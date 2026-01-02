# NDHSM - New DanHeng Server Manager

一套针对 DanHeng 的全自动部署与管理工具集，支持 Linux 服务器及安卓 Termux 环境。

## 🚀 一键部署

### Linux Debian 13

```bash
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/DeployOnDebian13/deploy.sh | bash
```

**通过加速代理下载（国内网络使用）：**
```bash
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/DeployOnDebian13/deploy.sh | bash -s -- --gh-proxy
```

**Termux 一键部署**

#### 第一步（安装 Debian）
```bash
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/TermuxToDebian13/setup_debian.sh | bash
debian
```

#### 第二步（Termux专用部署）

```bash
bash deploy.sh --termux
```

## 📚 相关链接

- [DanHengServer](https://github.com/GamblerIX/DanHengServer) - 服务端
- [DanHengProxy](https://github.com/GamblerIX/DanHengProxy) - 代理工具
- [DanHengServerResources](https://github.com/GamblerIX/DanHengServerResources) - 资源文件
- [NDHSM](https://github.com/GamblerIX/NDHSM) - 自动化工具
- [DanHeng](https://github.com/GamblerIX/DanHeng) - 链接上述所有仓库
- [开发文档](./Docs/) - 项目开发相关文档

## 📄 许可证

本项目基于 [GNU AGPLv3](LICENSE) 许可证开源。
