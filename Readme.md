# NDHSM - New DanHeng Server Manager

一套针对 DanHeng 的全自动部署与管理工具集，支持 Linux 服务器及安卓 Termux 环境。

## 🚀 一键部署

### Linux Debian 13

**标准部署（推荐使用阿里云源加速）：**
```bash
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/DeployOnDebian13/deploy.sh | bash -s -- --mirror1
```

**使用官方源部署：**
```bash
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/DeployOnDebian13/deploy.sh | bash -s -- --mirror2
```

### Termux 一键部署

#### 第一步（安装 Debian）
```bash
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/TermuxToDebian13/setup_debian.sh | bash
debian
```

#### 第二步（Termux 专用部署）
```bash
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/DeployOnDebian13/deploy.sh | bash -s -- --termux --mirror1
```

## 🎮 启动与管理

部署完成后，使用系统快捷指令 `DHS` 启动服务：

```bash
DHS
```

该命令会：
1. 自动计算并配置 .NET GC 限制（针对低内存环境优化）
2. 在前台启动 DanHengServer（方便查看实时日志）

> **注意**: 服务不会在部署完成后自动启动，需手动运行 `DHS`。

## 📋 命令参数

| 参数 | 说明 |
|------|------|
| `--headless`, `-H` | 无头模式，跳过交互 |
| `--mirror1` | 切换 APT 源为阿里云镜像（国内推荐） |
| `--mirror2` | 切换 APT 源为官方源 |
| `--termux` | Termux 优化模式 |
| `--http-port PORT` | HTTP/MUIP 端口（默认: 23300） |
| `--gc-limit MB` | 手动设置 GC 内存限制 |
| `--mysql` | 将数据库类型替换为 MySQL |
| `--delete` | 彻底删除安装目录及全部数据 |

## 📚 相关链接

- [DanHengServer](https://github.com/GamblerIX/DanHengServer) - 服务端
- [DanHengProxy](https://github.com/GamblerIX/DanHengProxy) - 代理工具
- [DanHengServerResources](https://github.com/GamblerIX/DanHengServerResources) - 资源文件
- [NDHSM](https://github.com/GamblerIX/NDHSM) - 自动化工具
- [DanHeng](https://github.com/GamblerIX/DanHeng) - 链接上述所有仓库

## 📄 许可证

本项目基于 [GNU AGPLv3](LICENSE) 许可证开源。
