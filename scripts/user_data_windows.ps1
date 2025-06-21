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

# SSMエージェントの更新
try {
    Invoke-WebRequest https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/windows_amd64/AmazonSSMAgentSetup.exe -OutFile $env:TEMP\SSMAgent_latest.exe
    Start-Process -FilePath $env:TEMP\SSMAgent_latest.exe -ArgumentList '/S' -Wait
    Restart-Service AmazonSSMAgent
    Write-Log "SSMエージェント更新完了"
}
catch {
    Write-Log "SSMエージェント更新エラー: $($_.Exception.Message)"
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
