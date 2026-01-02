# NDHSM - New DanHeng Server Manager

一套跨平台的 DanHeng 私服管理工具集，支持 Windows、Linux 和 Termux（Android）。

## 🚀 一键部署

### Linux Debian 13

```bash
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/Debian13/deploy.sh | bash
```

**无头模式（跳过交互）：**
```bash
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/Debian13/deploy.sh | bash -s -- --headless
```

**手动设置 GC 内存限制（Termux 推荐）：**
```bash
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/Debian13/deploy.sh | bash -s -- --headless --gc-limit 128
```

### Termux (Android)

```bash
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/TermuxToDebian13/setup_debian.sh | bash
```

安装完成后，输入 `debian` 进入 Debian 环境，然后运行上方的 Linux 部署命令。

### Windows

> 需要 Python 3.10+。

```bash
# 远程下载并运行
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Windows/install.ps1 | powershell -
```

```bash
# 手动运行
git clone https://github.com/GamblerIX/DanHeng.git
cd DanHeng/NDHSM/Windows
pip install -r requirements.txt
python main.py
```

## 📋 默认端口

| 服务 | 端口 | 协议 |
|------|------|------|
| HTTP/MUIP | 23300 | TCP |
| GameServer | 23301 | UDP |

## 🔧 常用命令

```bash
# 查看服务控制台
screen -r danheng

# 分离控制台（不停止服务）
Ctrl+A+D

# 停止服务
screen -X -S danheng quit
```

## 📚 相关链接

- [DanHengServer](https://github.com/GamblerIX/DanHengServer) - 服务端
- [DanHengProxy](https://github.com/GamblerIX/DanHengProxy) - 代理工具
- [DanHengServerResources](https://github.com/GamblerIX/DanHengServerResources) - 资源文件
- [NDHSM](https://github.com/GamblerIX/NDHSM) - 自动化工具
- [DanHeng](https://github.com/GamblerIX/DanHeng) - 链接上述所有仓库
- [开发文档](./Docs/) - 项目开发相关文档

## 📄 许可证

本项目基于 GNU AGPLv3 许可证开源。
