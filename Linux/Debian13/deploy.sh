#!/bin/bash
# ============================================
# NDHSM Linux Debian 13 全自动部署脚本
# 相关文件: ../TermuxToDebian13/setup_debian.sh
# ============================================
#
# 功能说明:
# 1. 自动安装系统依赖
# 2. 从 GitHub/Gitee 下载自包含版本服务器
# 3. 克隆资源文件
# 4. 创建 dh 用户并配置权限
# 5. 配置防火墙
# 6. 后台运行并自动生成/配置 Config.json
# 7. 无需手动安装 .NET 环境 (Self-contained)
#
# 使用方法:
#   交互模式: bash deploy.sh
#   无头模式: bash deploy.sh --headless --http-port 520 --game-port 23301
#
# ============================================

set -e

# ============================================
# 配置变量（便于修改）
# ============================================

# 默认配置
DEFAULT_HTTP_PORT=520
DEFAULT_GAME_PORT=23301
DEFAULT_HOST="0.0.0.0"
INSTALL_DIR="/opt/danheng"
SERVICE_USER="dh"

# 仓库地址
GITHUB_SERVER_RELEASES="https://api.github.com/repos/GamblerIX/DanHengServer/releases/latest"
GITEE_SERVER_RELEASES="https://gitee.com/api/v5/repos/GamblerIX/DanHengServer/releases/latest"
GITHUB_RESOURCES_REPO="https://github.com/GamblerIX/DanHengServerResources.git"
GITEE_RESOURCES_REPO="https://gitee.com/GamblerIX/DanHengServerResources.git"

# 中科大镜像
USTC_DOTNET_FEED="https://mirrors.ustc.edu.cn/dotnet"
USTC_APT_SOURCE="https://mirrors.ustc.edu.cn/debian"

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
    echo -e "${CYAN}[STEP $1/$TOTAL_STEPS]${NC} $2"
}

progress_bar() {
    local current=$1
    local total=$2
    local width=50
    local percent=$((current * 100 / total))
    local filled=$((width * current / total))
    local empty=$((width - filled))
    
    printf "\r["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' ' '
    printf "] %d%%" "$percent"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 权限运行此脚本"
        log_info "使用: sudo bash $0"
        exit 1
    fi
}

detect_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            echo "linux-x64"
            ;;
        aarch64|arm64)
            echo "linux-arm64"
            ;;
        armv7l)
            echo "linux-arm"
            ;;
        *)
            log_error "不支持的架构: $arch"
            exit 1
            ;;
    esac
}

# ============================================
# 参数解析
# ============================================

HEADLESS=false
USE_GITEE=false
HTTP_PORT=$DEFAULT_HTTP_PORT
GAME_PORT=$DEFAULT_GAME_PORT
PUBLIC_HOST=$DEFAULT_HOST
SKIP_FIREWALL=false
CONFIG_FILE=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --headless|-H)
                HEADLESS=true
                shift
                ;;
            --gitee)
                USE_GITEE=true
                shift
                ;;
            --http-port)
                HTTP_PORT="$2"
                shift 2
                ;;
            --game-port)
                GAME_PORT="$2"
                shift 2
                ;;
            --host)
                PUBLIC_HOST="$2"
                shift 2
                ;;
            --skip-firewall)
                SKIP_FIREWALL=true
                shift
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << EOF
NDHSM Linux Debian 13 全自动部署脚本

用法: bash deploy.sh [选项]

选项:
  --headless, -H      无头模式，跳过交互
  --gitee             使用 Gitee 镜像（国内加速）
  --http-port PORT    HTTP/MUIP 端口（默认: $DEFAULT_HTTP_PORT）
  --game-port PORT    游戏服务器端口（默认: $DEFAULT_GAME_PORT）
  --host HOST         公网地址（默认: $DEFAULT_HOST）
  --skip-firewall     跳过防火墙配置
  --config FILE       从配置文件读取参数
  --help, -h          显示帮助信息

