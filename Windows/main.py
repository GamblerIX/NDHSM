# ============================================
# NDHSM Windows 管理工具 - 程序入口
# 相关文件: main_window.py, config.py, muip_client.py,
#           auto_setup.py, proxy_manager.py
# ============================================
"""
NDHSM - DanHeng Server Manager
Windows 端主程序入口

使用方法:
    python main.py          # 启动 GUI
    python main.py --setup  # 仅运行自动配置
"""

import sys
import os

# 添加当前目录到路径
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def main():
    """主函数"""
    # 解析命令行参数
    if len(sys.argv) > 1:
        arg = sys.argv[1].lower()
        
        if arg in ("--setup", "-s"):
            # 仅运行自动配置
            from auto_setup import quick_setup
            use_gitee = "--gitee" in sys.argv
            success, msg = quick_setup(use_gitee=use_gitee)
            print(f"\n结果: {'成功' if success else '失败'}")
            print(f"消息: {msg}")
            return 0 if success else 1
        
        elif arg in ("--help", "-h"):
            print(__doc__)
            print("参数:")
            print("  --setup, -s   仅运行自动配置")
            print("  --gitee       使用 Gitee 镜像")
            print("  --help, -h    显示帮助信息")
            return 0
    
    # 启动 GUI
    from main_window import run_app
    return run_app()


if __name__ == "__main__":
    sys.exit(main())
