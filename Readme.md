# NDHSM - New DanHeng Server Manager

一套针对 DanHeng 的全自动部署与管理工具集，支持 Linux 服务器及安卓 Termux 环境。

## 🚀 一键部署

### Linux Debian 13

```bash
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/DeployOnDebian13/deploy.sh | bash
```

**通过加速代理下载（国内网络使用）：**
```bash
# 自动使用可用代理
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/DeployOnDebian13/deploy.sh | bash -s -- --gh-proxy

# 强制指定特定代理 (例如强制使用 gh-proxy.org)
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/DeployOnDebian13/deploy.sh | bash -s -- --ghproxyset https://gh-proxy.org/
```

**Termux 一键部署**

> 由于 Termux 环境网络波动较大，建议根据实际情况手动选择是否开启加速代理。

#### 第一步（安装 Debian）
```bash
curl -sSL https://gh-proxy.org/https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/TermuxToDebian13/setup_debian.sh | bash
debian
# 保留这行注释以避免输入Enter
```

#### 第二步（Termux专用部署）

```bash
# 默认部署（直连）
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/DeployOnDebian13/deploy.sh | bash -s -- --termux
# 保留这行注释以避免输入Enter
```

```bash
# 开启加速代理部署（国内推荐，但是Termux下疑似存在BUG，建议谨慎使用）
curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/DeployOnDebian13/deploy.sh | bash -s -- --termux --gh-proxy
# 保留这行注释以避免输入Enter
```

## 🎮 启动与管理

部署完成后，你可以使用系统快捷指令 `DHS` 来启动服务。

```bash
DHS
```

该命令会：
1. 自动计算并配置 .NET GC 限制（针对低内存环境优化）。
2. 在前台启动 DanHengServer（方便查看实时日志和调试）。

**注意**:
- 根据最新的部署逻辑，服务**不会**在部署完成后自动后台启动，你需要手动运行 `DHS`。
- 如果你是普通用户且安装时未能创建快捷软链接，请运行安装目录下的 `./dhs_runner.sh`。

## 📚 相关链接

- [DanHengServer](https://github.com/GamblerIX/DanHengServer) - 服务端
- [DanHengProxy](https://github.com/GamblerIX/DanHengProxy) - 代理工具
- [DanHengServerResources](https://github.com/GamblerIX/DanHengServerResources) - 资源文件
- [NDHSM](https://github.com/GamblerIX/NDHSM) - 自动化工具
- [DanHeng](https://github.com/GamblerIX/DanHeng) - 链接上述所有仓库
- [开发文档](./Docs/) - 项目开发相关文档

## 📄 许可证

本项目基于 [GNU AGPLv3](LICENSE) 许可证开源。
