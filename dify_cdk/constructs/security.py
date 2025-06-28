# -*- coding: utf-8 -*-

"""
セキュリティコンストラクト

このモジュールは、セキュリティグループやIAMロールなどのセキュリティリソースを定義します。
"""

from constructs import Construct
from aws_cdk import aws_ec2 as ec2
from aws_cdk import aws_iam as iam
from aws_cdk import Tags


class SecurityConstruct(Construct):
    """セキュリティリソースを作成するコンストラクト"""

    def __init__(self, scope: Construct, id: str, vpc: ec2.Vpc, **kwargs):
        """
        コンストラクタ
        
        Args:
            scope: 親スコープ
            id: コンストラクトID
            vpc: VPCインスタンス
            **kwargs: その他の引数
        """
        super().__init__(scope, id)
        
        # Windows VMのセキュリティグループ
        self.windows_sg = self._create_windows_security_group(vpc)
        
        # Linux VMのセキュリティグループ
        self.linux_sg = self._create_linux_security_group(vpc)
        
        # EC2インスタンスプロファイル用のIAMロール
        self.instance_role = self._create_instance_role()
    
    def _create_windows_security_group(self, vpc: ec2.Vpc) -> ec2.SecurityGroup:
        """
        Windows VMのセキュリティグループを作成
        
        Args:
            vpc: VPCインスタンス
            
        Returns:
            セキュリティグループ
        """
        sg = ec2.SecurityGroup(
            self, "WindowsSG",
            vpc=vpc,
            description="Security group for Windows VM",
            allow_all_outbound=True
        )
        
        # VPC内からのRDPトラフィックを許可（Fleet Managerを使用するため実際には不要だが、緊急時のために設定）
        sg.add_ingress_rule(
            ec2.Peer.ipv4(vpc.vpc_cidr_block),
            ec2.Port.tcp(3389),
            "Allow RDP from VPC"
        )
        
        # タグの追加
        Tags.of(sg).add("Name", "windows-vm-sg")
        
        return sg
    
    def _create_linux_security_group(self, vpc: ec2.Vpc) -> ec2.SecurityGroup:
        """
        Linux VMのセキュリティグループを作成
        
        Args:
            vpc: VPCインスタンス
            
        Returns:
            セキュリティグループ
        """
        sg = ec2.SecurityGroup(
            self, "LinuxSG",
            vpc=vpc,
            description="Security group for Linux VM",
            allow_all_outbound=True
        )
        
        # VPC内からのSSHトラフィックを許可（Fleet Managerを使用するため実際には不要だが、緊急時のために設定）
        sg.add_ingress_rule(
            ec2.Peer.ipv4(vpc.vpc_cidr_block),
            ec2.Port.tcp(22),
            "Allow SSH from VPC"
        )
        
        # VPC内からのHTTPトラフィックを許可（Difyアクセス用）
        sg.add_ingress_rule(
            ec2.Peer.ipv4(vpc.vpc_cidr_block),
            ec2.Port.tcp(80),
            "Allow HTTP from VPC"
        )
        
        # Windows VMからのHTTPトラフィックを許可（Difyアクセス用）
        sg.add_ingress_rule(
            self.windows_sg,
            ec2.Port.tcp(80),
            "Allow HTTP from Windows VM"
        )
        
        # タグの追加
        Tags.of(sg).add("Name", "linux-vm-sg")
        
        return sg
    
    def _create_instance_role(self) -> iam.Role:
        """
        EC2インスタンスプロファイル用のIAMロールを作成
        
        Returns:
            IAMロール
        """
        role = iam.Role(
            self, "EC2InstanceRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="Role for EC2 instances with IMDSv2 support"
        )
        
        # Systems Manager管理ポリシーを追加（Fleet Manager接続用）
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore")
        )
        
        # CloudWatch Agent用のポリシーを追加
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy")
        )
        
        # IMDSv2とSSMパラメータアクセス用のカスタムポリシー
        custom_policy = iam.Policy(
            self, "CustomInstancePolicy",
            statements=[
                # SSMパラメータの読み取り権限
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "ssm:GetParameter",
                        "ssm:GetParameters",
                        "ssm:GetParametersByPath"
                    ],
                    resources=[
                        f"arn:aws:ssm:*:*:parameter/dify/*"
                    ]
                ),
                # CloudWatch Logs用の権限
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "logs:CreateLogGroup",
                        "logs:CreateLogStream",
                        "logs:PutLogEvents",
                        "logs:DescribeLogGroups",
                        "logs:DescribeLogStreams"
                    ],
                    resources=[
                        f"arn:aws:logs:*:*:log-group:/aws/ec2/dify-logs*"
                    ]
                ),
                # EC2インスタンス情報の読み取り権限（IMDSv2用）
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "ec2:DescribeInstances",
                        "ec2:DescribeInstanceAttribute",
                        "ec2:DescribeInstanceStatus",
                        "ec2:DescribeInstanceTypes"
                    ],
                    resources=["*"]
                )
            ]
        )
        
        role.attach_inline_policy(custom_policy)
        
        return role
