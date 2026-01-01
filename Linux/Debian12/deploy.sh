#!/bin/bash
# ============================================
# NDHSM Linux Debian 12 全自动部署脚本
# 相关文件: ../TermuxToDebian12/setup_debian.sh
# ============================================
#
# 功能说明:
# 1. 自动安装运行环境 (.NET 9.0)
# 2. 从 GitHub/Gitee 下载最新版本
# 3. 克隆资源文件
# 4. 交互式配置 Config.json
# 5. 创建 dh 用户并配置权限
# 6. Screen 后台运行
# 7. 防火墙配置
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
GITHUB_SERVER_RELEASES="https://api.github.com/repos/StopWuyu/DanhengServer/releases/latest"
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
NDHSM Linux Debian 12 全自动部署脚本

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
  sudo bash deploy.sh

  # 无头模式
  sudo bash deploy.sh --headless --http-port 443 --game-port 23301

  # 使用 Gitee 镜像
  sudo bash deploy.sh --headless --gitee
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
    
    # 写入中科大源
    cat > /etc/apt/sources.list << EOF
deb ${USTC_APT_SOURCE} bookworm main contrib non-free non-free-firmware
deb ${USTC_APT_SOURCE} bookworm-updates main contrib non-free non-free-firmware
deb ${USTC_APT_SOURCE} bookworm-backports main contrib non-free non-free-firmware
deb ${USTC_APT_SOURCE}-security bookworm-security main contrib non-free non-free-firmware
EOF
    
    apt-get update -qq
    log_success "中科大源配置完成"
}

# ============================================
# 步骤 2: 安装依赖
# ============================================

