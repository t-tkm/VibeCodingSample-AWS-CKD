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
            **kwargs: その他の引数
        """
        super().__init__(scope, id)
        
        # ユーザーデータスクリプトの読み込み
        user_data = self._load_user_data()
        
        # Ubuntu AMIの検索
        # 注: 実際のデプロイ時には、特定のAMI IDを指定することも可能
        ubuntu_ami = ec2.MachineImage.generic_linux({
            # デフォルトでは最新のUbuntu 22.04 AMIを使用
            # 各リージョンで利用可能なAMI IDを指定
            'ap-northeast-1': 'ami-0d52744d6551d851e',  # 東京リージョンのUbuntu 22.04
            'us-east-1': 'ami-0c7217cdde317cfec',       # バージニアリージョンのUbuntu 22.04
            'us-west-2': 'ami-0efcece6bed30fd98',       # オレゴンリージョンのUbuntu 22.04
            # 必要に応じて他のリージョンを追加
        })
        
        # インスタンスタイプの設定
        instance_type_obj = ec2.InstanceType(instance_type)
        
        # Linux VMの作成
        self.instance = ec2.Instance(
            self, "Instance",
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
            detailed_monitoring=False,  # コスト最適化
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
            self, "UserPassword",
            parameter_name=f"/dify/{id}/user-password",
            string_value="P@ssw0rd123!",  # 初期パスワード（本番環境では自動生成すべき）
            description="Linux VM user password",
            tier=ssm.ParameterTier.STANDARD,
            simple_name=False
        )
        
        # タグの追加
        Tags.of(self.instance).add("Name", f"{id}-instance")
        
        # 出力の設定
        CfnOutput(
            self, "InstanceId",
            value=self.instance.instance_id,
            description="Linux VM Instance ID"
        )
        
        CfnOutput(
            self, "PrivateIP",
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
        
        # スクリプトファイルのパス
        script_path = os.path.join("scripts", "user_data_ubuntu.sh")
        
        # スクリプトファイルが存在する場合は読み込む
        if os.path.exists(script_path):
            with open(script_path, "r") as f:
                script_content = f.read()
            user_data.add_commands(script_content)
        else:
            # デフォルトのスクリプト
            user_data.add_commands(
                "#!/bin/bash",
                "set -e",
                
                # システムの更新
                "apt-get update",
                "apt-get upgrade -y",
                
                # 必要なパッケージのインストール
                "apt-get install -y apt-transport-https ca-certificates curl software-properties-common git",
                
                # ユーザーの作成
                "useradd -m -s /bin/bash dify",
                "echo 'dify:P@ssw0rd123!' | chpasswd",
                "usermod -aG sudo dify",
                
                # asdfのインストール
                "sudo -u dify bash -c 'git clone https://github.com/asdf-vm/asdf.git /home/dify/.asdf --branch v0.13.1'",
                "sudo -u dify bash -c 'echo \". /home/dify/.asdf/asdf.sh\" >> /home/dify/.bashrc'",
                "sudo -u dify bash -c 'echo \". /home/dify/.asdf/completions/asdf.bash\" >> /home/dify/.bashrc'",
                
                # Node.js 22のインストールに必要な依存関係をインストール
                "apt-get install -y dirmngr gpg curl gawk",
                
                # asdfプラグインの追加とNode.js 22のインストール
                "sudo -u dify bash -c 'source /home/dify/.asdf/asdf.sh && asdf plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git'",
                "sudo -u dify bash -c 'source /home/dify/.asdf/asdf.sh && asdf install nodejs 22.1.0'",
                "sudo -u dify bash -c 'source /home/dify/.asdf/asdf.sh && asdf global nodejs 22.1.0'",
                
                # Dockerのインストール
                "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -",
                "add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\"",
                "apt-get update",
                "apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin",
                "usermod -aG docker dify",
                
                # Difyのインストールディレクトリの作成
                "mkdir -p /opt/dify/docker",
                "chown -R dify:dify /opt/dify",
                
                # Docker Composeファイルの作成
                "cat > /opt/dify/docker/docker-compose.yml << 'EOL'",
                "version: '3'",
                "services:",
                "  api:",
                "    image: langgenius/dify-api:latest",
                "    restart: always",
                "    environment:",
                "      - CONSOLE_API_URL=http://localhost:5001",
                "      - CONSOLE_WEB_URL=http://localhost:3000",
                "    volumes:",
                "      - ./data:/app/api/storage",
                "    depends_on:",
                "      - db",
                "      - redis",
                "  worker:",
                "    image: langgenius/dify-api:latest",
                "    restart: always",
                "    command: celery -A app.celery worker -l info",
                "    environment:",
                "      - CONSOLE_API_URL=http://localhost:5001",
                "      - CONSOLE_WEB_URL=http://localhost:3000",
                "    volumes:",
                "      - ./data:/app/api/storage",
                "    depends_on:",
                "      - db",
                "      - redis",
                "  web:",
                "    image: langgenius/dify-web:latest",
                "    restart: always",
                "    environment:",
                "      - CONSOLE_API_URL=http://localhost:5001",
                "    depends_on:",
                "      - api",
                "  db:",
                "    image: postgres:15",
                "    restart: always",
                "    environment:",
                "      - POSTGRES_USER=postgres",
                "      - POSTGRES_PASSWORD=postgres",
                "      - POSTGRES_DB=dify",
                "    volumes:",
                "      - ./data/postgres:/var/lib/postgresql/data",
                "  redis:",
                "    image: redis:6",
                "    restart: always",
                "    volumes:",
                "      - ./data/redis:/data",
                "  weaviate:",
                "    image: semitechnologies/weaviate:1.19.6",
                "    restart: always",
                "    volumes:",
                "      - ./data/weaviate:/var/lib/weaviate",
                "    environment:",
                "      - QUERY_DEFAULTS_LIMIT=20",
                "      - AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED=true",
                "      - PERSISTENCE_DATA_PATH=/var/lib/weaviate",
                "      - DEFAULT_VECTORIZER_MODULE=none",
                "      - ENABLE_MODULES=text2vec-openai",
                "      - CLUSTER_HOSTNAME=node1",
                "  nginx:",
                "    image: nginx:latest",
                "    restart: always",
                "    ports:",
                "      - \"80:80\"",
                "    volumes:",
                "      - ./nginx.conf:/etc/nginx/conf.d/default.conf",
                "    depends_on:",
                "      - api",
                "      - web",
                "EOL",
                
                # Nginxの設定ファイルの作成
                "cat > /opt/dify/docker/nginx.conf << 'EOL'",
                "server {",
                "    listen 80;",
                "    server_name localhost;",
                "",
                "    location / {",
                "        proxy_pass http://web:3000;",
                "        proxy_set_header Host $host;",
                "        proxy_set_header X-Real-IP $remote_addr;",
                "    }",
                "",
                "    location /api/ {",
                "        proxy_pass http://api:5001/;",
                "        proxy_set_header Host $host;",
                "        proxy_set_header X-Real-IP $remote_addr;",
                "    }",
                "}",
                "EOL",
                
                # Docker Compose Override ファイルの作成
                "cat > /opt/dify/docker/docker-compose.override.yml << 'EOL'",
                "version: '3'",
                "services:",
                "  api:",
                "    environment:",
                "      - CONSOLE_API_URL=http://localhost/api",
                "      - CONSOLE_WEB_URL=http://localhost",
                "  worker:",
                "    environment:",
                "      - CONSOLE_API_URL=http://localhost/api",
                "      - CONSOLE_WEB_URL=http://localhost",
                "  web:",
                "    environment:",
                "      - CONSOLE_API_URL=http://localhost/api",
                "EOL",
                
                # 起動スクリプトの作成
                "cat > /opt/dify/start.sh << 'EOL'",
                "#!/bin/bash",
                "cd /opt/dify/docker",
                "docker compose up -d",
                "EOL",
                
                "chmod +x /opt/dify/start.sh",
                
                # 自動起動の設定
                "cat > /etc/systemd/system/dify.service << 'EOL'",
                "[Unit]",
                "Description=Dify AI Application",
                "After=docker.service",
                "Requires=docker.service",
                "",
                "[Service]",
                "Type=oneshot",
                "RemainAfterExit=yes",
                "WorkingDirectory=/opt/dify",
                "ExecStart=/opt/dify/start.sh",
                "User=dify",
                "Group=dify",
                "",
                "[Install]",
                "WantedBy=multi-user.target",
                "EOL",
                
                "systemctl enable dify.service",
                "systemctl start dify.service"
            )
        
        return user_data