示例:
  # 交互模式
  bash deploy.sh

  # 无头模式
  bash deploy.sh --headless --http-port 443 --game-port 23301

  # 使用 Gitee 镜像
  bash deploy.sh --headless --gitee
EOF
}

# ============================================
# 步骤 1: 配置中科大源
# ============================================

setup_ustc_source() {
    log_step 1 "配置中科大源..."
    
    # 备份原有源
    if [ -f /etc/apt/sources.list ]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.bak
    fi
    
    # 获取当前版本代号（默认 bookworm）
    local codename="bookworm"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [ -n "$VERSION_CODENAME" ]; then
            codename="$VERSION_CODENAME"
        fi
    fi
    log_info "检测到 Debian 版本: $codename"

    # 写入中科大源
    # 注意：trixie (testing) 安全源 URL 可能不同，这里统一处理通用格式
    if [ "$codename" == "trixie" ] || [ "$codename" == "sid" ]; then
        # Testing/Sid 版本
        cat > /etc/apt/sources.list << EOF
deb ${USTC_APT_SOURCE} $codename main contrib non-free non-free-firmware
deb ${USTC_APT_SOURCE} ${codename}-updates main contrib non-free non-free-firmware
deb https://mirrors.ustc.edu.cn/debian-security ${codename}-security main contrib non-free non-free-firmware
EOF
    else
        # Stable (bookworm) 及旧版本
        cat > /etc/apt/sources.list << EOF
deb ${USTC_APT_SOURCE} $codename main contrib non-free non-free-firmware
deb ${USTC_APT_SOURCE} ${codename}-updates main contrib non-free non-free-firmware
deb ${USTC_APT_SOURCE} ${codename}-backports main contrib non-free non-free-firmware
deb https://mirrors.ustc.edu.cn/debian-security ${codename}-security main contrib non-free non-free-firmware
EOF
    fi
    
    apt-get update -qq
    log_success "中科大源配置完成"
}

# ============================================
# 步骤 2: 安装依赖
# ============================================

install_dependencies() {
    log_step 1 "安装依赖..."
    
    # 更新包列表
    apt-get update -qq
    
    apt-get install -y -qq \
        curl \
        wget \
        git \
        unzip \
        screen \
        jq \
        ca-certificates \
        apt-transport-https
    
    log_success "依赖安装完成"
}



# ============================================
# 步骤 2: 下载服务器 (已存在则跳过)
# ============================================