install_dependencies() {
    log_step 2 "安装依赖..."
    
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
# 步骤 3: 安装 .NET 9.0
# ============================================

install_dotnet() {
    log_step 3 "安装 .NET 9.0..."
    
    # 检查是否已安装
    if command -v dotnet &> /dev/null; then
        local version=$(dotnet --version 2>/dev/null || echo "unknown")
        if [[ $version == 9.* ]]; then
            log_info ".NET 9.0 已安装 (版本: $version)"
            return 0
        fi
    fi
    
    # 使用微软官方安装脚本
    log_info "正在下载 .NET 安装脚本..."
    curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
    chmod +x /tmp/dotnet-install.sh
    
    # 安装 .NET 9.0 运行时
    log_info "正在安装 .NET 9.0 运行时..."
    /tmp/dotnet-install.sh --channel 9.0 --runtime dotnet --install-dir /usr/share/dotnet
    
    # 创建符号链接
    ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
    
    # 验证安装
    if dotnet --info &> /dev/null; then
        log_success ".NET 9.0 安装完成"
    else
        log_error ".NET 安装失败"
        exit 1
    fi
}

# ============================================
# 步骤 4: 下载服务器
# ============================================

download_server() {
    log_step 4 "下载 DanHengServer..."
    
    local arch=$(detect_arch)
    log_info "检测到架构: $arch"
    
    # 创建安装目录
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    # 获取最新 Release
    log_info "获取最新版本信息..."
    
    local release_info
    if ! release_info=$(curl -sSL "$GITHUB_SERVER_RELEASES" 2>/dev/null); then
        log_warning "无法访问 GitHub API，尝试备用方案..."
        # 这里可以添加备用下载逻辑
        log_error "下载失败，请检查网络连接"
        exit 1
    fi
    
    # 查找对应架构的下载链接
    local download_url
    download_url=$(echo "$release_info" | jq -r ".assets[] | select(.name | contains(\"$arch\")) | .browser_download_url" | head -1)
    
    if [ -z "$download_url" ] || [ "$download_url" == "null" ]; then
        # 尝试通用包
        download_url=$(echo "$release_info" | jq -r ".assets[] | select(.name | contains(\"DanhengServer\")) | .browser_download_url" | head -1)
    fi
    
    if [ -z "$download_url" ] || [ "$download_url" == "null" ]; then
        log_error "未找到适用的下载包"
        log_info "请手动下载并解压到: $INSTALL_DIR"
        exit 1
    fi
    
    log_info "下载地址: $download_url"
    
    # 下载
    local filename=$(basename "$download_url")
    wget -q --show-progress -O "$filename" "$download_url"
    
    # 解压
    log_info "正在解压..."
    if [[ $filename == *.zip ]]; then
        unzip -o -q "$filename"
    elif [[ $filename == *.tar.gz ]]; then
        tar -xzf "$filename"
    fi
    
    rm -f "$filename"
    log_success "服务器下载完成"
}

# ============================================
# 步骤 5: 克隆资源文件
# ============================================

clone_resources() {
    log_step 5 "克隆资源文件..."
    
    local resources_dir="$INSTALL_DIR/Resources"
    
    if [ -d "$resources_dir" ]; then
        log_info "Resources 目录已存在，跳过克隆"
        return 0
    fi
    
    local repo_url
    if [ "$USE_GITEE" = true ]; then
        repo_url="$GITEE_RESOURCES_REPO"
        log_info "使用 Gitee 镜像..."
    else
        repo_url="$GITHUB_RESOURCES_REPO"
    fi
    
    log_info "正在克隆资源仓库..."
    git clone --depth 1 "$repo_url" "$resources_dir"
    
    log_success "资源文件克隆完成"
}

# ============================================
# 步骤 6: 配置 Config.json
# ============================================

configure_server() {
    log_step 6 "配置 Config.json..."
    
    local config_path="$INSTALL_DIR/config.json"
    
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
    
    # 生成配置文件
    cat > "$config_path" << EOF
{
  "HttpServer": {
    "BindAddress": "0.0.0.0",
    "PublicAddress": "${PUBLIC_HOST}",
    "Port": ${HTTP_PORT},
    "UseSSL": true,
    "UseFetchRemoteHotfix": false
  },
  "KeyStore": {
    "KeyStorePath": "certificate.p12",
    "KeyStorePassword": "123456"
  },
  "GameServer": {
    "BindAddress": "0.0.0.0",
    "PublicAddress": "${PUBLIC_HOST}",
    "Port": ${GAME_PORT},
    "GameServerId": "dan_heng",
    "GameServerName": "DanhengServer",
    "GameServerDescription": "A re-implementation of StarRail server",
    "UsePacketEncryption": true
  },
  "Path": {
    "ResourcePath": "Resources",
    "ConfigPath": "Config",
    "DatabasePath": "Config/Database",
    "LogPath": "Logs",
    "PluginPath": "Plugins"
  },
  "Database": {
    "DatabaseType": "sqlite",
    "DatabaseName": "danheng.db",
    "MySqlHost": "127.0.0.1",
    "MySqlPort": 3306,
    "MySqlUser": "root",
    "MySqlPassword": "123456",
    "MySqlDatabase": "danheng"
  },
  "ServerOption": {
    "StartTrailblazerLevel": 1,
    "AutoUpgradeWorldLevel": true,
    "EnableMission": true,
    "EnableQuest": true,
    "AutoLightSection": true,
    "Language": "CHS",
    "FallbackLanguage": "EN",
    "DefaultPermissions": ["*"],
    "AutoCreateUser": true,
    "FarmingDropRate": 1,
    "UseCache": false
  },
  "MuipServer": {
    "AdminKey": ""
  }
}
EOF
    
    log_success "配置文件已生成: $config_path"
}

# ============================================
# 步骤 7: 创建用户和权限
# ============================================

setup_user() {
    log_step 7 "配置用户和权限..."
    
    # 创建 dh 用户
    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd -r -s /bin/bash -d "$INSTALL_DIR" "$SERVICE_USER"
        log_info "已创建用户: $SERVICE_USER"
    else
        log_info "用户 $SERVICE_USER 已存在"
    fi
    
    # 设置目录权限
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"
    
    # 设置可执行权限
    find "$INSTALL_DIR" -name "*.exe" -o -name "GameServer" | xargs chmod +x 2>/dev/null || true
    
    log_success "权限配置完成"
}

# ============================================
# 步骤 8: 配置防火墙
# ============================================

configure_firewall() {
    log_step 8 "配置防火墙..."
    
    if [ "$SKIP_FIREWALL" = true ]; then
        log_info "跳过防火墙配置"
        return 0
    fi
    
    # 检测防火墙类型并配置
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
        log_info "使用 iptables..."
        if iptables -A INPUT -p tcp --dport "$HTTP_PORT" -j ACCEPT && \
           iptables -A INPUT -p udp --dport "$GAME_PORT" -j ACCEPT; then
            log_success "iptables 规则已添加"
        else
            log_warning "iptables 规则添加失败 (可能是环境限制)"
        fi
        
    else
        log_warning "未检测到防火墙，跳过配置"
    fi
}

# ============================================
# 步骤 9: 启动服务
# ============================================

start_server() {
    log_step 9 "启动服务..."
    
    cd "$INSTALL_DIR"
    
    # 查找可执行文件
    local server_exe
    if [ -f "GameServer" ]; then
        server_exe="./GameServer"
    elif [ -f "GameServer.exe" ]; then
        server_exe="dotnet GameServer.exe"
    else
        log_error "未找到服务器可执行文件"
        exit 1
    fi
    
    # 使用 screen 启动
    log_info "使用 screen 启动服务..."
    
    su - "$SERVICE_USER" -c "cd $INSTALL_DIR && screen -dmS danheng $server_exe"
    
    sleep 2
    
    # 检查是否启动成功
    if screen -list | grep -q "danheng"; then
        log_success "服务已启动"
        log_info "使用 'screen -r danheng' 查看控制台"
        log_info "使用 Ctrl+A+D 分离控制台"
    else
        log_error "服务启动失败"
        exit 1
    fi
}

# ============================================
# 主流程
# ============================================

TOTAL_STEPS=9

main() {
    echo ""
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}  NDHSM Linux Debian 12 自动部署脚本${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""
    
    # 解析参数
    parse_args "$@"
    
    # 检查 root 权限
    check_root
    
    # 执行部署步骤
    setup_ustc_source
    install_dependencies
    install_dotnet
    download_server
    clone_resources
    configure_server
    setup_user
    configure_firewall
    start_server
    
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
