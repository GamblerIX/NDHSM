# ============================================
# NDHSM Windows 管理工具 - 自动配置模块
# 相关文件: config.py, main_window.py
# ============================================
"""
自动配置模块
- DanHengServer 下载/编译
- DanHengServerResources 克隆
- Config.json 自动生成
"""

import os
import sys
import subprocess
import shutil
import zipfile
import requests
from pathlib import Path
from typing import Optional, Callable, Tuple
from concurrent.futures import ThreadPoolExecutor

from config import (
    get_app_dir, get_server_dir, get_resources_dir, get_proxy_dir,
    get_config_path, get_default_config, save_config, load_config,
    GITHUB_SERVER_REPO, GITHUB_RESOURCES_REPO, GITHUB_PROXY_REPO,
    GITEE_SERVER_REPO, GITEE_RESOURCES_REPO, GITEE_PROXY_REPO
)

# ============================================
# GitHub API 配置
# ============================================

GITHUB_API_RELEASES = "https://api.github.com/repos/GamblerIX/DanHengServer/releases/latest"
GITHUB_ACTIONS_ARTIFACTS = "https://github.com/StopWuyu/DanhengServer/actions"


# ============================================
# 进度回调类型
# ============================================

# 回调函数类型: (阶段名称, 进度百分比, 详细消息)
ProgressCallback = Callable[[str, int, str], None]


def default_progress(stage: str, percent: int, message: str):
    """默认进度回调，打印到控制台"""
    print(f"[{stage}] {percent}% - {message}")


# ============================================
# Git 操作
# ============================================

def clone_repo(url: str, target_dir: Path, progress: ProgressCallback = default_progress) -> bool:
    """
    克隆 Git 仓库
    
    Args:
        url: 仓库 URL
        target_dir: 目标目录
        progress: 进度回调
        
    Returns:
        是否成功
    """
    try:
        import git
        
        if target_dir.exists():
            progress("克隆", 100, f"目录已存在: {target_dir.name}")
            return True
        
        progress("克隆", 0, f"开始克隆 {url}")
        
        # 使用 GitPython 克隆
        git.Repo.clone_from(
            url, 
            str(target_dir),
            progress=lambda op, cur, tot, msg: progress(
                "克隆", 
                int(cur / max(tot, 1) * 100) if tot else 50,
                msg or f"正在下载..."
            )
        )
        
        progress("克隆", 100, "克隆完成")
        return True
        
    except ImportError:
        # 如果没有 GitPython，使用命令行
        progress("克隆", 0, f"使用 git 命令行克隆 {url}")
        try:
            result = subprocess.run(
                ["git", "clone", "--depth", "1", url, str(target_dir)],
                capture_output=True,
                text=True,
                timeout=600
            )
            if result.returncode == 0:
                progress("克隆", 100, "克隆完成")
                return True
            else:
                progress("克隆", 0, f"克隆失败: {result.stderr}")
                return False
        except FileNotFoundError:
            progress("克隆", 0, "未找到 git 命令，请先安装 Git")
            return False
        except subprocess.TimeoutExpired:
            progress("克隆", 0, "克隆超时")
            return False
    except Exception as e:
        progress("克隆", 0, f"克隆失败: {e}")
        return False


# ============================================
# 自动配置类
# ============================================

