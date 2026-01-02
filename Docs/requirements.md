# NDHSM 开发需求文档

# 一、Windows 端本地服务器运行需求

1. **自动配置**：实现 DanHengServer 自动本地编译，或从 GitHub 平台自动下载；自动完成 DanHengServerResources 资源文件的放置（克隆至 DanHengServer 目录下，并重命名为 Resources）；将 Config.json 自动配置为 127.0.0.1 对应的 520 端口与 23301 端口。
2. **指令器开发**：通过连接 127.0.0.1:520 端口，并读取 Config.json 中存储的 DanHengServer 管理密钥，基于 PySide6 Fluent 框架开发美观易用的 GUI 页面，支持在页面内执行相关命令。
3. **Proxy 调用**：调用 DanHengProxy 并启用无头模式与静默模式，实现客户端请求的重定向功能。

# 二、Linux Debian 13 端全自动脚本需求

1. 自动安装或更新所需运行环境（设置中科大源），从 GitHub 自动匹配硬件架构，下载 Releases 中的最新版本压缩包，并完成自动解压部署。
2. 将 DanHengServerResources 资源文件克隆至 DanHengServer 目录下，并重命名为 Resources。
3. 提供交互式配置功能，引导用户完成 Config.json 的参数设置。
4. 创建 dh 用户，以 root 身份配置应用归属为 dh 用户，并设置 755 权限。
5. 以 dh 用户身份，基于 screen 工具启动服务端并后台运行，确保会话断开后服务持续稳定运行。
6. 以 root 身份配置防火墙（若存在），放开对应服务端口。
7. 实时输出部署完成状态及任务完成度，便于用户直观了解进度。

- 补充说明：脚本需额外支持命令行参数无头调用模式，无需人工交互即可完成全流程部署与程序启动运行。

# 三、Termux 转 Debian 13 全自动脚本需求

1. 设置中科大源。安装 proot-distro 工具。
1. 通过 proot-distro 工具自动安装 Debian 13 系统。
2. 添加快捷启动指令“debian”，输入该指令即可一键启动 Debian 13 系统。

https://github.com/GamblerIX/DanHeng.git
