#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import aws_cdk as cdk
from dify_cdk.dify_cdk_stack import DifyCdkStack

# スタック名とタグの設定
# 複数環境のデプロイ時に変更可能
APP_NAME = os.environ.get('APP_NAME', 'dify')
ENV_NAME = os.environ.get('ENV_NAME', 'dev')
STACK_NAME = f"{APP_NAME}-{ENV_NAME}"

app = cdk.App()

# 環境設定（AWS アカウントとリージョン）
# 実際のデプロイ時には、これらの値を適切に設定する必要があります
AWS_ACCOUNT = os.environ.get('CDK_DEFAULT_ACCOUNT', '123456789012')  # デフォルト値はダミー
AWS_REGION = os.environ.get('CDK_DEFAULT_REGION', 'ap-northeast-1')  # デフォルト値は東京リージョン

# メインスタックの作成
DifyCdkStack(app, STACK_NAME,
    description="Dify アプリケーション用のインフラストラクチャ",
    # 環境設定
    env=cdk.Environment(
        account=AWS_ACCOUNT,
        region=AWS_REGION
    ),
    # タグの設定
    tags={
        'Project': APP_NAME,
        'Environment': ENV_NAME,
        'ManagedBy': 'CDK',
    }
)

app.synth()
