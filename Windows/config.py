# ============================================
# NDHSM Windows 管理工具 - 配置管理模块
# 相关文件: main.py, muip_client.py, auto_setup.py,
#           main_window.py, proxy_manager.py
# ============================================
"""
配置管理模块
- 定义常量和默认配置
- 读写 Config.json
- 路径管理
"""

import os
import json
from pathlib import Path
from typing import Optional, Dict, Any

# ============================================
# 常量定义（便于修改）
# ============================================

# 默认端口配置
DEFAULT_HTTP_PORT = 520          # WebServer/MUIP API 端口 (需求文档中提到520)
DEFAULT_GAME_PORT = 23301        # GameServer 端口
DEFAULT_HOST = "127.0.0.1"       # 默认本地地址

# GitHub/Gitee 仓库地址
GITHUB_SERVER_REPO = "https://github.com/GamblerIX/DanHengServer.git"
GITHUB_RESOURCES_REPO = "https://github.com/GamblerIX/DanHengServerResources.git"
GITHUB_PROXY_REPO = "https://github.com/GamblerIX/DanHengProxy.git"

GITEE_SERVER_REPO = "https://gitee.com/GamblerIX/DanHengServer.git"
GITEE_RESOURCES_REPO = "https://gitee.com/GamblerIX/DanHengServerResources.git"
GITEE_PROXY_REPO = "https://gitee.com/GamblerIX/DanHengProxy.git"

# 应用信息
APP_NAME = "NDHSM"
APP_VERSION = "1.0.0"
APP_TITLE = "DanHeng Server Manager"

# ============================================
# 路径配置
# ============================================

def get_app_dir() -> Path:
    """获取应用根目录（NDHSM/Windows 的父目录）"""
    return Path(__file__).parent.parent.parent


def get_server_dir() -> Path:
    """获取 DanHengServer 目录"""
    return get_app_dir() / "DanHengServer"


def get_resources_dir() -> Path:
    """获取 Resources 目录（在 DanHengServer 下）"""
    return get_server_dir() / "Resources"


def get_proxy_dir() -> Path:
    """获取 DanHengProxy 目录"""
    return get_app_dir() / "DanHengProxy"


def get_config_path() -> Path:
    """获取 Config.json 路径"""
    return get_server_dir() / "config.json"


# ============================================
# Config.json 管理
# ============================================

def get_default_config() -> Dict[str, Any]:
    """
    生成默认的 Config.json 配置
    基于 DanHengServer 的 ConfigContainer.cs 结构
    """
    return {
        "HttpServer": {
            "BindAddress": "0.0.0.0",
            "PublicAddress": DEFAULT_HOST,
            "Port": DEFAULT_HTTP_PORT,
            "UseSSL": True,
            "UseFetchRemoteHotfix": False
        },
        "KeyStore": {
            "KeyStorePath": "certificate.p12",
            "KeyStorePassword": "123456"
        },
        "GameServer": {
            "BindAddress": "0.0.0.0",
            "PublicAddress": DEFAULT_HOST,
            "Port": DEFAULT_GAME_PORT,
            "GameServerId": "dan_heng",
            "GameServerName": "DanhengServer",
            "GameServerDescription": "A re-implementation of StarRail server",
            "UsePacketEncryption": True
        },
        "Path": {
            "ResourcePath": "Resources",
            "ConfigPath": "Config",
            "DatabasePath": "Config/Database",
            "LogPath": "Logs",
            "PluginPath": "Plugins"
        },
        "Database": {
            "DatabaseType": "sqlite",
            "DatabaseName": "danheng.db",
            "MySqlHost": "127.0.0.1",
            "MySqlPort": 3306,
            "MySqlUser": "root",
            "MySqlPassword": "123456",
            "MySqlDatabase": "danheng"
        },
        "ServerOption": {
            "StartTrailblazerLevel": 1,
            "AutoUpgradeWorldLevel": True,
            "EnableMission": True,
            "EnableQuest": True,
            "AutoLightSection": True,
            "Language": "CHS",
            "FallbackLanguage": "EN",
            "DefaultPermissions": ["*"],
            "AutoCreateUser": True,
            "FarmingDropRate": 1,
            "UseCache": False
        },
        "MuipServer": {
            "AdminKey": ""  # 将由服务器自动生成
        }
    }


def load_config() -> Optional[Dict[str, Any]]:
    """
    加载 Config.json
    返回配置字典，如果文件不存在返回 None
    """
    config_path = get_config_path()
    if not config_path.exists():
        return None
    
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError) as e:
        print(f"[错误] 加载配置文件失败: {e}")
        return None


def save_config(config: Dict[str, Any]) -> bool:
    """
    保存配置到 Config.json
    返回是否保存成功
    """
    config_path = get_config_path()
    
    try:
        # 确保父目录存在
        config_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(config_path, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
        return True
    except IOError as e:
        print(f"[错误] 保存配置文件失败: {e}")
        return False


def get_muip_url() -> str:
    """获取 MUIP API 的基础 URL"""
    config = load_config()
    if config is None:
        return f"https://{DEFAULT_HOST}:{DEFAULT_HTTP_PORT}"
    
    http_config = config.get("HttpServer", {})
    host = http_config.get("PublicAddress", DEFAULT_HOST)
    port = http_config.get("Port", DEFAULT_HTTP_PORT)
    use_ssl = http_config.get("UseSSL", True)
    
    protocol = "https" if use_ssl else "http"
    return f"{protocol}://{host}:{port}"


def get_admin_key() -> Optional[str]:
    """获取 MUIP 管理密钥"""
    config = load_config()
    if config is None:
        return None
    
    return config.get("MuipServer", {}).get("AdminKey")


# ============================================
# 配置验证
# ============================================

def validate_config(config: Dict[str, Any]) -> list[str]:
    """
    验证配置有效性
    返回错误消息列表，空列表表示配置有效
    """
    errors = []
    
    # 检查必要字段
    if "HttpServer" not in config:
        errors.append("缺少 HttpServer 配置")
    if "GameServer" not in config:
        errors.append("缺少 GameServer 配置")
    if "MuipServer" not in config:
        errors.append("缺少 MuipServer 配置")
    
    # 检查端口范围
    http_port = config.get("HttpServer", {}).get("Port", 0)
    if not (1 <= http_port <= 65535):
        errors.append(f"HttpServer 端口无效: {http_port}")
    
    game_port = config.get("GameServer", {}).get("Port", 0)
    if not (1 <= game_port <= 65535):
        errors.append(f"GameServer 端口无效: {game_port}")
    
    return errors
