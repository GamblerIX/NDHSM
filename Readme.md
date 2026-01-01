# NDHSM - DanHeng Server Manager

一套跨平台的 DanHeng 私服管理工具集，支持 Windows GUI、Linux 自动化部署和 Termux（Android）环境。

## 📦 项目结构

```
NDHSM/
├── Windows/                    # Windows 管理工具 (Python + PySide6 Fluent)
│   ├── main.py                # 程序入口
│   ├── main_window.py         # 主界面
│   ├── config.py              # 配置管理
│   ├── muip_client.py         # MUIP API 客户端
│   ├── auto_setup.py          # 自动配置
│   ├── proxy_manager.py       # 代理管理
│   └── requirements.txt       # Python 依赖
├── Linux/
│   ├── Debian12/
│   │   └── deploy.sh          # Debian 12 全自动部署脚本
│   └── TermuxToDebian12/
│       └── setup_debian.sh    # Termux 安装 Debian 脚本
└── Docs/
    └── requirements.md        # 需求文档
```

## 🚀 快速开始

### Windows 管理工具

```bash
cd NDHSM/Windows
pip install -r requirements.txt
python main.py
```

**功能特性：**
- 🎨 PySide6 Fluent 现代化界面
- ⚙️ 一键自动配置（下载/编译服务器、克隆资源）
- 🔐 MUIP API 集成（RSA 加密认证）
- 📡 命令远程执行
- 🌐 代理一键启动

### Linux Debian 12 部署

```bash
# 下载并运行部署脚本
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/Debian12/deploy.sh | sudo bash

# 或无头模式
sudo bash deploy.sh --headless --http-port 520 --game-port 23301

# 使用 Gitee 镜像（国内加速）
sudo bash deploy.sh --headless --gitee
```

**部署流程：**
1. 配置中科大 APT 源
2. 安装 .NET 9.0 运行时
3. 下载最新 DanHengServer Release
4. 克隆资源文件
5. 交互式配置 Config.json
6. 创建 `dh` 用户并配置权限
7. Screen 后台运行
8. 自动配置防火墙

### Termux (Android)

```bash
# 1. 安装 Debian 12 环境
bash setup_debian.sh

# 2. 进入 Debian
debian

# 3. 在 Debian 中运行部署脚本
bash deploy.sh
```

## 📋 配置说明

### 默认端口
| 服务 | 端口 | 协议 |
|------|------|------|
| HTTP/MUIP | 520 | TCP |
| GameServer | 23301 | UDP |

### Config.json 关键配置
```json
{
  "HttpServer": {
    "Port": 520,
    "UseSSL": true
  },
  "GameServer": {
    "Port": 23301
  },
  "MuipServer": {
    "AdminKey": "服务器启动时自动生成"
  }
}
```

## 📚 相关项目

- [DanHengServer](https://github.com/GamblerIX/DanHengServer) - 服务端
- [DanHengProxy](https://github.com/GamblerIX/DanHengProxy) - 代理工具
- [DanHengServerResources](https://github.com/GamblerIX/DanHengServerResources) - 资源文件

## 📄 许可证

本项目基于 GPL-3.0 许可证开源。
