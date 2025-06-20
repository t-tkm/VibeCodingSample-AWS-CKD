# -*- coding: utf-8 -*-

"""
Dify CDKスタック

このモジュールは、Difyアプリケーションのデプロイメント用のCDKスタックを定義します。
"""

from constructs import Construct
from aws_cdk import Stack

from dify_cdk.config.config import Config
from dify_cdk.constructs.network import NetworkConstruct
from dify_cdk.constructs.security import SecurityConstruct
from dify_cdk.constructs.windows_instance import WindowsInstanceConstruct
from dify_cdk.constructs.linux_instance import LinuxInstanceConstruct


class DifyCdkStack(Stack):
    """Difyアプリケーションのデプロイメント用のCDKスタック"""

    def __init__(self, scope: Construct, construct_id: str, **kwargs):
        """
        コンストラクタ
        
        Args:
            scope: 親スコープ
            construct_id: コンストラクトID
            **kwargs: その他の引数
        """
        super().__init__(scope, construct_id, **kwargs)
        
        # 設定の読み込み
        config = Config(self.node.root)
        
        # ネットワークリソースの作成
        network = NetworkConstruct(
            self, "Network",
            vpc_cidr=config.vpc_cidr
        )
        
        # セキュリティリソースの作成
        security = SecurityConstruct(
            self, "Security",
            vpc=network.vpc
        )
        
        # Windows VMの作成
        windows_instance = WindowsInstanceConstruct(
            self, "WindowsVM",
            vpc=network.vpc,
            security_group=security.windows_sg,
            instance_role=security.instance_role,
            instance_type=config.windows_instance_type,
            ami_name_pattern=config.windows_ami_name
        )
        
        # Linux VMの作成
        linux_instance = LinuxInstanceConstruct(
            self, "LinuxVM",
            vpc=network.vpc,
            security_group=security.linux_sg,
            instance_role=security.instance_role,
            instance_type=config.linux_instance_type,
            ami_name_pattern=config.linux_ami_name
        )
