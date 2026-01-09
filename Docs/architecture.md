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

1. **换源** - (可选) 支持切换阿里云/官方源，解决依赖安装问题。
2. **依赖检测与安装** - 使用 `dpkg-query` 精准检测（curl, wget, git, unzip, jq, libicu-dev 等）。
3. **下载服务器** - 从 GitHub Releases 获取 self-contained 版本 (直连)。
4. **下载资源文件** - 从 GitHub Releases 下载 DanHengServerResources ZIP 包 (直连)。
5. **创建启动脚本** - 生成 `DHS` 快捷指令和 `dhs_runner.sh`，封装 GC 优化和配置环境变量。
6. **配置引导** - 提示用户手动修改 `Config.json`（不再自动生成）。

### 命令行参数

| 参数 | 说明 |
|------|------|
| `--headless`, `-H` | 无头模式，跳过所有交互式问题（默认使用阿里云源） |
| `--http-port PORT` | 提示用户配置 HTTP/MUIP 端口（仅提示，不修改文件） |
| `--host HOST` | 提示用户配置公网地址（仅提示，不修改文件） |
| `--termux` | **Termux 专属优化**：隐含无头模式，强制无头，预设 128MB 堆限制 |
| `--no-mirror` | 无头模式下跳过换源（交互模式可直接选择跳过） |
| `--mysql` | 启用 MySQL 模式（在 `DHS` 启动指令中修改 Config.json） |


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
