# -*- coding: utf-8 -*-

"""
ネットワークコンストラクト

このモジュールは、VPCやサブネットなどのネットワークリソースを定義します。
"""

from constructs import Construct
from aws_cdk import aws_ec2 as ec2
from aws_cdk import Tags


class NetworkConstruct(Construct):
    """ネットワークリソースを作成するコンストラクト"""

    def __init__(self, scope: Construct, id: str, vpc_cidr: str, **kwargs):
        """
        コンストラクタ
        
        Args:
            scope: 親スコープ
            id: コンストラクトID
            vpc_cidr: VPCのCIDR範囲
            **kwargs: その他の引数
        """
        super().__init__(scope, id)
        
        # VPCの作成
        self.vpc = ec2.Vpc(
            self, "VPC",
            vpc_name=f"{id}-vpc",
            ip_addresses=ec2.IpAddresses.cidr(vpc_cidr),
            max_azs=2,  # 2つのアベイラビリティゾーンを使用
            nat_gateways=1,  # NATゲートウェイを1つ作成（コスト削減のため）
            subnet_configuration=[
                # パブリックサブネット（インターネットアクセス用）
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24
                ),
                # プライベートサブネット（VMインスタンス用）
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24
                ),
                # 隔離サブネット（将来の拡張用）
                ec2.SubnetConfiguration(
                    name="Isolated",
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                    cidr_mask=24
                )
            ]
        )
        
        # VPCエンドポイントの作成（AWS Systems Manager接続用）
        self._create_ssm_endpoints()
        
        # タグの追加
        Tags.of(self.vpc).add("Name", f"{id}-vpc")
    
    def _create_ssm_endpoints(self):
        """
        AWS Systems Manager接続用のVPCエンドポイントを作成
        
        Fleet Managerを使用するために必要なエンドポイント:
        - ssm: Systems Manager
        - ssmmessages: Session Manager
        - ec2messages: EC2メッセージ
        """
        # セキュリティグループの作成
        sg = ec2.SecurityGroup(
            self, "SSMEndpointSG",
            vpc=self.vpc,
            description="Security group for SSM VPC Endpoints",
            allow_all_outbound=True
        )
        
        # 内部からのHTTPSトラフィックを許可
        sg.add_ingress_rule(
            ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            ec2.Port.tcp(443),
            "Allow HTTPS from VPC"
        )
        
        # SSMエンドポイント
        self.vpc.add_interface_endpoint(
            "SSMEndpoint",
            service=ec2.InterfaceVpcEndpointAwsService.SSM,
            security_groups=[sg]
        )
        
        # SSMメッセージエンドポイント
        self.vpc.add_interface_endpoint(
            "SSMMessagesEndpoint",
            service=ec2.InterfaceVpcEndpointAwsService.SSM_MESSAGES,
            security_groups=[sg]
        )
        
        # EC2メッセージエンドポイント
        self.vpc.add_interface_endpoint(
            "EC2MessagesEndpoint",
            service=ec2.InterfaceVpcEndpointAwsService.EC2_MESSAGES,
            security_groups=[sg]
        )
