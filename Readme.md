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

> 该命令会在后台启动 DanHengServer 
> 服务不会在部署完成后自动启动，需手动运行 `DHS`。


## 📋 命令参数

### deploy.sh 部署脚本

| 参数 | 说明 |
|------|------|
| `--headless`, `-H` | 无头模式，跳过交互（跳过换源） |
| `--termux` | Termux 优化模式（无头 + GC 限制 128MB） |

### DHS.sh 服务管理

| 参数 | 说明 |
|------|------|
| (无参数) | 启动服务 |
| `--stop` | 停止服务 |
| `--delete` | 彻底删除安装目录及全部数据 |
| `--help` | 显示帮助信息 |

## 📚 相关链接

- [DanHengServer](https://github.com/GamblerIX/DanHengServer) - 服务端
- [DanHengServerConfig](https://github.com/GamblerIX/DanHengServerConfig) - 服务端配置文件
- [DanHengProxy](https://github.com/GamblerIX/DanHengProxy) - 代理工具
- [DanHengServerResources](https://github.com/GamblerIX/DanHengServerResources) - 资源文件
- [NDHSM](https://github.com/GamblerIX/NDHSM) - 自动化工具
- [DanHeng](https://github.com/GamblerIX/DanHeng) - 链接上述所有仓库及官方源仓库的复刻

## 📄 许可证

本项目基于 [GNU AGPLv3](LICENSE) 许可证开源。
