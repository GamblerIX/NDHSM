# NDHSM - New DanHeng Server Manager

一套针对 DanHeng 的全自动部署与管理工具集，支持 Linux 服务器及安卓 Termux 环境。

## 🚀 一键部署

### Linux Debian 13

**标准部署（交互模式，可选择软件源）：**
```bash
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/DeployOnDebian13/deploy.sh | bash
```

**无头模式部署（默认使用阿里云源）：**
```bash
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/DeployOnDebian13/deploy.sh | bash -s -- --headless
```

### Termux 一键部署

#### 第一步（安装 Debian）
```bash
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/TermuxToDebian13/setup_debian.sh | bash
debian
```

#### 第二步（Termux 专用部署）
```bash
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/DeployOnDebian13/deploy.sh | bash -s -- --termux
```

## 🎮 启动与管理

部署完成后，使用系统快捷指令 `DHS` 启动服务：

```bash
DHS
```

该命令会：
1. 自动计算并配置 .NET GC 限制（针对低内存环境优化）
2. 在前台启动 DanHengServer（方便查看实时日志）

> **注意**: 
> 1. 服务不会在部署完成后自动启动，需手动运行 `DHS`。
> 2. 部署脚本不再自动修改 `Config.json`。如需修改端口或数据库配置，请在首次启动后编辑生成的配置文件，然后重启服务。

## 📋 命令参数

| 参数 | 说明 |
|------|------|
| `--headless`, `-H` | 无头模式，跳过交互（默认使用阿里云源） |
| `--termux` | Termux 优化模式（无头 + GC 限制 128MB） |
| `--no-mirror` | 无头模式下跳过换源 |
| `--http-port PORT` | 提示用户配置端口（仅提示，不再自动修改文件） |
| `--mysql` | 启用 MySQL 模式（在启动指令中修改 Config.json） |
| `--delete` | 彻底删除安装目录及全部数据 |

## 📚 相关链接

- [DanHengServer](https://github.com/GamblerIX/DanHengServer) - 服务端
- [DanHengProxy](https://github.com/GamblerIX/DanHengProxy) - 代理工具
- [DanHengServerResources](https://github.com/GamblerIX/DanHengServerResources) - 资源文件
- [NDHSM](https://github.com/GamblerIX/NDHSM) - 自动化工具
- [DanHeng](https://github.com/GamblerIX/DanHeng) - 链接上述所有仓库

## 📄 许可证

本项目基于 [GNU AGPLv3](LICENSE) 许可证开源。