class AutoSetup:
    """
    自动配置管理器
    负责 DanHeng 环境的自动部署和配置
    """
    
    def __init__(self, use_gitee: bool = False, progress: ProgressCallback = default_progress):
        """
        初始化自动配置器
        
        Args:
            use_gitee: 是否使用 Gitee（国内镜像）
            progress: 进度回调函数
        """
        self.use_gitee = use_gitee
        self.progress = progress
        
        # 选择仓库源
        if use_gitee:
            self.server_repo = GITEE_SERVER_REPO
            self.resources_repo = GITEE_RESOURCES_REPO
            self.proxy_repo = GITEE_PROXY_REPO
        else:
            self.server_repo = GITHUB_SERVER_REPO
            self.resources_repo = GITHUB_RESOURCES_REPO
            self.proxy_repo = GITHUB_PROXY_REPO
    
    def check_environment(self) -> Tuple[bool, str]:
        """
        检查运行环境
        
        Returns:
            (是否满足要求, 状态消息)
        """
        issues = []
        
        # 检查 Git
        try:
            result = subprocess.run(
                ["git", "--version"],
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode != 0:
                issues.append("Git 不可用")
        except FileNotFoundError:
            issues.append("未安装 Git")
        except subprocess.TimeoutExpired:
            issues.append("Git 响应超时")
        
        # 检查 .NET SDK（可选，用于编译）
        try:
            result = subprocess.run(
                ["dotnet", "--version"],
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode == 0:
                self.dotnet_available = True
            else:
                self.dotnet_available = False
        except:
            self.dotnet_available = False
        
        if issues:
            return False, "环境检查失败: " + ", ".join(issues)
        
        return True, "环境检查通过"
    
    def setup_server(self) -> bool:
        """
        设置 DanHengServer
        优先下载预编译版本，否则克隆源码
        """
        server_dir = get_server_dir()
        
        if server_dir.exists() and (server_dir / "GameServer.exe").exists():
            self.progress("服务器", 100, "DanHengServer 已存在")
            return True
        
        self.progress("服务器", 10, "正在设置 DanHengServer...")
        
        # 尝试克隆仓库（如果目录不存在）
        if not server_dir.exists():
            success = clone_repo(self.server_repo, server_dir, self.progress)
            if not success:
                return False
        
        # 检查是否需要编译
        if not (server_dir / "GameServer.exe").exists():
            if self.dotnet_available:
                self.progress("服务器", 60, "正在编译...")
                success = self._build_server(server_dir)
                if not success:
                    self.progress("服务器", 0, "编译失败，请手动下载预编译版本")
                    return False
            else:
                self.progress("服务器", 0, "未找到预编译版本且无法编译，请安装 .NET SDK 或手动下载")
                return False
        
        self.progress("服务器", 100, "DanHengServer 设置完成")
        return True
    
    def _build_server(self, server_dir: Path) -> bool:
        """编译 DanHengServer"""
        try:
            result = subprocess.run(
                ["dotnet", "build", "-c", "Release"],
                cwd=str(server_dir),
                capture_output=True,
                text=True,
                timeout=300
            )
            return result.returncode == 0
        except Exception as e:
            self.progress("服务器", 0, f"编译错误: {e}")
            return False
    
    def setup_resources(self) -> bool:
        """
        设置资源文件
        克隆 DanHengServerResources 到 DanHengServer/Resources
        """
        resources_dir = get_resources_dir()
        source_dir = get_app_dir() / "DanHengServerResources"
        
        if resources_dir.exists() and any(resources_dir.iterdir()):
            self.progress("资源", 100, "Resources 已存在")
            return True
        
        self.progress("资源", 10, "正在设置资源文件...")
        
        # 如果 DanHengServerResources 已存在，创建符号链接或复制
        if source_dir.exists():
            self.progress("资源", 50, "正在链接资源文件...")
            try:
                # 尝试创建符号链接
                if not resources_dir.exists():
                    resources_dir.symlink_to(source_dir, target_is_directory=True)
                self.progress("资源", 100, "资源链接完成")
                return True
            except OSError:
                # Windows 需要管理员权限创建符号链接，改为复制
                self.progress("资源", 50, "正在复制资源文件...")
                try:
                    shutil.copytree(source_dir, resources_dir)
                    self.progress("资源", 100, "资源复制完成")
                    return True
                except Exception as e:
                    self.progress("资源", 0, f"复制失败: {e}")
                    return False
        else:
            # 克隆到服务器目录下
            success = clone_repo(self.resources_repo, resources_dir, self.progress)
            if success:
                self.progress("资源", 100, "资源克隆完成")
            return success
    
    def setup_config(self, 
                     http_port: int = 520, 
                     game_port: int = 23301,
                     host: str = "127.0.0.1") -> bool:
        """
        生成或更新 Config.json
        
        Args:
            http_port: HTTP/MUIP 端口
            game_port: 游戏服务器端口
            host: 主机地址
        """
        config_path = get_config_path()
        
        self.progress("配置", 10, "正在生成配置文件...")
        
        # 如果配置已存在，更新关键字段
        existing_config = load_config()
        if existing_config:
            existing_config["HttpServer"]["Port"] = http_port
            existing_config["HttpServer"]["PublicAddress"] = host
            existing_config["GameServer"]["Port"] = game_port
            existing_config["GameServer"]["PublicAddress"] = host
            config = existing_config
            self.progress("配置", 50, "更新现有配置...")
        else:
            # 生成新配置
            config = get_default_config()
            config["HttpServer"]["Port"] = http_port
            config["HttpServer"]["PublicAddress"] = host
            config["GameServer"]["Port"] = game_port
            config["GameServer"]["PublicAddress"] = host
            self.progress("配置", 50, "生成新配置...")
        
        # 保存配置
        if save_config(config):
            self.progress("配置", 100, f"配置已保存: {config_path}")
            return True
        else:
            self.progress("配置", 0, "保存配置失败")
            return False
    
    def run_full_setup(self, 
                       http_port: int = 520, 
                       game_port: int = 23301,
                       host: str = "127.0.0.1") -> Tuple[bool, str]:
        """
        执行完整的自动配置流程
        
        Returns:
            (是否成功, 状态消息)
        """
        # 1. 检查环境
        success, msg = self.check_environment()
        if not success:
            return False, msg
        
        # 2. 设置服务器
        if not self.setup_server():
            return False, "DanHengServer 设置失败"
        
        # 3. 设置资源
        if not self.setup_resources():
            return False, "资源文件设置失败"
        
        # 4. 生成配置
        if not self.setup_config(http_port, game_port, host):
            return False, "配置文件生成失败"
        
        return True, "自动配置完成！"


# ============================================
# 便捷函数
# ============================================

def quick_setup(use_gitee: bool = False, 
                progress: ProgressCallback = default_progress) -> Tuple[bool, str]:
    """
    快速配置（使用默认参数）
    """
    setup = AutoSetup(use_gitee=use_gitee, progress=progress)
    return setup.run_full_setup()


if __name__ == "__main__":
    # 命令行测试
    print("=" * 50)
    print("NDHSM 自动配置工具")
    print("=" * 50)
    
    use_gitee = "--gitee" in sys.argv
    success, msg = quick_setup(use_gitee=use_gitee)
    
    print("=" * 50)
    print(f"结果: {'成功' if success else '失败'}")
    print(f"消息: {msg}")
