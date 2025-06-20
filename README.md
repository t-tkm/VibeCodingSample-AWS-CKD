# AWS CDK Dify デプロイメントプロジェクト

このプロジェクトは、AWS CDKを使用してDifyアプリケーションを実行するためのインフラストラクチャをデプロイします。

## 概要

このプロジェクトでは、以下の構成でDifyアプリケーションをAWS上にデプロイします：

- **Windows Server**: 管理用サーバー（日本語版Windows Server 2022）
- **Linux Server**: Dify実行環境（Ubuntu 22.04、Docker Compose使用）
- **セキュアアクセス**: AWS Systems Manager Fleet Managerを使用したVPC内接続

詳細なアーキテクチャ図については、[付録](#付録)をご参照ください。

## ディレクトリ構造

```
.
├── README.md                      # プロジェクト説明
├── app.py                         # CDKアプリケーションのエントリーポイント
├── cdk.json                       # CDK設定ファイル
├── requirements.txt               # Pythonの依存関係
├── setup.py                       # セットアップスクリプト
├── source.bat                     # Windowsでの環境設定（CDK自動生成）
├── dify_cdk/                      # CDKスタック定義
│   ├── __init__.py
│   ├── dify_cdk_stack.py          # メインCDKスタック
│   ├── constructs/                # 再利用可能なコンストラクト
│   │   ├── __init__.py
│   │   ├── network.py             # ネットワーク関連のリソース
│   │   ├── security.py            # セキュリティグループなど
│   │   ├── windows_instance.py    # Windows VMの定義
│   │   └── linux_instance.py      # Linux VMの定義
│   └── config/                    # 設定ファイル
│       ├── __init__.py
│       └── config.py              # 環境設定
└── scripts/                       # ユーザーデータスクリプト
    ├── user_data_windows.ps1      # Windows VM初期化スクリプト
    └── user_data_ubuntu.sh        # Linux VM初期化スクリプト（Difyセットアップ含む）
```

## 前提条件

- Python 3.8以上
- AWS CDK v2
- AWS CLI（設定済み）
- AWS アカウントとアクセス権限

## セットアップ手順

1. 仮想環境を作成してアクティベート
```
python -m venv .venv
source .venv/bin/activate  # Linuxの場合
.venv\Scripts\activate     # Windowsの場合
```

2. 依存関係をインストール
```
pip install -r requirements.txt
```

3. （オプション）AWS認証情報を設定
   通常はAWS CLIで認証情報が設定されていますが、一時的な認証情報や異なるプロファイルを使用する場合は、以下の環境変数を設定できます：

```bash
export AWS_ACCESS_KEY_ID="<アクセスキーID>"
export AWS_SECRET_ACCESS_KEY="<シークレットアクセスキー>"
export AWS_SESSION_TOKEN="<セッショントークン>"
```

   **注意:** 上記はプレースホルダーです。実際の認証情報は以下の方法で取得してください：
   - AWS IAM Identity Center (SSO)
   - AWS STS (Security Token Service)
   - IAMユーザーのアクセスキー

4. （オプション）AWS リージョンを設定
```
export AWS_DEFAULT_REGION=ap-northeast-1
```

5. CDKをデプロイ
```
cdk deploy
```

## 使用方法

1. デプロイ完了後、AWS Management Consoleにログイン
2. AWS Systems Manager > Fleet Managerを開く
3. デプロイされたインスタンスに接続
4. Linux VMでは、Difyが `/opt/dify/docker` ディレクトリにインストールされ、自動的に起動
5. Windows VMからブラウザを使用して、Linux VMのプライベートIPアドレスにアクセスしてDifyを利用

## VMパスワードの変更方法

### Windows VMのパスワード変更

Windows VMのAdministratorパスワードを変更するには、以下の手順で`scripts/user_data_windows.ps1`ファイルを編集します：

```powershell
# 管理者パスワードの設定
$Password = ConvertTo-SecureString '新しいパスワード' -AsPlainText -Force
$UserAccount = Get-LocalUser -Name 'Administrator'
$UserAccount | Set-LocalUser -Password $Password
```

`'新しいパスワード'`の部分を、希望するパスワードに変更してください。パスワードは複雑さの要件（大文字、小文字、数字、特殊文字を含む）を満たす必要があります。

### Linux VMのパスワード変更

Linux VMでは、初期設定で`ubuntu`ユーザーがデフォルトで使用されます。パスワードを設定するには、`scripts/user_data_ubuntu.sh`ファイルに以下の行を追加します：

```bash
# ubuntuユーザーのパスワード設定
echo 'ubuntu:新しいパスワード' | chpasswd
```

この行を`# ubuntuユーザーをdockerグループに追加`の行の後に追加することをお勧めします。

## 注意事項

- このインフラストラクチャは、インターネットからの直接アクセスを許可していません
- Difyへのアクセスは、VPC内のリソースからのみ可能です
- 複数環境のデプロイには、`cdk.context.json`ファイルでスタック名やタグを変更してください
- パスワードはソースコードに平文で保存されるため、本番環境では適切なシークレット管理を検討してください

## 付録

### AWSアーキテクチャ図

```mermaid
%%{init: {'theme': 'base', 'themeVariables': { 'primaryColor': '#f0f0f0', 'primaryBorderColor': '#666', 'primaryTextColor': '#333', 'background': '#e0e0e0' }}}%%
graph LR
    subgraph AWS["AWS Cloud"]
        subgraph VPC["VPC"]
            subgraph PrivateSubnet["プライベートサブネット"]
                WinVM["Windows VM\n管理用サーバー"]
                LinuxVM["Linux VM\nUbuntu 22.04\nDify実行環境"]
            end
            
            subgraph PublicSubnet["パブリックサブネット"]
                SSMEndpoint["SSM\nエンドポイント"]
            end
        end
        
        SSM["AWS Systems Manager\n(Fleet Manager)"]
    end
    
    User["ユーザー"]
    
    User -->|"AWS Management\nConsole"| SSM
    SSM -->|"セキュアな接続"| SSMEndpoint
    SSMEndpoint -->|"RDP/SSH"| WinVM
    SSMEndpoint -->|"RDP/SSH"| LinuxVM
    WinVM -->|"HTTP (80)"| LinuxVM
    
    classDef default fill:#e0e0e0,stroke:#666,color:#333
    classDef aws fill:#d0d0d0,stroke:#666,color:#333
    classDef vpc fill:#c0c0c0,stroke:#666,color:#333
    classDef subnet fill:#b0b0b0,stroke:#666,color:#333
    classDef vm fill:#a0a0a0,stroke:#666,color:#333
    classDef user fill:#909090,stroke:#666,color:#333
    
    class AWS,SSM aws;
    class VPC vpc;
    class PrivateSubnet,PublicSubnet subnet;
    class WinVM,LinuxVM,SSMEndpoint vm;
    class User user;
```

### Difyコンテナ構成図

```mermaid
%%{init: {'theme': 'base', 'themeVariables': { 'primaryColor': '#f0f0f0', 'primaryBorderColor': '#666', 'primaryTextColor': '#333', 'background': '#e0e0e0' }}}%%
graph TD
    subgraph DockerCompose["Docker Compose環境"]
        Nginx["Nginx\nリバースプロキシ\nポート: 80"]
        API["API\nDify APIサーバー"]
        Worker["Worker\nCeleryワーカー"]
        Web["Web\nDifyフロントエンド"]
        DB["PostgreSQL\nデータベース"]
        Redis["Redis\nキャッシュ"]
        Weaviate["Weaviate\nベクトルデータベース"]
    end
    
    User["Windows VM\nブラウザ"]
    
    User -->|"HTTP (80)"| Nginx
    Nginx -->|"/"| Web
    Nginx -->|"/api/"| API
    API --> DB
    API --> Redis
    API --> Weaviate
    Worker --> DB
    Worker --> Redis
    Worker --> Weaviate
    Web --> API
    
    classDef default fill:#e0e0e0,stroke:#666,color:#333
    classDef container fill:#c0c0c0,stroke:#666,color:#333
    classDef db fill:#b0b0b0,stroke:#666,color:#333
    classDef cache fill:#a0a0a0,stroke:#666,color:#333
    classDef proxy fill:#909090,stroke:#666,color:#333
    classDef user fill:#808080,stroke:#666,color:#333
    
    class API,Worker,Web container;
    class DB,Weaviate db;
    class Redis cache;
    class Nginx proxy;
    class User user;
```
