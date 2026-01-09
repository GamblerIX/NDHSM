#!/bin/bash
# ============================================
# ChangeSource.sh - APT 软件源切换脚本
# 相关文件:
#   - ./deploy.sh (主部署脚本可调用此脚本)
# ============================================
#
# 功能说明:
#   交互式切换 Debian APT 软件源（阿里云/官方/跳过）
#
# 使用方法:
#   bash ChangeSource.sh
#
# ============================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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

# ============================================
# 前置检查
# ============================================

# 修复管道执行时的 TTY 问题
if [ ! -t 0 ] && [ -e /dev/tty ]; then
    exec < /dev/tty
fi

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    log_error "此脚本需要 root 权限运行"
    log_info "请使用: sudo bash ChangeSource.sh"
    exit 1
fi

# ============================================
# 主逻辑
# ============================================

change_apt_source() {
    local sources_file="/etc/apt/sources.list"
    local sources_dir="/etc/apt/sources.list.d"
    local backup_file="/etc/apt/sources.list.bak"
    local mirror_choice=""
    
    echo ""
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}  APT 软件源切换工具${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""
    
    # 交互模式，询问用户
    echo -e "${CYAN}请选择 APT 软件源:${NC}"
    echo "  1) 阿里云镜像（国内推荐）"
    echo "  2) Debian 官方源"
    echo "  3) 跳过，保持当前配置"
    echo ""
    read -p "请输入选项 [1/2/3] (默认: 1): " mirror_choice
    mirror_choice=${mirror_choice:-1}
    
    # 跳过换源
    if [ "$mirror_choice" = "3" ]; then
        log_info "跳过换源，保持当前配置"
        exit 0
    fi
    
    # 自动检测 Debian 版本代号
    local codename
    if [ -f /etc/os-release ]; then
        codename=$(grep "^VERSION_CODENAME=" /etc/os-release | cut -d= -f2)
    fi
    
    # 如果无法检测，默认使用 trixie (Debian 13)
    if [ -z "$codename" ]; then
        codename="trixie"
        log_warning "无法检测 Debian 版本，默认使用 $codename"
    else
        log_info "检测到 Debian 版本: $codename"
    fi
    
    # 备份原文件
    if [ ! -f "$backup_file" ]; then
        cp "$sources_file" "$backup_file"
        log_info "已备份原配置到 $backup_file"
    fi
    
    # 清理可能冲突的源文件
    rm -f "$sources_dir"/*.sources 2>/dev/null || true
    rm -f "$sources_dir"/*.list 2>/dev/null || true
    
    if [ "$mirror_choice" = "1" ]; then
        log_info "切换到阿里云镜像源（使用 HTTP 以兼容无证书环境）..."
        if [ "$codename" = "trixie" ] || [ "$codename" = "sid" ]; then
            # Debian 13 (Trixie) / Sid - 无 security 仓库分离
            cat > "$sources_file" << EOF
deb http://mirrors.aliyun.com/debian/ $codename main contrib non-free non-free-firmware
deb http://mirrors.aliyun.com/debian/ $codename-updates main contrib non-free non-free-firmware
EOF
        else
            # Debian 12 (Bookworm) 及更早版本
            cat > "$sources_file" << EOF
deb http://mirrors.aliyun.com/debian/ $codename main contrib non-free non-free-firmware
deb http://mirrors.aliyun.com/debian/ $codename-updates main contrib non-free non-free-firmware
deb http://mirrors.aliyun.com/debian-security $codename-security main contrib non-free non-free-firmware
EOF
        fi
        log_success "已切换到阿里云镜像源"
    elif [ "$mirror_choice" = "2" ]; then
        log_info "切换到官方源..."
        if [ "$codename" = "trixie" ] || [ "$codename" = "sid" ]; then
            cat > "$sources_file" << EOF
deb http://deb.debian.org/debian $codename main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $codename-updates main contrib non-free non-free-firmware
EOF
        else
            cat > "$sources_file" << EOF
deb http://deb.debian.org/debian $codename main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $codename-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security $codename-security main contrib non-free non-free-firmware
EOF
        fi
        log_success "已切换到官方源"
    else
        log_warning "无效选项，跳过换源"
        exit 0
    fi
    
    # 立即更新源索引
    log_info "正在更新软件包索引..."
    if ! apt-get update -qq 2>/dev/null; then
        log_warning "apt-get update 遇到警告，将继续尝试..."
        apt-get update 2>&1 | grep -i "^E:" && {
            log_error "更新软件包索引失败，请检查网络连接"
            exit 1
        }
    fi
    log_success "软件包索引已更新"
    
    echo ""
    log_success "换源完成！"
}

# 执行
change_apt_source
