# NDHSM 项目架构文档

## 📦 项目结构

```
NDHSM/
├── Linux/
│   ├── DeployOnDebian13/
│   │   └── deploy.sh          # Debian 13 全自动部署脚本
│   └── TermuxToDebian13/
│       └── setup_debian.sh    # Termux 安装 Debian 脚本
└── Docs/
    ├── requirements.md        # 需求文档
    └── architecture.md        # 架构文档（本文件）
```


## 🐧 Linux 部署脚本

### deploy.sh 部署流程

1. **依赖检测与安装** - 使用 `dpkg-query` 精准检测（curl, wget, git, unzip, jq, libicu-dev 等）。
2. **选择并检测代理** - (可选) `--gh-proxy` 自动测速并选择可用的 GitHub 加速代理。
3. **下载服务器** - 从 GitHub Releases 获取 self-contained 版本。
4. **下载资源文件** - 从 GitHub Releases 下载 DanHengServerResources ZIP 包。
5. **配置防火墙** - 支持 `ufw`, `firewalld` 和 `iptables`。
6. **启动服务** - 使用 `nohup` 后台运行，日志重定向至 `server.log`。
7. **配置 Config.json** - 服务启动后自动生成并使用 `jq` 修改。

### 命令行参数

| 参数 | 说明 |
|------|------|
| `--headless`, `-H` | 无头模式，跳过所有交互式问题 |
| `--http-port PORT` | HTTP/MUIP 端口（默认 23300） |
| `--host HOST` | 设置服务器的公网地址 |
| `--open-firewall` | 显式触发防火墙端口开放逻辑（需 root） |
| `--termux` | **Termux 专属优化**：隐含无头模式，强制安装 libicu，预设 128MB 堆限制 |
| `--gh-proxy` | 开启 GitHub 加速下载（自动测速选择最佳代理） |
| `--gc-limit MB` | 手动设置 .NET GC 堆内存上限（单位 MB） |

## 📱 Termux 环境

### setup_debian.sh 流程

1. 安装 proot-distro
2. 下载并安装 Debian 13 (Trixie/Testing)
3. 创建 `debian` 进入脚本

### 注意事项

- Termux proot 环境不支持 systemd，服务通过 `nohup` 替代。
- 必须安装 `libicu-dev` 否则 .NET 服务无法启动。
- 默认后台运行，使用 `tail -f server.log` 查看实时控制台输出。

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