download_server() {
    log_step 2 "下载 DanHengServer..."
    
    # 检测可执行文件是否已存在
    if [ -f "$INSTALL_DIR/DanhengServer" ] || [ -f "$INSTALL_DIR/GameServer" ]; then
        log_info "服务器文件已存在，跳过下载"
        return 0
    fi
    
    # 创建安装目录
    mkdir -p "$INSTALL_DIR"
    
    local arch=$(detect_arch)
    log_info "检测到架构: $arch"
    
    cd "$INSTALL_DIR"
    
    local download_url=""
    local filename=""
    
    # 辅助函数：尝试从 API 获取下载链接
    get_download_url() {
        local api_url="$1"
        local source_name="$2"
        
        log_info "正在尝试从 $source_name 获取版本信息..." >&2
        
        local release_info
        if ! release_info=$(curl -sSL --connect-timeout 10 "$api_url" 2>/dev/null); then
            log_warning "无法连接到 $source_name API" >&2
            return 1
        fi

        if [ -z "$release_info" ]; then
             log_warning "$source_name API 返回为空" >&2
             return 1
        fi
        
        # 尝试匹配架构 (仅下载 self-contained 版本)
        local url
        url=$(echo "$release_info" | jq -r ".assets[] | select(.name | contains(\"$arch\") and contains(\"self-contained\")) | .browser_download_url" 2>/dev/null | head -1)
        

        
        echo "$url"
    }

    # 1. 优先尝试 Gitee
    if [ "$download_url" == "" ] || [ "$download_url" == "null" ]; then
        download_url=$(get_download_url "$GITEE_SERVER_RELEASES" "Gitee")
    fi

    # 2. 如果失败，尝试 GitHub
    if [ -z "$download_url" ] || [ "$download_url" == "null" ]; then
        log_warning "Gitee 获取失败或未找到 Release，尝试 GitHub..."
        download_url=$(get_download_url "$GITHUB_SERVER_RELEASES" "GitHub")
    fi
    
    # 3. 最终检查
    if [ -z "$download_url" ] || [ "$download_url" == "null" ]; then
        log_error "未找到适用的下载包 (Gitee 和 GitHub 均失败)"
        log_info "请手动下载 Release 包并解压到: $INSTALL_DIR"
        exit 1
    fi
    
    log_info "下载地址: $download_url"
    
    # 下载
    filename=$(basename "$download_url")
    if wget --show-progress -O "$filename" "$download_url"; then
        log_success "下载成功"
    else
        log_error "下载失败"
        rm -f "$filename"
        exit 1
    fi
    
    # 解压
    log_info "正在解压..."
    if [[ $filename == *.zip ]]; then
        if ! unzip -o -q "$filename"; then
            log_error "解压失败 (unzip)"
            exit 1
        fi
    elif [[ $filename == *.tar.gz ]]; then
        if ! tar -xzf "$filename"; then
             log_error "解压失败 (tar)"
             exit 1
        fi
    else
        log_warning "未知的压缩格式，尝试保留文件"
    fi
    
    # 保留压缩包，待服务成功启动后删除
    # rm -f "$filename" 已移至 configure_server 函数末尾
    
    # 将子目录内容移至安装目录根目录
    # Release 包解压后会创建类似 linux-arm64-self-contained/ 的子目录
    for subdir in "$INSTALL_DIR"/*-self-contained "$INSTALL_DIR"/*-self-contained/; do
        if [ -d "$subdir" ]; then
            log_info "正在整理文件结构..."
            mv "$subdir"/* "$INSTALL_DIR/" 2>/dev/null || true
            rmdir "$subdir" 2>/dev/null || true
        fi
    done
    
    log_success "服务器文件准备就绪"
}

# ============================================
# 步骤 4: 克隆资源文件
# ============================================

clone_resources() {
    log_step 3 "克隆资源文件..."
    
    local resources_dir="$INSTALL_DIR/Resources"
    
    if [ -d "$resources_dir" ]; then
        log_info "Resources 目录已存在，跳过克隆"
        return 0
    fi
    
    local repo_url="$GITHUB_RESOURCES_REPO"
    
    # 资源仓库目前仅支持 GitHub (Gitee 需要鉴权)
    if [ "$USE_GITEE" = true ]; then
        log_info "注意: 资源文件将从 GitHub 克隆 (Gitee 镜像需鉴权)"
    fi
    
    log_info "正在克隆资源仓库..."
    git clone --depth 1 "$repo_url" "$resources_dir"
    
    log_success "资源文件克隆完成"
}

# ============================================
# 步骤 7: 配置 Config.json (服务启动后执行)
# ============================================

configure_server() {
    log_step 7 "配置 Config.json..."
    
    local config_path="$INSTALL_DIR/Config.json"
    
    # 等待 Config.json 生成 (服务首次启动会自动创建)
    log_info "等待配置文件生成..."
    local wait_count=0
    while [ ! -f "$config_path" ] && [ $wait_count -lt 30 ]; do
        sleep 1
        wait_count=$((wait_count + 1))
    done
    
    if [ ! -f "$config_path" ]; then
        log_warning "Config.json 未生成，使用默认配置"
        return 0
    fi
    
    # 停止服务
    log_info "停止服务以修改配置..."
    screen -X -S danheng quit 2>/dev/null || true
    sleep 2
    
    # 交互模式下询问用户
    if [ "$HEADLESS" = false ]; then
        echo ""
        log_info "请配置服务器参数（直接回车使用默认值）:"
        echo ""
        
        read -p "HTTP/MUIP 端口 [${HTTP_PORT}]: " input
        HTTP_PORT=${input:-$HTTP_PORT}
        
        read -p "游戏服务器端口 [${GAME_PORT}]: " input
        GAME_PORT=${input:-$GAME_PORT}
        
        read -p "公网地址 [${PUBLIC_HOST}]: " input
        PUBLIC_HOST=${input:-$PUBLIC_HOST}
        
        echo ""
    fi
    
    # 使用 jq 修改配置文件
    if command -v jq &>/dev/null; then
        local tmp_config=$(mktemp)
        jq --arg http_port "$HTTP_PORT" \
           --arg game_port "$GAME_PORT" \
           --arg public_host "$PUBLIC_HOST" \
           '.HttpServer.Port = ($http_port | tonumber) |
            .HttpServer.PublicAddress = $public_host |
            .GameServer.Port = ($game_port | tonumber) |
            .GameServer.PublicAddress = $public_host' \
           "$config_path" > "$tmp_config" && mv "$tmp_config" "$config_path"
        log_success "配置文件已更新: $config_path"
    else
        log_warning "jq 未安装，跳过配置修改 (使用默认值)"
    fi
    
    # 重新启动服务
    log_info "重新启动服务..."
    local server_exe
    cd "$INSTALL_DIR"
    if [ -f "DanhengServer" ]; then
        server_exe="./DanhengServer"
    elif [ -f "GameServer" ]; then
        server_exe="./GameServer"
    else
        log_error "未找到服务器可执行文件"
        exit 1
    fi
    
    chmod +x "$server_exe"
    su - "$SERVICE_USER" -c "cd $INSTALL_DIR && screen -dmS danheng $server_exe"
    sleep 2
    
    if screen -list | grep -q "danheng"; then
        log_success "服务已重新启动"
        
        # 清理下载的压缩包
        rm -f "$INSTALL_DIR"/*.zip "$INSTALL_DIR"/*.tar.gz 2>/dev/null || true
    else
        log_error "服务重启失败"
        exit 1
    fi
}

# ============================================
# 步骤 4: 创建用户和权限
# ============================================

setup_user() {
    log_step 4 "配置用户和权限..."
    
    # 创建 dh 用户
    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd -r -s /bin/bash -d "$INSTALL_DIR" "$SERVICE_USER"
        log_info "已创建用户: $SERVICE_USER"
    else
        log_info "用户 $SERVICE_USER 已存在"
    fi
    
    # 仅设置 DanhengServer 可执行权限
    if [ -f "$INSTALL_DIR/DanhengServer" ]; then
        chmod +x "$INSTALL_DIR/DanhengServer"
        log_success "权限配置完成"
    else
        log_warning "DanhengServer 不存在，跳过权限设置"
    fi
}

# ============================================
# 步骤 5: 配置防火墙
# ============================================

configure_firewall() {
    log_step 5 "配置防火墙..."
    
    if [ "$SKIP_FIREWALL" = true ]; then
        log_info "跳过防火墙配置"
        return 0
    fi
    
    # 检测防火墙类型并配置
    if command -v ufw &> /dev/null; then
        log_info "检测到 UFW..."
        if ufw allow "$HTTP_PORT"/tcp && ufw allow "$GAME_PORT"/udp; then
            log_success "UFW 规则已添加"
        else
            log_warning "UFW 规则添加失败 (可能是环境限制)"
        fi
        
    elif command -v firewall-cmd &> /dev/null; then
        log_info "检测到 firewalld..."
        if firewall-cmd --permanent --add-port="$HTTP_PORT"/tcp && \
           firewall-cmd --permanent --add-port="$GAME_PORT"/udp; then
            firewall-cmd --reload || true
            log_success "firewalld 规则已添加"
        else
            log_warning "firewalld 规则添加失败 (可能是环境限制)"
        fi
        
    elif command -v iptables &> /dev/null; then
        # 先测试 iptables 是否可用（Termux 环境可能无权限）
        if ! iptables -L -n &>/dev/null; then
            log_info "iptables 不可用 (可能是环境限制)，跳过配置"
        else
            log_info "使用 iptables..."
            if iptables -A INPUT -p tcp --dport "$HTTP_PORT" -j ACCEPT && \
               iptables -A INPUT -p udp --dport "$GAME_PORT" -j ACCEPT; then
                log_success "iptables 规则已添加"
            else
                log_warning "iptables 规则添加失败"
            fi
        fi
        
    else
        log_info "未检测到防火墙工具，跳过配置"
    fi
}

# ============================================
# 步骤 6: 启动服务
# ============================================

start_server() {
    log_step 6 "启动服务..."
    
    cd "$INSTALL_DIR"
    
    # 查找可执行文件
    local server_exe
    if [ -f "DanhengServer" ]; then
        server_exe="./DanhengServer"
    else
        log_error "未找到服务器可执行文件 (DanhengServer)"
        log_info "安装目录内容:"
        ls -la "$INSTALL_DIR" | head -20
        exit 1
    fi
    
    chmod +x "$server_exe"
    log_info "可执行文件: $server_exe"
    
    # 使用 screen 启动
    log_info "使用 screen 启动服务..."
    
    # .NET 环境变量 (解决 Termux proot 内存限制问题)
    export DOTNET_GCHeapHardLimit=200000000        # 限制 GC 堆为 ~200MB
    export DOTNET_EnableDiagnostics=0              # 禁用诊断
    export DOTNET_gcServer=0                       # 使用工作站 GC 模式
    
    # 检测是否在 Termux proot 环境 (用户切换可能失败)
    if [ -f /etc/proot-distro ] || [ "$EUID" -eq 0 ] && ! command -v sudo &>/dev/null; then
        # Termux 环境：直接以当前用户启动
        screen -dmS danheng "$server_exe"
    else
        # 标准 Linux 环境：以服务用户启动
        su - "$SERVICE_USER" -c "cd $INSTALL_DIR && DOTNET_GCHeapHardLimit=200000000 DOTNET_EnableDiagnostics=0 DOTNET_gcServer=0 screen -dmS danheng $server_exe"
    fi
    
    sleep 3
    
    # 检查是否启动成功
    if screen -list | grep -q "danheng"; then
        log_success "服务已启动"
        log_info "使用 'screen -r danheng' 查看控制台"
        log_info "使用 Ctrl+A+D 分离控制台"
    else
        log_error "服务启动失败"
        log_info "尝试手动启动以查看错误信息:"
        log_info "  cd $INSTALL_DIR && $server_exe"
        exit 1
    fi
}

# ============================================
# 主流程
# ============================================

TOTAL_STEPS=7

main() {
    echo ""
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}  NDHSM Linux Debian 13 自动部署脚本${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""
    
    # 解析参数
    parse_args "$@"
    
    # 检查 root 权限
    check_root
    
    # 执行部署步骤
    # setup_ustc_source
    install_dependencies
    download_server
    clone_resources
    setup_user
    configure_firewall
    start_server
    configure_server
    
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  部署完成！${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo -e "安装目录: ${CYAN}$INSTALL_DIR${NC}"
    echo -e "HTTP 端口: ${CYAN}$HTTP_PORT${NC}"
    echo -e "游戏端口: ${CYAN}$GAME_PORT${NC}"
    echo -e "运行用户: ${CYAN}$SERVICE_USER${NC}"
    echo ""
    echo -e "管理命令:"
    echo -e "  查看控制台: ${YELLOW}screen -r danheng${NC}"
    echo -e "  分离控制台: ${YELLOW}Ctrl+A+D${NC}"
    echo -e "  停止服务:   ${YELLOW}screen -X -S danheng quit${NC}"
    echo ""
}

# 运行主流程
main "$@"
