#!/bin/bash
# Ubuntu VM 初期化スクリプト

# エラー時に停止
set -e

# ログファイルの設定
LOGFILE="/var/log/user-data.log"
exec > >(tee -a ${LOGFILE}) 2>&1

echo "Starting Ubuntu VM initialization script at $(date)"

# システムの更新
echo "Updating system packages..."
apt-get update
apt-get upgrade -y

# 必要なパッケージのインストール
echo "Installing required packages..."
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common \
    gnupg \
    lsb-release \
    git \
    vim \
    htop \
    net-tools \
    unzip

# ユーザーの作成
echo "Creating dify user..."
useradd -m -s /bin/bash dify
echo 'dify:P@ssw0rd123!' | chpasswd
usermod -aG sudo dify

# Dockerのインストール
echo "Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
usermod -aG docker dify

# SSMエージェントのインストール
echo "Installing SSM Agent..."
mkdir -p /tmp/ssm
cd /tmp/ssm
wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
dpkg -i amazon-ssm-agent.deb
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Difyのインストールディレクトリの作成
echo "Creating Dify installation directory..."
mkdir -p /opt/dify/docker
chown -R dify:dify /opt/dify

# Docker Composeファイルの作成
echo "Creating Docker Compose configuration..."
cat > /opt/dify/docker/docker-compose.yml << 'EOL'
version: '3'
services:
  api:
    image: langgenius/dify-api:latest
    restart: always
    environment:
      - CONSOLE_API_URL=http://localhost:5001
      - CONSOLE_WEB_URL=http://localhost:3000
    volumes:
      - ./data:/app/api/storage
    depends_on:
      - db
      - redis
  worker:
    image: langgenius/dify-api:latest
    restart: always
    command: celery -A app.celery worker -l info
    environment:
      - CONSOLE_API_URL=http://localhost:5001
      - CONSOLE_WEB_URL=http://localhost:3000
    volumes:
      - ./data:/app/api/storage
    depends_on:
      - db
      - redis
  web:
    image: langgenius/dify-web:latest
    restart: always
    environment:
      - CONSOLE_API_URL=http://localhost:5001
    depends_on:
      - api
  db:
    image: postgres:15
    restart: always
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_DB=dify
    volumes:
      - ./data/postgres:/var/lib/postgresql/data
  redis:
    image: redis:6
    restart: always
    volumes:
      - ./data/redis:/data
  weaviate:
    image: semitechnologies/weaviate:1.19.6
    restart: always
    volumes:
      - ./data/weaviate:/var/lib/weaviate
    environment:
      - QUERY_DEFAULTS_LIMIT=20
      - AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED=true
      - PERSISTENCE_DATA_PATH=/var/lib/weaviate
      - DEFAULT_VECTORIZER_MODULE=none
      - ENABLE_MODULES=text2vec-openai
      - CLUSTER_HOSTNAME=node1
  nginx:
    image: nginx:latest
    restart: always
    ports:
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf
    depends_on:
      - api
      - web
EOL

# Nginxの設定ファイルの作成
echo "Creating Nginx configuration..."
cat > /opt/dify/docker/nginx.conf << 'EOL'
server {
    listen 80;
    server_name localhost;

    location / {
        proxy_pass http://web:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /api/ {
        proxy_pass http://api:5001/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOL

# Docker Compose Override ファイルの作成
echo "Creating Docker Compose override configuration..."
cat > /opt/dify/docker/docker-compose.override.yml << 'EOL'
version: '3'
services:
  api:
    environment:
      - CONSOLE_API_URL=http://localhost/api
      - CONSOLE_WEB_URL=http://localhost
  worker:
    environment:
      - CONSOLE_API_URL=http://localhost/api
      - CONSOLE_WEB_URL=http://localhost
  web:
    environment:
      - CONSOLE_API_URL=http://localhost/api
EOL

# 起動スクリプトの作成
echo "Creating startup script..."
cat > /opt/dify/start.sh << 'EOL'
#!/bin/bash
cd /opt/dify/docker
docker compose up -d
EOL

chmod +x /opt/dify/start.sh
chown dify:dify /opt/dify/start.sh

# 自動起動の設定
echo "Setting up auto-start service..."
cat > /etc/systemd/system/dify.service << 'EOL'
[Unit]
Description=Dify AI Application
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/dify
ExecStart=/opt/dify/start.sh
User=dify
Group=dify

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable dify.service
systemctl start dify.service

# ファイアウォールの設定
echo "Configuring firewall..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
echo "y" | ufw enable

echo "Ubuntu VM initialization completed successfully at $(date)"
