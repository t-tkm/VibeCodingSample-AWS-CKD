# Windows VM 初期化スクリプト

# ログファイルの設定
$LogFile = "C:\Windows\Temp\UserDataLog.txt"
function Write-Log {
    param($Message)
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$TimeStamp - $Message" | Out-File -FilePath $LogFile -Append
    Write-Host "$TimeStamp - $Message"
}

Write-Log "Windows VM 初期化開始"

# IMDSv2対応のメタデータ取得ヘルパー関数
function Get-InstanceMetadata {
    param(
        [string]$Path
    )
    
    try {
        # IMDSv2トークンの取得
        $tokenUri = "http://169.254.169.254/latest/api/token"
        $headers = @{
            "X-aws-ec2-metadata-token-ttl-seconds" = "21600"
        }
        $token = Invoke-RestMethod -Uri $tokenUri -Method Put -Headers $headers -ErrorAction Stop
        
        if ($token) {
            # メタデータの取得
            $metadataUri = "http://169.254.169.254/latest/meta-data/$Path"
            $metadataHeaders = @{
                "X-aws-ec2-metadata-token" = $token
            }
            return Invoke-RestMethod -Uri $metadataUri -Headers $metadataHeaders -ErrorAction Stop
        }
    }
    catch {
        Write-Log "Failed to get metadata for path: $Path - $($_.Exception.Message)"
        return $null
    }
}

# インスタンス情報の取得（ログ用）
Write-Log "Getting instance information..."
$instanceId = Get-InstanceMetadata -Path "instance-id"
$region = Get-InstanceMetadata -Path "placement/region"
Write-Log "Instance ID: $instanceId"
Write-Log "Region: $region"

# 実行ポリシーの設定
Set-ExecutionPolicy Unrestricted -Force
Write-Log "実行ポリシー設定完了"

# 管理者パスワードの設定（手動で成功したコマンドを使用）
try {
    Write-Log "Administratorアカウントの設定開始"
    
    # Administratorアカウントを有効化
    $result1 = net user Administrator /active:yes
    Write-Log "Administratorアカウント有効化: $result1"
    
    # パスワードを設定
    $password = if ($env:WINDOWS_ADMIN_PASSWORD) { $env:WINDOWS_ADMIN_PASSWORD } else { "Admin@2024#Secure" }
    $username = if ($env:WINDOWS_ADMIN_USERNAME) { $env:WINDOWS_ADMIN_USERNAME } else { "Administrator" }
    $result2 = net user $username $password
    Write-Log "パスワード設定: $result2"
    
    # パスワード期限なしに設定
    $result3 = net user Administrator /expires:never
    Write-Log "パスワード期限設定: $result3"
    
    # 設定確認
    $adminInfo = net user Administrator
    Write-Log "Administratorアカウント設定完了"
    Write-Log "アカウント情報: $adminInfo"
}
catch {
    Write-Log "Administratorアカウント設定エラー: $($_.Exception.Message)"
}

# RDP接続を有効化
try {
    # RDPを有効化
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -Value 0
    Write-Log "RDP有効化完了"
    
    # ファイアウォールでRDPを許可
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
    Write-Log "RDPファイアウォール許可完了"
    
    # NLA（Network Level Authentication）を無効化
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -name "UserAuthentication" -Value 0
    Write-Log "NLA無効化完了"
}
catch {
    Write-Log "RDP設定エラー: $($_.Exception.Message)"
}

# 日本語環境の設定
try {
    # タイムゾーンを東京に設定
    Set-TimeZone -Id "Tokyo Standard Time"
    Write-Log "タイムゾーン設定完了"
    
    # システムロケールを日本語に設定
    Set-WinSystemLocale ja-JP
    Write-Log "システムロケール設定完了"
}
catch {
    Write-Log "日本語環境設定エラー: $($_.Exception.Message)"
}

# ファイアウォールの設定
try {
    New-NetFirewallRule -DisplayName 'Allow HTTP' -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName 'Allow HTTPS' -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName 'Allow RDP' -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow -ErrorAction SilentlyContinue
    Write-Log "ファイアウォール設定完了"
}
catch {
    Write-Log "ファイアウォール設定エラー: $($_.Exception.Message)"
}

# 必要な機能のインストール
try {
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools -ErrorAction SilentlyContinue
    Write-Log "IIS機能インストール完了"
}
catch {
    Write-Log "IIS機能インストールエラー: $($_.Exception.Message)"
}

# Chocolateyのインストール
try {
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    Write-Log "Chocolateyインストール完了"
    
    # 基本的なソフトウェアのインストール
    choco install -y googlechrome --ignore-checksums
    choco install -y notepadplusplus --ignore-checksums
    Write-Log "基本ソフトウェアインストール完了"
}
catch {
    Write-Log "Chocolatey関連エラー: $($_.Exception.Message)"
}

