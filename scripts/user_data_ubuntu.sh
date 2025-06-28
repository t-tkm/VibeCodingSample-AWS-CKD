#!/bin/bash
# Difyインストール用Ubuntuユーザーデータスクリプト

# エラーハンドリングの設定
set -e
set -o pipefail

# ログ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/user-data.log
}

# エラーハンドリング関数
handle_error() {
    log "ERROR: An error occurred on line $1"
    exit 1
}

# エラートラップの設定
trap 'handle_error $LINENO' ERR

# スクリプト開始
log "Starting Dify installation script..."

# IMDSv2対応のメタデータ取得ヘルパー関数
get_metadata() {
    local path="$1"
    local token=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)
    if [ -n "$token" ]; then
        curl -H "X-aws-ec2-metadata-token: $token" -s "http://169.254.169.254/latest/meta-data/${path}"
    else
        log "ERROR: Failed to get IMDS token"
        return 1
    fi
}

# インスタンス情報の取得（ログ用）
log "Getting instance information..."
INSTANCE_ID=$(get_metadata "instance-id" || echo "unknown")
REGION=$(get_metadata "placement/region" || echo "unknown")
log "Instance ID: $INSTANCE_ID"
log "Region: $REGION"

# デフォルト値の設定（CDKから環境変数として渡される）
admin_username=${admin_username:-ubuntu}
admin_password=${admin_password:-P@ssw0rd123!}
enable_cloudwatch_agent=${enable_cloudwatch_agent:-false}

# ubuntuユーザーのパスワード設定
log "Setting ${admin_username} user password..."
echo "${admin_username}:${admin_password}" | chpasswd

# SSH設定でパスワード認証を有効化
log "Enabling SSH password authentication..."
sed -i 's/#PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd

# システムの更新
log "Updating system packages..."
apt-get update -y
apt-get upgrade -y

# 必要なパッケージのインストール
log "Installing required packages..."
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    vim \
    htop \
    net-tools \
    unzip \
    wget

# Session Manager Plugin のインストール
log "Installing Session Manager Plugin..."
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
dpkg -i session-manager-plugin.deb

# CloudWatch agent のインストール（有効化されている場合）
if [ "${enable_cloudwatch_agent}" = "true" ]; then
    log "Installing CloudWatch Agent..."
    wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
    dpkg -i -E ./amazon-cloudwatch-agent.deb
    
    # IMDSv2対応のCloudWatch設定
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWEOF'
{
    "agent": {
        "region": "auto"
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/user-data.log",
                        "log_group_name": "/aws/ec2/dify-logs",
                        "log_stream_name": "{instance_id}/dify-setup",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "/var/log/syslog",
                        "log_group_name": "/aws/ec2/dify-logs",
                        "log_stream_name": "{instance_id}/syslog",
                        "timezone": "UTC"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "AWS/EC2/Dify",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle"
                ],
                "metrics_collection_interval": 300
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 300
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 300,
                "resources": [
                    "*"
                ]
            }
        }
    }
}
CWEOF
    
    # CloudWatch agentの開始（IMDSv2対応）
    export AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE=IPv4
    export AWS_EC2_METADATA_SERVICE_NUM_ATTEMPTS=3
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
    log "CloudWatch Agent installed and started"
fi

# Dockerのインストール
log "Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Dockerを開始し有効化
systemctl start docker
systemctl enable docker

# ubuntuユーザーをdockerグループに追加
usermod -aG docker "${admin_username}"

# Docker Compose のインストール（standalone版）
log "Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Dify用ディレクトリを作成
log "Creating Dify installation directory..."
mkdir -p /opt/dify
cd /opt/dify

# Difyリポジトリをクローン
log "Cloning Dify repository..."
git clone https://github.com/langgenius/dify.git .

# dockerディレクトリに移動
cd /opt/dify/docker

# カスタム設定でdocker-compose.override.ymlを作成
log "Creating Docker Compose override configuration..."
cat > docker-compose.override.yml << 'EOF'
version: '3'
services:
  # APIサービス
  api:
    environment:
      - SECRET_KEY=sk-9f73s3ljTXVcMT3Blb3ljTqtsKiGHXVcMT3BlbkFJLK7U
      - CONSOLE_WEB_URL=http://localhost
      - CONSOLE_API_URL=http://localhost
      - SERVICE_API_URL=http://localhost
      - APP_WEB_URL=http://localhost
      - FILES_URL=http://localhost
      - STORAGE_TYPE=local
      - STORAGE_LOCAL_PATH=/app/api/storage
      # IMDSv2对応
      - AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE=IPv4
      - AWS_EC2_METADATA_SERVICE_NUM_ATTEMPTS=3
    restart: unless-stopped

  # ワーカーサービス
  worker:
    environment:
      - STORAGE_TYPE=local
      - STORAGE_LOCAL_PATH=/app/api/storage
      # IMDSv2対応
      - AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE=IPv4
      - AWS_EC2_METADATA_SERVICE_NUM_ATTEMPTS=3
    restart: unless-stopped

  # Webサービス
  web:
    restart: unless-stopped

  # データベース
  db:
    restart: unless-stopped
    volumes:
      - db_data:/var/lib/postgresql/data

  # Redis
  redis:
    restart: unless-stopped
    volumes:
      - redis_data:/data

  # Weaviate
  weaviate:
    restart: unless-stopped

  # Nginxリバースプロキシ
  nginx:
    ports:
      - "80:80"
    restart: unless-stopped

