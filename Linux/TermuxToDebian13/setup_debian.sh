#!/data/data/com.termux/files/usr/bin/bash
# ============================================
# NDHSM Termux 转 Debian 13 脚本
# 相关文件: ../DeployOnDebian13/deploy.sh
# ============================================
#
# 功能说明:
# 1. 安装 proot-distro
# 2. 安装 Debian 13
# 3. 添加 "debian" 快捷命令
#
# 使用方法:
#   bash setup_debian.sh
#
# 安装完成后:
#   输入 "debian" 即可启动 Debian 13 环境
#
# ============================================

set -e

# ============================================
# 配置变量（便于修改）
# ============================================

# Debian 发行版代号
DEBIAN_DISTRO="debian"

# 快捷命令名称
SHORTCUT_NAME="debian"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================
# 工具函数
# ============================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP $1/3]${NC} $2"
}

check_termux() {
    if [ ! -d "/data/data/com.termux" ]; then
        log_error "此脚本只能在 Termux 环境中运行"
        exit 1
    fi
}

# ============================================
# 步骤 1: 安装 proot-distro
# ============================================

install_proot_distro() {
    log_step 1 "安装 proot-distro..."
    
    # 检查是否已安装
    if command -v proot-distro &> /dev/null; then
        log_info "proot-distro 已安装"
        return 0
    fi
    
    # 尝试更新并安装
    apt-get update -qq && apt-get install -y -qq proot-distro
    
    if command -v proot-distro &> /dev/null; then
        log_success "proot-distro 安装完成"
    else
        log_error "proot-distro 安装失败"
        exit 1
    fi
}

# ============================================
# 步骤 2: 安装 Debian 13
# ============================================

install_debian() {
    log_step 2 "安装 Debian 13..."
    
    # 检查是否已安装（检测 rootfs 目录）
    local rootfs_dir="$PREFIX/var/lib/proot-distro/installed-rootfs/debian"
    if [ -d "$rootfs_dir" ]; then
        log_info "Debian 已安装"
        return 0
    fi
    
    log_info "正在下载并安装 Debian 13，请耐心等待..."
    
    # 安装 Debian
    proot-distro install "$DEBIAN_DISTRO"
    
    # 验证安装（检查 rootfs 目录是否存在）
    local rootfs_dir="$PREFIX/var/lib/proot-distro/installed-rootfs/debian"
    if [ -d "$rootfs_dir" ]; then
        log_success "Debian 安装完成"
    else
        log_error "Debian 安装失败"
        exit 1
    fi
}

# ============================================
# 步骤 3: 添加快捷命令
# ============================================

setup_shortcut() {
    log_step 3 "添加快捷命令..."
    
    local shortcut_path="$PREFIX/bin/$SHORTCUT_NAME"
    
    # 创建快捷脚本
    cat > "$shortcut_path" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# DanHeng Debian 13 快捷启动脚本
# 使用方法: debian [命令]

if [ $# -eq 0 ]; then
    # 无参数时进入交互式 shell
    proot-distro login debian
else
    # 有参数时执行命令
    proot-distro login debian -- "$@"
fi
EOF
    
    # 添加可执行权限
    chmod +x "$shortcut_path"
    
    log_success "快捷命令 '$SHORTCUT_NAME' 已创建"
    log_info "输入 '$SHORTCUT_NAME' 即可启动 Debian 13"
}

# ============================================
# 主流程
# ============================================

main() {
    echo ""
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}  NDHSM Termux 转 Debian 13 脚本${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""
    
    # 检查环境
    check_termux
    
    # 执行步骤
    install_proot_distro
    install_debian
    setup_shortcut
    
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  安装完成！${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo -e "使用方法:"
    echo -e "  启动 Debian:    ${YELLOW}${SHORTCUT_NAME}${NC}"
    echo -e "  执行命令:       ${YELLOW}${SHORTCUT_NAME} <命令>${NC}"
    echo -e "  退出 Debian:    ${YELLOW}exit${NC}"
    echo ""
    echo -e "后续步骤:"
    echo -e "  1. 输入 '${YELLOW}${SHORTCUT_NAME}${NC}' 进入 Debian 环境"
    echo -e "  2. 运行 DanHeng 部署脚本:"
    echo -e "     ${YELLOW}curl -sSL https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/DeployOnDebian13/deploy.sh | bash${NC}"
    echo ""
}

# 运行
main "$@"