# SSMエージェントの設定と更新
try {
    Write-Log "SSMエージェントの設定開始"
    
    # IMDSv2対応の環境変数を設定
    [Environment]::SetEnvironmentVariable("AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE", "IPv4", "Machine")
    [Environment]::SetEnvironmentVariable("AWS_EC2_METADATA_SERVICE_NUM_ATTEMPTS", "3", "Machine")
    Write-Log "IMDSv2環境変数設定完了"
    
    # 既存のSSMエージェントサービスの状態を確認
    $ssmService = Get-Service -Name "AmazonSSMAgent" -ErrorAction SilentlyContinue
    if ($ssmService) {
        Write-Log "既存のSSMエージェントサービスが見つかりました: $($ssmService.Status)"
        if ($ssmService.Status -eq "Running") {
            Stop-Service AmazonSSMAgent -Force -ErrorAction SilentlyContinue
            Write-Log "SSMエージェントサービスを停止しました"
        }
    } else {
        Write-Log "SSMエージェントサービスが見つかりません。新規インストールを実行します"
    }
    
    # Windows Server 2019用のSSMエージェントをダウンロード
    $ssmUrl = "https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/windows_amd64/AmazonSSMAgentSetup.exe"
    $ssmInstaller = "$env:TEMP\AmazonSSMAgentSetup.exe"
    
    Write-Log "SSMエージェントをダウンロード中: $ssmUrl"
    
    # TLS設定とダウンロード
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($ssmUrl, $ssmInstaller)
    Write-Log "SSMエージェントダウンロード完了"
    
    # インストーラーの実行
    if (Test-Path $ssmInstaller) {
        Write-Log "SSMエージェントインストール開始"
        $installProcess = Start-Process -FilePath $ssmInstaller -ArgumentList '/S' -Wait -PassThru -ErrorAction SilentlyContinue
        
        if ($installProcess.ExitCode -eq 0) {
            Write-Log "SSMエージェントインストール成功"
        } else {
            Write-Log "SSMエージェントインストール終了コード: $($installProcess.ExitCode)"
        }
        
        # インストーラーファイルを削除
        Remove-Item $ssmInstaller -Force -ErrorAction SilentlyContinue
    }
    
    # サービスの開始を待機
    Start-Sleep -Seconds 15
    
    # SSMエージェントサービスの開始
    $maxRetries = 3
    for ($i = 1; $i -le $maxRetries; $i++) {
        try {
            $ssmServiceCheck = Get-Service -Name "AmazonSSMAgent" -ErrorAction Stop
            if ($ssmServiceCheck.Status -ne "Running") {
                Start-Service AmazonSSMAgent -ErrorAction Stop
                Write-Log "SSMエージェントサービスを開始しました (試行 $i)"
                break
            } else {
                Write-Log "SSMエージェントサービスは既に実行中です"
                break
            }
        }
        catch {
            Write-Log "SSMエージェントサービス開始エラー (試行 $i): $($_.Exception.Message)"
            if ($i -lt $maxRetries) {
                Start-Sleep -Seconds 10
            }
        }
    }
    
    # 最終的なサービス状態の確認
    $finalStatus = Get-Service -Name "AmazonSSMAgent" -ErrorAction SilentlyContinue
    if ($finalStatus) {
        Write-Log "SSMエージェント最終状態: $($finalStatus.Status)"
        if ($finalStatus.Status -eq "Running") {
            Write-Log "✓ SSMエージェント設定・更新完了"
        } else {
            Write-Log "⚠️ SSMエージェントは正常に動作していない可能性があります"
        }
    } else {
        Write-Log "✗ SSMエージェントサービスが見つかりません"
    }
}
catch {
    Write-Log "SSMエージェント設定エラー: $($_.Exception.Message)"
    Write-Log "エラー詳細: $($_.Exception.StackTrace)"
}

# ホストファイルの設定（Linux VMへの接続用）
try {
    # 注意: 実際のIPアドレスはデプロイ後に変更する必要があります
    Add-Content -Path $env:windir\System32\drivers\etc\hosts -Value "`n10.0.0.100 dify-server"
    Write-Log "hostsファイル設定完了"
}
catch {
    Write-Log "hostsファイル設定エラー: $($_.Exception.Message)"
}

