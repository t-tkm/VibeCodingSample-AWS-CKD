# Windows VM 初期化スクリプト

# 日本語環境の設定
# システムロケールを日本語に設定
Set-WinSystemLocale ja-JP
# UIの言語を日本語に設定
Set-WinUILanguageOverride -Language ja-JP
# ユーザー言語リストに日本語を追加して最優先に設定
$LanguageList = New-WinUserLanguageList ja-JP
$LanguageList.Add("en-US")
Set-WinUserLanguageList $LanguageList -Force
# 地域を日本に設定
Set-WinHomeLocation -GeoId 0x7A # 日本の地域ID
# タイムゾーンを東京に設定
Set-TimeZone -Id "Tokyo Standard Time"

# 実行ポリシーの設定
Set-ExecutionPolicy Unrestricted -Force

# 管理者パスワードの設定
# Administratorアカウントを有効化
net user Administrator /active:yes

# より強固なパスワードを設定
$Password = ConvertTo-SecureString 'Admin@2024#Secure' -AsPlainText -Force
$UserAccount = Get-LocalUser -Name 'Administrator'
$UserAccount | Set-LocalUser -Password $Password -PasswordNeverExpires $true

# パスワード要件を緩和（必要に応じて）
secedit /export /cfg c:\secpol.cfg
(gc C:\secpol.cfg).replace("PasswordComplexity = 1", "PasswordComplexity = 0") | Out-File C:\secpol.cfg
secedit /configure /db c:\windows\security\local.sdb /cfg c:\secpol.cfg /areas SECURITYPOLICY
rm -force c:\secpol.cfg -confirm:$false

# RDP接続を有効化
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -name "UserAuthentication" -Value 0

# 必要な機能のインストール
Install-WindowsFeature -Name Web-Server -IncludeManagementTools
Install-WindowsFeature -Name RSAT-AD-Tools

# Chocolateyのインストール
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

# 必要なソフトウェアのインストール
choco install -y googlechrome
choco install -y firefox
choco install -y 7zip
choco install -y notepadplusplus
choco install -y putty
choco install -y winscp

# ファイアウォールの設定
New-NetFirewallRule -DisplayName 'Allow HTTP' -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow
New-NetFirewallRule -DisplayName 'Allow HTTPS' -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow
New-NetFirewallRule -DisplayName 'Allow RDP' -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow

# SSMエージェントの更新
Invoke-WebRequest https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/windows_amd64/AmazonSSMAgentSetup.exe -OutFile $env:TEMP\SSMAgent_latest.exe
Start-Process -FilePath $env:TEMP\SSMAgent_latest.exe -ArgumentList '/S' -Wait
Restart-Service AmazonSSMAgent

# ホストファイルの設定（Linux VMへの接続用）
# 注意: 実際のIPアドレスはデプロイ後に変更する必要があります
Add-Content -Path $env:windir\System32\drivers\etc\hosts -Value "`n10.0.0.100 dify-server"

# デスクトップにショートカットを作成
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\Dify.lnk")
$Shortcut.TargetPath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$Shortcut.Arguments = "http://dify-server"
$Shortcut.Description = "Dify AI Platform"
$Shortcut.IconLocation = "C:\Program Files\Google\Chrome\Application\chrome.exe,0"
$Shortcut.Save()

# 完了メッセージ
Write-Host "Windows VM setup completed successfully!"
