#!/bin/bash
# Difyインストール用Ubuntuユーザーデータスクリプト

# エラー時に停止
set -e

# ログファイルの設定
LOGFILE="/var/log/user-data.log"
exec > >(tee -a ${LOGFILE}) 2>&1

echo "Starting Dify installation script at $(date)"

# システムの更新
echo "Updating system packages..."
apt-get update -y
apt-get upgrade -y

# 必要なパッケージのインストール
echo "Installing required packages..."
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
    unzip

# Dockerのインストール
echo "Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Dockerを開始し有効化
systemctl start docker
systemctl enable docker

# ubuntuユーザーをdockerグループに追加
usermod -aG docker ubuntu

# ubuntuユーザーのパスワード設定
echo 'ubuntu:P@ssw0rd123!' | chpasswd
echo "Ubuntu user password has been set."

# SSMエージェントのインストール - AMIに既に設定済みのためコメントアウト
# echo "Checking and installing SSM Agent..."
# # snapコマンドでSSMエージェントがインストール済みか確認
# if snap list amazon-ssm-agent &>/dev/null; then
#     echo "SSM Agent is already installed via snap. Skipping installation."
# else
#     # debパッケージでインストールを試みる
#     mkdir -p /tmp/ssm
#     cd /tmp/ssm
#     wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
#     # エラーが発生しても続行するために set +e を使用
#     set +e
#     dpkg -i amazon-ssm-agent.deb
#     set -e
#     # サービスの有効化と開始を試みる
#     systemctl enable amazon-ssm-agent || true
#     systemctl start amazon-ssm-agent || true
# fi

# Dify用ディレクトリを作成
echo "Creating Dify installation directory..."
mkdir -p /opt/dify
cd /opt/dify

# Difyリポジトリをクローン
echo "Cloning Dify repository..."
git clone https://github.com/langgenius/dify.git .

# docker用ディレクトリを作成
mkdir -p /opt/dify/docker
cd docker

# docker-composeファイルをdockerディレクトリにコピー
cp docker-compose.yaml /opt/dify/docker/
cp -r volumes /opt/dify/docker/
cp -r nginx /opt/dify/docker/

# dockerディレクトリに移動
cd /opt/dify/docker

# カスタム設定でdocker-compose.override.ymlを作成
echo "Creating Docker Compose override configuration..."
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
    restart: unless-stopped

  # ワーカーサービス
  worker:
    environment:
      - STORAGE_TYPE=local
      - STORAGE_LOCAL_PATH=/app/api/storage
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
chown -R ubuntu:ubuntu /opt/dify

# Dify用systemdサービスを作成
echo "Setting up auto-start service..."
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
# rootユーザーで実行（Dockerへのアクセス権限の問題を回避）
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

# Difyサービスを有効化し開始
systemctl daemon-reload
systemctl enable dify.service

# Dockerが完全に準備できるまで待機
sleep 30

# Difyを開始
systemctl start dify.service

# 簡単なステータス確認スクリプトを作成
echo "Creating status check script..."
cat > /opt/dify/check_status.sh << 'EOF'
#!/bin/bash
echo "Difyサービスステータス:"
systemctl status dify.service --no-pager

echo -e "\nDockerコンテナ:"
cd /opt/dify/docker && docker compose ps

echo -e "\nDifyアプリケーションURL:"
echo "http://$(hostname -I | awk '{print $1}')"
EOF

chmod +x /opt/dify/check_status.sh

# ファイアウォールの設定
echo "Configuring firewall..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
echo "y" | ufw enable

# 完了をログに記録
echo "Difyのインストールが正常に完了しました！" > /var/log/dify-setup.log
echo "インストール完了時刻: $(date)" >> /var/log/dify-setup.log
echo "Difyアクセス先: http://$(hostname -I | awk '{print $1}')" >> /var/log/dify-setup.log

echo "Dify installation completed successfully at $(date)"
