# -*- coding: utf-8 -*-

"""
Windows VMコンストラクト

このモジュールは、Windows VMインスタンスを定義します。
"""

import os
from constructs import Construct
from aws_cdk import aws_ec2 as ec2
from aws_cdk import aws_iam as iam
from aws_cdk import aws_ssm as ssm
from aws_cdk import Tags, CfnOutput


class WindowsInstanceConstruct(Construct):
    """Windows VMインスタンスを作成するコンストラクト"""

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
        
        # Windows AMIの検索（日本語版）
        windows_ami = ec2.MachineImage.latest_windows(
            version=ec2.WindowsVersion.WINDOWS_SERVER_2022_JAPANESE_FULL_BASE
        )
        
        # インスタンスタイプの設定
        instance_type_obj = ec2.InstanceType(instance_type)
        
        # Windows VMの作成
        self.instance = ec2.Instance(
            self, "Instance",
            vpc=vpc,
            instance_type=instance_type_obj,
            machine_image=windows_ami,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
            security_group=security_group,
            role=instance_role,
            user_data=user_data,
            user_data_causes_replacement=False,
            block_devices=[
                ec2.BlockDevice(
                    device_name="/dev/sda1",
                    volume=ec2.BlockDeviceVolume.ebs(
                        volume_size=50,  # 50GB
                        volume_type=ec2.EbsDeviceVolumeType.GP3,
                        encrypted=True
                    )
                )
            ]
        )
        
        # SSMパラメータストアに管理者パスワードを保存
        admin_password = ssm.StringParameter(
            self, "AdminPassword",
            parameter_name=f"/dify/{id}/admin-password",
            string_value=config.windows_admin_password,
            description="Windows VM administrator password",
            tier=ssm.ParameterTier.STANDARD,
            simple_name=False
        )
        
        # タグの追加
        Tags.of(self.instance).add("Name", f"{id}-instance")
        
        # 出力の設定
        CfnOutput(
            self, "InstanceId",
            value=self.instance.instance_id,
            description="Windows VM Instance ID"
        )
        
        CfnOutput(
            self, "PrivateIP",
            value=self.instance.instance_private_ip,
            description="Windows VM Private IP Address"
        )
    
    def _load_user_data(self) -> ec2.UserData:
        """
        ユーザーデータスクリプトを読み込む
        
        Returns:
            UserDataインスタンス
        """
        user_data = ec2.UserData.for_windows()
        
        # スクリプトファイルのパス
        script_path = os.path.join("scripts", "user_data_windows.ps1")
        
        # スクリプトファイルが存在する場合は読み込む
        if os.path.exists(script_path):
            with open(script_path, "r", encoding='utf-8') as f:
                script_content = f.read()
            
            user_data.add_commands(
                f"$env:WINDOWS_ADMIN_USERNAME = '{self.config.windows_admin_username}'",
                f"$env:WINDOWS_ADMIN_PASSWORD = '{self.config.windows_admin_password}'"
            )
            user_data.add_commands(script_content)
        else:
            # デフォルトのスクリプト
            user_data.add_commands(
                "Set-ExecutionPolicy Unrestricted -Force",
                "Install-WindowsFeature -Name Web-Server -IncludeManagementTools",
                # 管理者パスワードの設定
                f"$Password = ConvertTo-SecureString '{self.config.windows_admin_password}' -AsPlainText -Force",
                f"$UserAccount = Get-LocalUser -Name '{self.config.windows_admin_username}'",
                "$UserAccount | Set-LocalUser -Password $Password",
                # ファイアウォールの設定
                "New-NetFirewallRule -DisplayName 'Allow HTTP' -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow",
                # SSMエージェントの更新
                "Invoke-WebRequest https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/windows_amd64/AmazonSSMAgentSetup.exe -OutFile $env:TEMP\\SSMAgent_latest.exe",
                "Start-Process -FilePath $env:TEMP\\SSMAgent_latest.exe -ArgumentList '/S' -Wait",
                "Restart-Service AmazonSSMAgent"
            )
        
        return user_data
