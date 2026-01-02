# NDHSM - New DanHeng Server Manager

一套针对 DanHeng 的全自动部署与管理工具集，支持 Linux 服务器及安卓 Termux 环境。

## 🚀 一键部署

### Linux Debian 13

```bash
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/DeployOnDebian13/deploy.sh | bash
```

**通过加速代理下载（国内网络使用）：**
```bash
# 自动选择最快代理
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/DeployOnDebian13/deploy.sh | bash -s -- --gh-proxy

# 强制指定特定代理 (例如强制使用 gh-proxy.org)
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/DeployOnDebian13/deploy.sh | bash -s -- --ghproxyset https://gh-proxy.org/
```

**Termux 一键部署**

> Termux部署方式始终使用国内加速网络，且脚本会自动进行**带宽竞速测试**，从多个预设代理中选取下载速度最快的节点。

#### 第一步（安装 Debian）
```bash
curl -sSL https://gh-proxy.org/https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/TermuxToDebian13/setup_debian.sh | bash
debian
# 保留这行注释以避免输入Enter
```

#### 第二步（Termux专用部署）

```bash
# 自动竞速最优节点
curl -sSL https://gh-proxy.org/https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/DeployOnDebian13/deploy.sh | bash -s -- --termux

# 若特定节点不稳定，可强制指定常用代理
curl -sSL https://gh-proxy.org/https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/DeployOnDebian13/deploy.sh | bash -s -- --termux --ghproxyset https://ghproxy.net/
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
