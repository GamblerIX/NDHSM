# ============================================
# NDHSM Windows 管理工具 - MUIP API 客户端
# 相关文件: config.py, main_window.py
# ============================================
"""
MUIP API 客户端模块
- RSA 加密实现 (PKCS#1)
- 会话管理
- 命令执行
- 服务器状态查询
"""

import base64
import requests
from typing import Optional, Dict, Any, Tuple
from Crypto.PublicKey import RSA
from Crypto.Cipher import PKCS1_v1_5

from config import get_muip_url, get_admin_key

# ============================================
# 常量定义
# ============================================

# API 端点
ENDPOINT_CREATE_SESSION = "/muip/create_session"
ENDPOINT_AUTH_ADMIN = "/muip/auth_admin"
ENDPOINT_EXEC_CMD = "/muip/exec_cmd"
ENDPOINT_SERVER_INFO = "/muip/server_information"
ENDPOINT_PLAYER_INFO = "/muip/player_information"

# 请求超时（秒）
REQUEST_TIMEOUT = 10


# ============================================
# MUIP 客户端类
# ============================================

class MuipClient:
    """
    MUIP API 客户端
    用于与 DanHengServer 的 MUIP 接口通信
    """
    
    def __init__(self, base_url: Optional[str] = None):
        """
        初始化 MUIP 客户端
        
        Args:
            base_url: API 基础 URL，如果为 None 则从配置文件读取
        """
        self.base_url = base_url or get_muip_url()
        self.session_id: Optional[str] = None
        self.rsa_public_key: Optional[str] = None
        self.expire_timestamp: Optional[int] = None
        self.is_authorized = False
        
        # 禁用 SSL 验证警告（本地开发）
        requests.packages.urllib3.disable_warnings()
    
    def _request(self, method: str, endpoint: str, 
                 data: Optional[Dict] = None, 
                 params: Optional[Dict] = None) -> Tuple[bool, Dict[str, Any]]:
        """
        发送 HTTP 请求
        
        Returns:
            (成功标志, 响应数据)
        """
        url = f"{self.base_url}{endpoint}"
        
        try:
            if method.upper() == "POST":
                response = requests.post(
                    url, 
                    json=data,
                    params=params,
                    timeout=REQUEST_TIMEOUT,
                    verify=False  # 忽略 SSL 证书验证
                )
            else:
                response = requests.get(
                    url,
                    params=params,
                    timeout=REQUEST_TIMEOUT,
                    verify=False
                )
            
            result = response.json()
            success = result.get("code", -1) == 0
            return success, result
            
        except requests.exceptions.ConnectionError:
            return False, {"code": -1, "message": "无法连接到服务器"}
        except requests.exceptions.Timeout:
            return False, {"code": -1, "message": "请求超时"}
        except requests.exceptions.RequestException as e:
            return False, {"code": -1, "message": f"请求错误: {str(e)}"}
        except ValueError:
            return False, {"code": -1, "message": "无效的 JSON 响应"}
    
    def _encrypt_with_rsa(self, plaintext: str) -> Optional[str]:
        """
        使用 RSA 公钥加密文本 (PKCS#1 v1.5)
        
        Args:
            plaintext: 明文字符串
            
        Returns:
            Base64 编码的密文，失败返回 None
        """
        if not self.rsa_public_key:
            return None
        
        try:
            # 尝试解析 PEM 格式
            if "-----BEGIN" in self.rsa_public_key:
                key = RSA.import_key(self.rsa_public_key)
            else:
                # 尝试 XML 格式（DanHengServer 默认）
                key = self._parse_xml_rsa_key(self.rsa_public_key)
            
            cipher = PKCS1_v1_5.new(key)
            encrypted = cipher.encrypt(plaintext.encode('utf-8'))
            return base64.b64encode(encrypted).decode('utf-8')
            
        except Exception as e:
            print(f"[错误] RSA 加密失败: {e}")
            return None
    
    def _parse_xml_rsa_key(self, xml_key: str) -> RSA.RsaKey:
        """
        解析 XML 格式的 RSA 公钥
        """
        import re
        
        # 提取 Modulus 和 Exponent
        modulus_match = re.search(r'<Modulus>([^<]+)</Modulus>', xml_key)
        exponent_match = re.search(r'<Exponent>([^<]+)</Exponent>', xml_key)
        
        if not modulus_match or not exponent_match:
            raise ValueError("无效的 XML RSA 密钥格式")
        
        modulus = int.from_bytes(base64.b64decode(modulus_match.group(1)), 'big')
        exponent = int.from_bytes(base64.b64decode(exponent_match.group(1)), 'big')
        
        return RSA.construct((modulus, exponent))
    
    # ============================================
    # API 方法
    # ============================================
    
    def create_session(self, key_type: str = "PEM") -> Tuple[bool, str]:
        """
        创建会话
        
        Args:
            key_type: 密钥类型，"PEM" 或 "XML"
            
        Returns:
            (成功标志, 消息)
        """
        success, result = self._request(
            "POST", 
            ENDPOINT_CREATE_SESSION,
            data={"key_type": key_type}
        )
        
        if success and result.get("data"):
            data = result["data"]
            self.session_id = data.get("sessionId")
            self.rsa_public_key = data.get("rsaPublicKey")
            self.expire_timestamp = data.get("expireTimeStamp")
            return True, "会话创建成功"
        
        return False, result.get("message", "创建会话失败")
    
    def auth_admin(self, admin_key: Optional[str] = None) -> Tuple[bool, str]:
        """
        授权管理员
        
        Args:
            admin_key: 管理密钥，如果为 None 则从配置文件读取
            
        Returns:
            (成功标志, 消息)
        """
        if not self.session_id:
            return False, "请先创建会话"
        
        key = admin_key or get_admin_key()
        if not key:
            return False, "未配置管理密钥"
        
        # RSA 加密密钥
        encrypted_key = self._encrypt_with_rsa(key)
        if not encrypted_key:
            return False, "密钥加密失败"
        
        success, result = self._request(
            "POST",
            ENDPOINT_AUTH_ADMIN,
            data={
                "SessionId": self.session_id,
                "admin_key": encrypted_key
            }
        )
        
        if success:
            self.is_authorized = True
            if result.get("data"):
                self.expire_timestamp = result["data"].get("expireTimeStamp")
            return True, "授权成功"
        
        return False, result.get("message", "授权失败")
    
    def exec_command(self, command: str, target_uid: int) -> Tuple[bool, str]:
        """
        执行命令
        
        Args:
            command: 要执行的命令
            target_uid: 目标玩家 UID
            
        Returns:
            (成功标志, 命令输出)
        """
        if not self.session_id or not self.is_authorized:
            return False, "请先授权"
        
        # RSA 加密命令
        encrypted_cmd = self._encrypt_with_rsa(command)
        if not encrypted_cmd:
            return False, "命令加密失败"
        
        success, result = self._request(
            "POST",
            ENDPOINT_EXEC_CMD,
            data={
                "SessionId": self.session_id,
                "Command": encrypted_cmd,
                "TargetUid": target_uid
            }
        )
        
        if success and result.get("data"):
            # 解码 Base64 输出
            message = result["data"].get("message", "")
            try:
                decoded = base64.b64decode(message).decode('utf-8')
                return True, decoded
            except:
                return True, message
        
        return False, result.get("message", "命令执行失败")
    
    def get_server_info(self) -> Tuple[bool, Dict[str, Any]]:
        """
        获取服务器状态
        
        Returns:
            (成功标志, 服务器信息)
        """
        if not self.session_id:
            return False, {"message": "请先创建会话"}
        
        success, result = self._request(
            "GET",
            ENDPOINT_SERVER_INFO,
            params={"SessionId": self.session_id}
        )
        
        if success and result.get("data"):
            return True, result["data"]
        
        return False, {"message": result.get("message", "获取服务器信息失败")}
    
    def get_player_info(self, uid: int) -> Tuple[bool, Dict[str, Any]]:
        """
        获取玩家信息
        
        Args:
            uid: 玩家 UID
            
        Returns:
            (成功标志, 玩家信息)
        """
        if not self.session_id:
            return False, {"message": "请先创建会话"}
        
        success, result = self._request(
            "GET",
            ENDPOINT_PLAYER_INFO,
            params={
                "SessionId": self.session_id,
                "Uid": uid
            }
        )
        
        if success and result.get("data"):
            return True, result["data"]
        
        return False, {"message": result.get("message", "获取玩家信息失败")}
    
    def connect(self, admin_key: Optional[str] = None) -> Tuple[bool, str]:
        """
        完整的连接流程：创建会话 -> 授权
        
        Args:
            admin_key: 管理密钥
            
        Returns:
            (成功标志, 消息)
        """
        # 创建会话
        success, msg = self.create_session()
        if not success:
            return False, f"创建会话失败: {msg}"
        
        # 授权
        success, msg = self.auth_admin(admin_key)
        if not success:
            return False, f"授权失败: {msg}"
        
        return True, "连接成功"
    
    def disconnect(self):
        """断开连接，清理状态"""
        self.session_id = None
        self.rsa_public_key = None
        self.expire_timestamp = None
        self.is_authorized = False
