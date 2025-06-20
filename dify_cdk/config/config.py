# -*- coding: utf-8 -*-

"""
設定ファイル

このモジュールは、CDKスタックの設定パラメータを定義します。
環境変数やcdk.jsonのコンテキストから値を取得します。
"""

import os
import json
from typing import Dict, Any
from aws_cdk import App


class Config:
    """CDKスタックの設定を管理するクラス"""

    def __init__(self, app: App):
        """
        コンストラクタ
        
        Args:
            app: CDKアプリケーションインスタンス
        """
        self.app = app
        self.context = app.node.try_get_context('context') or {}
        self.credentials = self._load_credentials()
        
    def get_value(self, key: str, default: Any = None) -> Any:
        """
        設定値を取得する
        
        環境変数 > CDKコンテキスト > デフォルト値 の順で値を探します
        
        Args:
            key: 設定キー
            default: デフォルト値
            
        Returns:
            設定値
        """
        # 環境変数から取得（キーを大文字に変換し、ハイフンをアンダースコアに置換）
        env_key = key.upper().replace('-', '_')
        if env_key in os.environ:
            return os.environ[env_key]
        
        # CDKコンテキストから取得
        if key in self.context:
            return self.context[key]
        
        # デフォルト値を返す
        return default
    
    def _load_credentials(self) -> Dict[str, Any]:
        """
        認証情報ファイルを読み込む
        
        Returns:
            認証情報の辞書
        """
        credentials_file = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), 'credentials.json')
        
        if os.path.exists(credentials_file):
            try:
                with open(credentials_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except (json.JSONDecodeError, IOError) as e:
                print(f"Warning: Failed to load credentials file: {e}")
                return {}
        
        return {}
    
    @property
    def vpc_cidr(self) -> str:
        """VPCのCIDR範囲"""
        return self.get_value('vpc-cidr', '10.0.0.0/16')
    
    @property
    def windows_instance_type(self) -> str:
        """Windows VMのインスタンスタイプ"""
        return self.get_value('windows-instance-type', 't3.medium')
    
    @property
    def linux_instance_type(self) -> str:
        """Linux VMのインスタンスタイプ"""
        return self.get_value('linux-instance-type', 't3.large')
    
    @property
    def windows_ami_name(self) -> str:
        """Windows AMIの名前パターン"""
        return self.get_value('windows-ami-name', 'Windows_Server-2022-English-Full-Base-*')
    
    @property
    def linux_ami_name(self) -> str:
        """Linux AMIの名前パターン"""
        return self.get_value('linux-ami-name', 'ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*')
    
    @property
    def windows_admin_username(self) -> str:
        """Windows VMの管理者ユーザー名"""
        env_key = 'WINDOWS_ADMIN_USERNAME'
        if env_key in os.environ:
            return os.environ[env_key]
        
        if 'windows' in self.credentials and 'admin_username' in self.credentials['windows']:
            return self.credentials['windows']['admin_username']
        
        return 'Administrator'
    
    @property
    def windows_admin_password(self) -> str:
        """Windows VMの管理者パスワード"""
        env_key = 'WINDOWS_ADMIN_PASSWORD'
        if env_key in os.environ:
            return os.environ[env_key]
        
        if 'windows' in self.credentials and 'admin_password' in self.credentials['windows']:
            return self.credentials['windows']['admin_password']
        
        return 'P@ssw0rd123!'
    
    @property
    def linux_admin_username(self) -> str:
        """Linux VMの管理者ユーザー名"""
        env_key = 'LINUX_ADMIN_USERNAME'
        if env_key in os.environ:
            return os.environ[env_key]
        
        if 'linux' in self.credentials and 'admin_username' in self.credentials['linux']:
            return self.credentials['linux']['admin_username']
        
        return 'ubuntu'
    
    @property
    def linux_admin_password(self) -> str:
        """Linux VMの管理者パスワード"""
        env_key = 'LINUX_ADMIN_PASSWORD'
        if env_key in os.environ:
            return os.environ[env_key]
        
        if 'linux' in self.credentials and 'admin_password' in self.credentials['linux']:
            return self.credentials['linux']['admin_password']
        
        return 'P@ssw0rd123!'
    
    @property
    def tags(self) -> Dict[str, str]:
        """リソースに適用するタグ"""
        app_name = os.environ.get('APP_NAME', 'dify')
        env_name = os.environ.get('ENV_NAME', 'dev')
        
        return {
            'Project': app_name,
            'Environment': env_name,
            'ManagedBy': 'CDK',
        }