volumes:
  db_data:
  redis_data:
EOF

# 適切な権限を設定
chown -R "${admin_username}:${admin_username}" /opt/dify

# Dify用systemdサービスを作成
log "Setting up auto-start service..."
cat > /etc/systemd/system/dify.service << 'EOF'
[Unit]
Description=Dify Application
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/dify/docker
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

# Difyサービスを有効化
systemctl daemon-reload
systemctl enable dify.service

# ファイアウォールの設定
log "Configuring firewall..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
echo "y" | ufw enable

# Dockerが完全に準備できるまで待機
log "Waiting for Docker to be ready..."
sleep 30

# Difyを開始
log "Starting Dify..."
systemctl start dify.service

# 簡単なステータス確認スクリプトを作成
log "Creating status check script..."
cat > /opt/dify/check_status.sh << 'EOF'
#!/bin/bash
echo "Difyサービスステータス:"
systemctl status dify.service --no-pager

echo -e "\nDockerコンテナ:"
cd /opt/dify/docker && docker compose ps

echo -e "\nDifyアプリケーションURL:"
echo "http://$(hostname -I | awk '{print $1}')"

echo -e "\nシステム情報:"
echo "Docker: $(docker --version)"
echo "Docker Compose: $(docker compose version)"

echo -e "\nIMDSv2対応状況:"
echo "AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE: $AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE"
echo "AWS_EC2_METADATA_SERVICE_NUM_ATTEMPTS: $AWS_EC2_METADATA_SERVICE_NUM_ATTEMPTS"

# IMDSv2テスト
echo -e "\nIMDSv2テスト:"
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s --max-time 10)
if [ -n "$TOKEN" ]; then
    echo "✓ IMDSv2トークン取得成功"
    INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s --max-time 10 "http://169.254.169.254/latest/meta-data/instance-id")
    echo "✓ インスタンスID: $INSTANCE_ID"
else
    echo "✗ IMDSv2トークン取得失敗"
fi
EOF

chmod +x /opt/dify/check_status.sh

# IMDSv2診断用の個別スクリプトも作成
cat > /opt/dify/imds_test.sh << 'EOF'
#!/bin/bash
echo "=== IMDSv2診断テスト ==="

# 環境変数の確認
echo "環境変数:"
echo "  AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE: $AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE"
echo "  AWS_EC2_METADATA_SERVICE_NUM_ATTEMPTS: $AWS_EC2_METADATA_SERVICE_NUM_ATTEMPTS"

# IMDSv1テスト（失敗するはず）
echo -e "\nIMDSv1テスト（失敗する予定）:"
IMDSv1_RESULT=$(curl -s --max-time 5 "http://169.254.169.254/latest/meta-data/instance-id" 2>&1)
if [ $? -eq 0 ] && [ -n "$IMDSv1_RESULT" ]; then
    echo "⚠️  IMDSv1が有効: $IMDSv1_RESULT"
else
    echo "✓ IMDSv1が正しく無効化されています"
fi

# IMDSv2テスト
echo -e "\nIMDSv2テスト:"
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s --max-time 10)
if [ -n "$TOKEN" ]; then
    echo "✓ IMDSv2トークン取得成功"
    echo "  トークン: ${TOKEN:0:20}..."
    
    # 各種メタデータの取得テスト
    echo "  インスタンスID: $(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s --max-time 10 "http://169.254.169.254/latest/meta-data/instance-id")"
    echo "  リージョン: $(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s --max-time 10 "http://169.254.169.254/latest/meta-data/placement/region")"
    echo "  インスタンスタイプ: $(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s --max-time 10 "http://169.254.169.254/latest/meta-data/instance-type")"
else
    echo "✗ IMDSv2トークン取得失敗"
fi

# SSM Agentの状態確認
echo -e "\nSSM Agent状態:"
if systemctl is-active --quiet amazon-ssm-agent; then
    echo "✓ SSM Agent実行中"
else
    echo "✗ SSM Agent停止中"
fi

# CloudWatch Agentの状態確認（インストールされている場合）
echo -e "\nCloudWatch Agent状態:"
if systemctl is-active --quiet amazon-cloudwatch-agent >/dev/null 2>&1; then
    echo "✓ CloudWatch Agent実行中"
elif systemctl list-unit-files | grep -q amazon-cloudwatch-agent; then
    echo "⚠️  CloudWatch Agentがインストールされているが停止中"
else
    echo "- CloudWatch Agentはインストールされていません"
fi

echo -e "\n=== 診断完了 ==="
EOF

chmod +x /opt/dify/imds_test.sh

# セットアップ完了
log "Dify installation completed successfully!"
log "System information:"
log "Docker: $(docker --version)"
log "Docker Compose: $(docker compose version)"

# 完了をログに記録
echo "Difyのインストールが正常に完了しました！" > /var/log/dify-setup.log
echo "インストール完了時刻: $(date)" >> /var/log/dify-setup.log
echo "Difyアクセス先: http://$(hostname -I | awk '{print $1}')" >> /var/log/dify-setup.log

# 最終状態確認
log "Final status check:"
sleep 10
cd /opt/dify/docker && docker compose ps | tee -a /var/log/user-data.log

log "Dify installation script completed at $(date)"