# 最終確認
Write-Log "=== 最終設定確認 ==="
try {
    # Administratorアカウント情報の確認
    $adminCheck = net user Administrator
    Write-Log "Administrator確認: $adminCheck"
    
    # RDP設定の確認
    $rdpCheck = Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections"
    Write-Log "RDP設定確認: fDenyTSConnections = $($rdpCheck.fDenyTSConnections)"
    
    # IMDSv2環境変数の確認
    $imdsMode = [Environment]::GetEnvironmentVariable("AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE", "Machine")
    $imdsAttempts = [Environment]::GetEnvironmentVariable("AWS_EC2_METADATA_SERVICE_NUM_ATTEMPTS", "Machine")
    Write-Log "IMDS設定確認: Mode = $imdsMode, Attempts = $imdsAttempts"
    
    # SSMエージェントサービスの状態確認
    $ssmStatus = Get-Service AmazonSSMAgent -ErrorAction SilentlyContinue
    if ($ssmStatus) {
        Write-Log "SSMエージェント状態: $($ssmStatus.Status)"
    } else {
        Write-Log "SSMエージェントサービスが見つかりません"
    }
}
catch {
    Write-Log "最終確認エラー: $($_.Exception.Message)"
}

# 完了メッセージ
Write-Log "Windows VM setup completed successfully!"
Write-Host "Windows VM setup completed successfully!"
Write-Host "ログファイルの場所: $LogFile"
$displayUsername = if ($env:WINDOWS_ADMIN_USERNAME) { $env:WINDOWS_ADMIN_USERNAME } else { "Administrator" }
Write-Host "管理者アカウント: $displayUsername"
Write-Host "パスワードは設定済みです"

# IMDSv2診断スクリプトの作成
$DiagnosticScript = @"
# IMDSv2診断スクリプト
Write-Host "=== IMDSv2診断テスト ==="

# 環境変数の確認
Write-Host "環境変数:"
Write-Host "  AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE: `$([Environment]::GetEnvironmentVariable('AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE', 'Machine'))"
Write-Host "  AWS_EC2_METADATA_SERVICE_NUM_ATTEMPTS: `$([Environment]::GetEnvironmentVariable('AWS_EC2_METADATA_SERVICE_NUM_ATTEMPTS', 'Machine'))"

# IMDSv1テスト（失敗するはず）
Write-Host "`nIMDSv1テスト（失敗する予定）:"
try {
    `$imdsv1Result = Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/instance-id" -TimeoutSec 5 -ErrorAction Stop
    Write-Host "⚠️  IMDSv1が有効: `$imdsv1Result" -ForegroundColor Yellow
} catch {
    Write-Host "✓ IMDSv1が正しく無効化されています" -ForegroundColor Green
}

# IMDSv2テスト
Write-Host "`nIMDSv2テスト:"
try {
    `$tokenUri = "http://169.254.169.254/latest/api/token"
    `$headers = @{"X-aws-ec2-metadata-token-ttl-seconds" = "21600"}
    `$token = Invoke-RestMethod -Uri `$tokenUri -Method Put -Headers `$headers -TimeoutSec 10 -ErrorAction Stop
    
    if (`$token) {
        Write-Host "✓ IMDSv2トークン取得成功" -ForegroundColor Green
        Write-Host "  トークン: `$(`$token.Substring(0, [Math]::Min(20, `$token.Length)))..."
        
        # 各種メタデータの取得テスト
        `$metadataHeaders = @{"X-aws-ec2-metadata-token" = `$token}
        `$instanceId = Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/instance-id" -Headers `$metadataHeaders -TimeoutSec 10
        `$region = Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/placement/region" -Headers `$metadataHeaders -TimeoutSec 10
        `$instanceType = Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/instance-type" -Headers `$metadataHeaders -TimeoutSec 10
        
        Write-Host "  インスタンスID: `$instanceId"
        Write-Host "  リージョン: `$region"
        Write-Host "  インスタンスタイプ: `$instanceType"
    }
} catch {
    Write-Host "✗ IMDSv2トークン取得失敗: `$(`$_.Exception.Message)" -ForegroundColor Red
}

# SSM Agentの状態確認  
Write-Host "`nSSM Agent状態:"
try {
    `$ssmService = Get-Service AmazonSSMAgent -ErrorAction Stop
    if (`$ssmService.Status -eq 'Running') {
        Write-Host "✓ SSM Agent実行中" -ForegroundColor Green
    } else {
        Write-Host "⚠️  SSM Agent状態: `$(`$ssmService.Status)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "✗ SSM Agentが見つかりません" -ForegroundColor Red
}

Write-Host "`n=== 診断完了 ==="
"@

$DiagnosticScript | Out-File -FilePath "C:\Windows\Temp\IMDSv2_Diagnostic.ps1" -Encoding UTF8
Write-Log "IMDSv2診断スクリプトを作成しました: C:\Windows\Temp\IMDSv2_Diagnostic.ps1"
Write-Host "IMDSv2診断を実行するには: PowerShell -ExecutionPolicy Bypass -File C:\Windows\Temp\IMDSv2_Diagnostic.ps1"
