# NDHSM 项目架构文档

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
│   ├── Debian13/
│   │   └── deploy.sh          # Debian 13 全自动部署脚本
│   └── TermuxToDebian13/
│       └── setup_debian.sh    # Termux 安装 Debian 脚本
└── Docs/
    ├── requirements.md        # 需求文档
    └── architecture.md        # 架构文档（本文件）
```

## 🖥️ Windows 管理工具

### 技术栈
- **Python 3.10+**
- **PySide6 + QFluentWidgets** - 现代化 Fluent UI
- **RSA 加密** - MUIP API 安全认证

### 功能模块

| 模块 | 文件 | 说明 |
|------|------|------|
| 主界面 | `main_window.py` | Fluent 风格主窗口 |
| 配置管理 | `config.py` | 读写 Config.json |
| MUIP 客户端 | `muip_client.py` | RSA 加密 API 调用 |
| 自动配置 | `auto_setup.py` | 下载服务器/克隆资源 |
| 代理管理 | `proxy_manager.py` | DanHengProxy 控制 |

## 🐧 Linux 部署脚本

### deploy.sh 部署流程

1. **安装依赖** - curl, wget, git, screen, jq
2. **下载服务器** - 从 GitHub Releases 获取自包含版本
3. **克隆资源文件** - DanHengServerResources
4. **创建 dh 用户** - 设置可执行权限
5. **配置防火墙** - 开放服务端口 (可选)
6. **启动服务** - screen 后台运行
7. **配置 Config.json** - 服务启动后自动生成并修改

### 命令行参数

| 参数 | 说明 |
|------|------|
| `--headless`, `-H` | 无头模式，跳过交互 |
| `--http-port PORT` | HTTP/MUIP 端口（默认 23300） |
| `--game-port PORT` | 游戏端口（默认 23301） |
| `--host HOST` | 公网地址 |
| `--skip-firewall` | 跳过防火墙配置 |
| `--gc-limit MB` | 手动设置 .NET GC 内存限制（单位 MB） |

## 📱 Termux 环境

### setup_debian.sh 流程

1. 配置中科大 Termux 源
2. 安装 proot-distro
3. 安装 Debian 13
4. 配置 Debian 中科大源
5. 创建 `debian` 快捷命令

### 注意事项

- Termux proot 环境不支持 systemd
- 防火墙命令可能因权限限制而失败（已做容错处理）
- 使用 screen 管理服务进程

## 🔧 Config.json 完整配置

```json
{
  "HttpServer": {
    "BindAddress": "0.0.0.0",
    "PublicAddress": "0.0.0.0",
    "Port": 23300,
    "UseSSL": true,
    "UseFetchRemoteHotfix": false
  },
  "KeyStore": {
    "KeyStorePath": "certificate.p12",
    "KeyStorePassword": "123456"
  },
  "GameServer": {
    "BindAddress": "0.0.0.0",
    "PublicAddress": "0.0.0.0",
    "Port": 23301,
    "GameServerId": "dan_heng",
    "GameServerName": "DanhengServer",
    "GameServerDescription": "A re-implementation of StarRail server",
    "UsePacketEncryption": true
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
    "DatabaseName": "danheng.db"
  },
  "ServerOption": {
    "StartTrailblazerLevel": 1,
    "AutoUpgradeWorldLevel": true,
    "EnableMission": true,
    "EnableQuest": true,
    "AutoLightSection": true,
    "Language": "CHS",
    "FallbackLanguage": "EN",
    "DefaultPermissions": ["*"],
    "AutoCreateUser": true,
    "FarmingDropRate": 1,
    "UseCache": false
  },
  "MuipServer": {
    "AdminKey": ""
  }
}
```
