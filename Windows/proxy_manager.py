# ============================================
# NDHSM Windows 管理工具 - 代理管理模块
# 相关文件: config.py, main_window.py
# ============================================
"""
代理管理模块
- DanHengProxy 启动/停止
- 状态监控
- 日志捕获
"""

import os
import sys
import subprocess
import threading
import time
from pathlib import Path
from typing import Optional, Callable, List
from dataclasses import dataclass

from config import get_proxy_dir, get_app_dir

# ============================================
# 常量
# ============================================

PROXY_EXE_NAME = "DanHengProxy.exe"
PROXY_CONFIG_NAME = "config.json"


# ============================================
# 数据类
# ============================================

@dataclass
class ProxyStatus:
    """代理状态"""
    running: bool = False
    pid: Optional[int] = None
    start_time: Optional[float] = None
    log_lines: List[str] = None
    
    def __post_init__(self):
        if self.log_lines is None:
            self.log_lines = []


# ============================================
# 代理管理器
# ============================================

class ProxyManager:
    """
    DanHengProxy 管理器
    负责代理的启动、停止和状态监控
    """
    
    def __init__(self, 
                 proxy_dir: Optional[Path] = None,
                 log_callback: Optional[Callable[[str], None]] = None):
        """
        初始化代理管理器
        
        Args:
            proxy_dir: 代理目录，为 None 则使用默认路径
            log_callback: 日志回调函数
        """
        self.proxy_dir = proxy_dir or get_proxy_dir()
        self.log_callback = log_callback or (lambda msg: print(f"[Proxy] {msg}"))
        
        self.process: Optional[subprocess.Popen] = None
        self.status = ProxyStatus()
        self._log_thread: Optional[threading.Thread] = None
        self._stop_event = threading.Event()
    
    @property
    def proxy_exe(self) -> Path:
        """获取代理可执行文件路径"""
        return self.proxy_dir / PROXY_EXE_NAME
    
    @property
    def is_running(self) -> bool:
        """检查代理是否正在运行"""
        if self.process is None:
            return False
        return self.process.poll() is None
    
    def _log(self, message: str):
        """记录日志"""
        self.status.log_lines.append(message)
        # 限制日志行数
        if len(self.status.log_lines) > 1000:
            self.status.log_lines = self.status.log_lines[-500:]
        
        if self.log_callback:
            self.log_callback(message)
    
    def _read_output(self):
        """读取进程输出的线程"""
        if self.process is None:
            return
        
        try:
            for line in iter(self.process.stdout.readline, ''):
                if self._stop_event.is_set():
                    break
                if line:
                    self._log(line.strip())
            
            # 读取 stderr
            if self.process.stderr:
                for line in iter(self.process.stderr.readline, ''):
                    if self._stop_event.is_set():
                        break
                    if line:
                        self._log(f"[错误] {line.strip()}")
        except Exception as e:
            self._log(f"[异常] 读取输出失败: {e}")
    
    def check_proxy_exists(self) -> bool:
        """检查代理程序是否存在"""
        return self.proxy_exe.exists()
    
    def start(self, 
              headless: bool = True, 
              quiet: bool = True,
              host: Optional[str] = None,
              port: Optional[int] = None,
              ssl: Optional[bool] = None) -> bool:
        """
        启动代理
        
        Args:
            headless: 无头模式
            quiet: 静默模式
            host: 覆盖目标主机
            port: 覆盖目标端口
            ssl: 是否启用 SSL
            
        Returns:
            是否成功启动
        """
        if self.is_running:
            self._log("代理已在运行中")
            return True
        
        if not self.check_proxy_exists():
            self._log(f"代理程序不存在: {self.proxy_exe}")
            return False
        
        # 构建命令行参数
        args = [str(self.proxy_exe)]
        
        if headless:
            args.append("--headless")
        if quiet:
            args.append("--quiet")
        if host:
            args.extend(["--host", host])
        if port:
            args.extend(["--port", str(port)])
        if ssl is True:
            args.append("--ssl")
        elif ssl is False:
            args.append("--no-ssl")
        
        self._log(f"启动命令: {' '.join(args)}")
        
        try:
            # 启动进程
            self.process = subprocess.Popen(
                args,
                cwd=str(self.proxy_dir),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
            )
            
            self.status.running = True
            self.status.pid = self.process.pid
            self.status.start_time = time.time()
            
            # 启动日志读取线程
            self._stop_event.clear()
            self._log_thread = threading.Thread(target=self._read_output, daemon=True)
            self._log_thread.start()
            
            self._log(f"代理已启动 (PID: {self.process.pid})")
            return True
            
        except FileNotFoundError:
            self._log("无法启动代理：程序文件不存在")
            return False
        except PermissionError:
            self._log("无法启动代理：权限不足")
            return False
        except Exception as e:
            self._log(f"启动失败: {e}")
            return False
    
    def stop(self, timeout: float = 5.0) -> bool:
        """
        停止代理
        
        Args:
            timeout: 等待超时时间（秒）
            
        Returns:
            是否成功停止
        """
        if not self.is_running:
            self._log("代理未在运行")
            return True
        
        self._log("正在停止代理...")
        
        try:
            # 发送终止信号
            self.process.terminate()
            
            # 等待进程结束
            self._stop_event.set()
            self.process.wait(timeout=timeout)
            
            self.status.running = False
            self._log("代理已停止")
            return True
            
        except subprocess.TimeoutExpired:
            # 强制结束
            self._log("代理未响应，正在强制结束...")
            self.process.kill()
            self.process.wait()
            self.status.running = False
            self._log("代理已强制停止")
            return True
            
        except Exception as e:
            self._log(f"停止失败: {e}")
            return False
        
        finally:
            self.process = None
    
    def restart(self, **kwargs) -> bool:
        """重启代理"""
        self.stop()
        time.sleep(0.5)
        return self.start(**kwargs)
    
    def get_status(self) -> ProxyStatus:
        """获取当前状态"""
        self.status.running = self.is_running
        return self.status
    
    def get_uptime(self) -> Optional[float]:
        """获取运行时间（秒）"""
        if self.status.start_time and self.is_running:
            return time.time() - self.status.start_time
        return None
    
    def get_logs(self, last_n: int = 100) -> List[str]:
        """获取最近的日志"""
        return self.status.log_lines[-last_n:]


# ============================================
# 便捷函数
# ============================================

_default_manager: Optional[ProxyManager] = None


def get_proxy_manager() -> ProxyManager:
    """获取全局代理管理器实例"""
    global _default_manager
    if _default_manager is None:
        _default_manager = ProxyManager()
    return _default_manager


def start_proxy(headless: bool = True, quiet: bool = True) -> bool:
    """快速启动代理"""
    return get_proxy_manager().start(headless=headless, quiet=quiet)


def stop_proxy() -> bool:
    """快速停止代理"""
    return get_proxy_manager().stop()


if __name__ == "__main__":
    # 命令行测试
    print("=" * 50)
    print("NDHSM 代理管理器")
    print("=" * 50)
    
    manager = ProxyManager()
    
    if not manager.check_proxy_exists():
        print(f"[错误] 代理程序不存在: {manager.proxy_exe}")
        sys.exit(1)
    
    print("启动代理...")
    if manager.start():
        print(f"代理已启动，PID: {manager.status.pid}")
        
        try:
            input("按 Enter 键停止代理...")
        except KeyboardInterrupt:
            pass
        
        manager.stop()
    else:
        print("启动失败")
