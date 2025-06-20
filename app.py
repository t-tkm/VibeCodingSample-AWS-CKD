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

# メインスタックの作成
DifyCdkStack(app, STACK_NAME,
    description="Dify アプリケーション用のインフラストラクチャ",
    # タグの設定
    tags={
        'Project': APP_NAME,
        'Environment': ENV_NAME,
        'ManagedBy': 'CDK',
    }
)

app.synth()
