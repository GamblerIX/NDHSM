#!/data/data/com.termux/files/usr/bin/bash
# ============================================
# NDHSM Termux 转 Debian 12 脚本
# 相关文件: ../Debian12/deploy.sh
# ============================================
#
# 功能说明:
# 1. 设置中科大源
# 2. 安装 proot-distro
# 3. 安装 Debian 12
# 4. 添加 "debian" 快捷命令
#
# 使用方法:
#   bash setup_debian.sh
#
# 安装完成后:
#   输入 "debian" 即可启动 Debian 12 环境
#
# ============================================

set -e

# ============================================
# 配置变量（便于修改）
# ============================================

# 中科大 Termux 镜像
USTC_TERMUX_REPO="https://mirrors.ustc.edu.cn/termux/apt/termux-main"

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
    echo -e "${CYAN}[STEP $1/4]${NC} $2"
}

check_termux() {
    if [ ! -d "/data/data/com.termux" ]; then
        log_error "此脚本只能在 Termux 环境中运行"
        exit 1
    fi
}

# ============================================
# 步骤 1: 设置中科大源
# ============================================

setup_ustc_source() {
    log_step 1 "配置中科大 Termux 源..."
    
    # 检查是否已配置
    if grep -q "mirrors.ustc.edu.cn" "$PREFIX/etc/apt/sources.list" 2>/dev/null; then
        log_info "中科大源已配置，跳过"
        return 0
    fi
    
    # 备份原有源
    if [ -f "$PREFIX/etc/apt/sources.list" ]; then
        cp "$PREFIX/etc/apt/sources.list" "$PREFIX/etc/apt/sources.list.bak"
    fi
    
    # 手动写入中科大源
    cat > "$PREFIX/etc/apt/sources.list" << EOF
# USTC Termux Mirror
deb ${USTC_TERMUX_REPO} stable main
EOF
    
    # 更新包列表
    log_info "更新包列表..."
    apt-get update -qq
    
    log_success "中科大源配置完成"
}

# ============================================
# 步骤 2: 安装 proot-distro
# ============================================

install_proot_distro() {
    log_step 2 "安装 proot-distro..."
    
    # 检查是否已安装
    if command -v proot-distro &> /dev/null; then
        log_info "proot-distro 已安装"
        return 0
    fi
    
    # 安装依赖
    apt-get install -y -qq proot-distro
    
    if command -v proot-distro &> /dev/null; then
        log_success "proot-distro 安装完成"
    else
        log_error "proot-distro 安装失败"
        exit 1
    fi
}

# ============================================
# 步骤 3: 安装 Debian 12
# ============================================

install_debian() {
    log_step 3 "安装 Debian 12..."
    
    # 检查是否已安装
    if proot-distro list | grep -q "debian.*installed"; then
        log_info "Debian 已安装"
        return 0
    fi
    
    log_info "正在下载并安装 Debian 12，请耐心等待..."
    
    # 安装 Debian
    proot-distro install "$DEBIAN_DISTRO"
    
    # 验证安装
    if proot-distro list | grep -q "debian.*installed"; then
        log_success "Debian 12 安装完成"
    else
        log_error "Debian 安装失败"
        exit 1
    fi
    
    # 进入 Debian 配置中科大源
    log_info "配置 Debian 中科大源..."
    
    proot-distro login "$DEBIAN_DISTRO" -- bash -c '
cat > /etc/apt/sources.list << EOF
deb https://mirrors.ustc.edu.cn/debian bookworm main contrib non-free non-free-firmware
deb https://mirrors.ustc.edu.cn/debian bookworm-updates main contrib non-free non-free-firmware
deb https://mirrors.ustc.edu.cn/debian-security bookworm-security main contrib non-free non-free-firmware
EOF
apt-get update -qq
'
    
    log_success "Debian 中科大源配置完成"
}

# ============================================
# 步骤 4: 添加快捷命令
# ============================================

setup_shortcut() {
    log_step 4 "添加快捷命令..."
    
    local shortcut_path="$PREFIX/bin/$SHORTCUT_NAME"
    
    # 创建快捷脚本
    cat > "$shortcut_path" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# DanHeng Debian 12 快捷启动脚本
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
    log_info "输入 '$SHORTCUT_NAME' 即可启动 Debian 12"
}

# ============================================
# 主流程
# ============================================

main() {
    echo ""
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}  NDHSM Termux 转 Debian 12 脚本${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""
    
    # 检查环境
    check_termux
    
    # 执行步骤
    setup_ustc_source
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
    echo -e "     ${YELLOW}curl -sSL <deploy_script_url> | bash${NC}"
    echo ""
}

# 运行
main "$@"
