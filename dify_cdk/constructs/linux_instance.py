# -*- coding: utf-8 -*-

"""
Linux VMコンストラクト

このモジュールは、Linux VMインスタンスを定義します。
"""

import os
from constructs import Construct
from aws_cdk import aws_ec2 as ec2
from aws_cdk import aws_iam as iam
from aws_cdk import aws_ssm as ssm
from aws_cdk import Tags, CfnOutput


class LinuxInstanceConstruct(Construct):
    """Linux VMインスタンスを作成するコンストラクト"""

    def __init__(
        self,
        scope: Construct,
        id: str,
        vpc: ec2.Vpc,
        security_group: ec2.SecurityGroup,
        instance_role: iam.Role,
        instance_type: str,
        ami_name_pattern: str,
        config,
        **kwargs
    ):
        """
        コンストラクタ

        Args:
            scope: 親スコープ
            id: コンストラクトID
            vpc: VPCインスタンス
            security_group: セキュリティグループ
            instance_role: IAMロール
            instance_type: インスタンスタイプ
            ami_name_pattern: AMI名のパターン
            config: 設定オブジェクト
            **kwargs: その他の引数
        """
        super().__init__(scope, id)

        self.config = config

        # ユーザーデータスクリプトの読み込み
        user_data = self._load_user_data()

        # Ubuntu AMIの設定
        ubuntu_ami = ec2.MachineImage.generic_linux({
            'ap-northeast-1': 'ami-0d52744d6551d851e',  # 東京リージョンのUbuntu 22.04
            'us-east-1': 'ami-0c7217cdde317cfec',       # バージニアリージョンのUbuntu 22.04
            'us-west-2': 'ami-0efcece6bed30fd98',       # オレゴンリージョンのUbuntu 22.04
        })

        # インスタンスタイプの設定
        instance_type_obj = ec2.InstanceType(instance_type)

        # Linux VMの作成
        self.instance = ec2.Instance(
            self,
            "Instance",
            vpc=vpc,
            instance_type=instance_type_obj,
            machine_image=ubuntu_ami,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
            security_group=security_group,
            role=instance_role,
            user_data=user_data,
            require_imdsv2=True,  # セキュリティ強化
            detailed_monitoring=True,  # 詳細なモニタリングを優先
            user_data_causes_replacement=True,
            block_devices=[
                ec2.BlockDevice(
                    device_name="/dev/sda1",
                    volume=ec2.BlockDeviceVolume.ebs(
                        volume_size=100,  # 100GB
                        volume_type=ec2.EbsDeviceVolumeType.GP3,
                        encrypted=True
                    )
                )
            ]
        )

        # SSMパラメータストアにユーザーパスワードを保存
        user_password = ssm.StringParameter(
            self,
            "UserPassword",
            parameter_name=f"/dify/{id}/user-password",
            string_value=config.linux_admin_password,
            description="Linux VM user password",
            tier=ssm.ParameterTier.STANDARD,
            simple_name=False
        )

        # タグの追加
        Tags.of(self.instance).add("Name", f"{id}-instance")

        # 出力の設定
        CfnOutput(
            self,
            "InstanceId",
            value=self.instance.instance_id,
            description="Linux VM Instance ID"
        )

        CfnOutput(
            self,
            "PrivateIP",
            value=self.instance.instance_private_ip,
            description="Linux VM Private IP Address"
        )

    def _load_user_data(self) -> ec2.UserData:
        """
        ユーザーデータスクリプトを読み込む

        Returns:
            UserDataインスタンス
        """
        user_data = ec2.UserData.for_linux()

        # 環境変数の設定
        user_data.add_commands(
            f"export admin_username='{self.config.linux_admin_username}'",
            f"export admin_password='{self.config.linux_admin_password}'"
        )

        # ユーザーデータスクリプトの追加
        user_data.add_commands(self._get_user_data_script())

        return user_data

    def _get_user_data_script(self) -> str:
        """
        ユーザーデータスクリプトを取得

        Returns:
            ユーザーデータスクリプト文字列
        """
        return """
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

# デフォルト値の設定
admin_username=${admin_username:-ubuntu}
admin_password=${admin_password:-P@ssw0rd123!}
enable_cloudwatch_agent=${enable_cloudwatch_agent:-false}

# ユーザーパスワード設定
log "Setting ${admin_username} user password..."
echo "${admin_username}:${admin_password}" | chpasswd

# SSH設定
log "Configuring SSH settings..."
sed -i 's/#PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart sshd

# システムの更新（コメントアウト）
# log "Updating system packages..."
# export DEBIAN_FRONTEND=noninteractive
# apt-get update -y
# apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

# 必要最小限のパッケージのインストール（DifyとDocker用）
log "Installing required packages for Dify and Docker..."
apt-get update -y
apt-get install -y \\
    apt-transport-https \\
    ca-certificates \\
    curl \\
    gnupg \\
    lsb-release \\
    git

# SSMエージェント状態確認（コメントアウト）
# log "Checking SSM Agent status..."
# if systemctl is-active --quiet amazon-ssm-agent; then
#     log "SSM Agent is already running"
#     systemctl status amazon-ssm-agent --no-pager | tee -a /var/log/user-data.log
# else
#     log "SSM Agent is not running, attempting to start..."
#     systemctl start amazon-ssm-agent
#     systemctl enable amazon-ssm-agent
#     sleep 5
#     if systemctl is-active --quiet amazon-ssm-agent; then
#         log "SSM Agent started successfully"
#     else
#         log "ERROR: Failed to start SSM Agent"
#     fi
# fi

# Session Manager Plugin のインストール（コメントアウト）
# log "Checking if Session Manager Plugin is already installed..."
# if ! command -v session-manager-plugin &> /dev/null; then
#     log "Session Manager Plugin not found, installing..."
#     curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
#     dpkg -i session-manager-plugin.deb
#     rm -f session-manager-plugin.deb
# fi

# Dockerのインストール
log "Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Dockerサービスの開始と有効化
systemctl start docker
systemctl enable docker

# ubuntuユーザーをdockerグループに追加
usermod -aG docker ${admin_username}

# Difyのインストール
log "Installing Dify..."
cd /opt

# Difyのクローン
git clone https://github.com/langgenius/dify.git dify
cd dify/docker

# 環境設定ファイルの作成
log "Creating environment configuration..."
cp .env.example .env

# 基本的な設定を.envファイルに追加
# 動的にIPアドレスを取得
PRIVATE_IP=$(hostname -I | awk '{print $1}')
SECRET_KEY_VALUE="dify_secret_key_$(openssl rand -hex 32)"

cat >> .env << EOF
# 基本設定
EDITION=SELF_HOSTED
CONSOLE_URL=http://${PRIVATE_IP}:3000
API_URL=http://${PRIVATE_IP}:5001
SERVICE_API_URL=http://${PRIVATE_IP}:5001
APP_URL=http://${PRIVATE_IP}:3000

# データベース設定
DB_HOST=db
DB_PORT=5432
DB_USERNAME=postgres
DB_PASSWORD=difyai123456
DB_DATABASE=dify

# Redis設定
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_USERNAME=
REDIS_PASSWORD=
REDIS_DB=0

# ストレージ設定
STORAGE_TYPE=local
LOCAL_STORAGE_PATH=./storage

# セキュリティ設定
SECRET_KEY=${SECRET_KEY_VALUE}
EOF

# Docker ComposeでDifyを起動
log "Starting Dify with Docker Compose..."
docker compose up -d

# データベースとRedisが起動するまで待機
log "Waiting for database and Redis to be ready..."
sleep 60

# データベース接続テスト
log "Testing database connection..."
docker compose exec -T db pg_isready -U postgres || true

# ファイアウォールの設定
log "Configuring firewall..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 3000/tcp
ufw allow 5001/tcp
echo "y" | ufw enable

# Difyアプリケーションが完全に起動するまで待機
log "Waiting for Dify application to be fully ready..."
sleep 30

# Difyコンテナの状態確認
log "Checking Dify containers status..."
cd /opt/dify/docker && docker compose ps

# エラーログがあれば表示
log "Checking for any container errors..."
cd /opt/dify/docker && docker compose logs --tail=20 | grep -i error || true

# 簡単なステータス確認スクリプトを作成
log "Creating status check script..."
cat > /opt/dify/check_status.sh << 'EOF'
#!/bin/bash
echo "Difyコンテナステータス:"
cd /opt/dify/docker && docker compose ps

echo -e "\\nDifyアプリケーションURL:"
echo "http://$(hostname -I | awk '{print $1}'):3000"

echo -e "\\nシステム情報:"
echo "Docker: $(docker --version)"
echo "Docker Compose: $(docker compose version)"

echo -e "\\nDifyログ（最新10行）:"
cd /opt/dify/docker && docker compose logs --tail=10
EOF

chmod +x /opt/dify/check_status.sh

# セットアップ完了
log "Dify installation completed successfully!"
log "System information:"
log "Docker: $(docker --version)"
log "Docker Compose: $(docker compose version)"

# 完了をログに記録
echo "Difyのインストールが正常に完了しました！" > /var/log/dify-setup.log
echo "インストール完了時刻: $(date)" >> /var/log/dify-setup.log
echo "Difyアクセス先: http://$(hostname -I | awk '{print $1}'):3000" >> /var/log/dify-setup.log

# 最終状態確認
log "Final status check:"
sleep 10
cd /opt/dify/docker && docker compose ps | tee -a /var/log/user-data.log

log "Dify installation script completed at $(date)"
"""