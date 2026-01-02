# ============================================
# NDHSM Linux DeployOnDebian13 全自动部署脚本
# 相关文件:
#   - ../TermuxToDebian13/setup_debian.sh (Termux 环境初始化)
#   - ../../Readme.md (项目主说明文档)
# ============================================
#
# 功能说明:
# 1. 自动安装系统依赖
# 2. 从 GitHub 下载自包含版本服务器 (支持代理)
# 3. 克隆资源文件 (支持代理)
# 4. 配置防火墙 (可选，需 root)
# 5. 后台运行并自动生成/配置 Config.json
#
# 使用方法:
#   交互模式: bash deploy.sh
#   无头模式: bash deploy.sh --termux --headless --http-port 23300
#
# ============================================

set -e

# ============================================
# 配置变量（便于修改）
# ============================================

# 默认配置
DEFAULT_HTTP_PORT=23300
DEFAULT_HOST="0.0.0.0"
INSTALL_DIR="/opt/danheng"

# 仓库地址
GITHUB_SERVER_RELEASES="https://api.github.com/repos/GamblerIX/DanHengServer/releases/latest"
GITHUB_RESOURCES_REPO="https://github.com/GamblerIX/DanHengServerResources.git"

# GitHub 加速代理
GITHUB_PROXIES=(
    "https://ghps.cc/"
    "https://gh-proxy.org/"
    "https://gh.xmly.dev/"
    "http://gh.halonice.com/"
    "https://proxy.gitwarp.com/"
    "https://gh.zwnes.xyz/"
)
ENABLE_GH_PROXY=false
SELECTED_PROXY=""

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
        IS_ROOT=false
        log_info "当前以普通用户身份运行"
    else
        IS_ROOT=true
        log_info "当前以 root 身份运行"
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
        *)
            log_error "不支持的架构: $arch (目前仅支持 x64 和 arm64)"
            exit 1
            ;;
    esac
}

# 选择带宽吞吐量最高的 Github 代理
select_github_proxy() {
    if [ "$ENABLE_GH_PROXY" = false ]; then
        return 0
    fi
    
    log_info "正在对可用加速代理进行带宽竞速测试..."
    local max_speed=0
    local best_proxy=""
    
    for proxy in "${GITHUB_PROXIES[@]}"; do
        # 测速：尝试拉取代理主页或小文件，记录下载速度 (bytes/sec)
        # --max-time 3 防止单个节点卡死下载过程
        # 使用 cut 处理浮点数取整数部分，方便在 shell 中进行比较
        local speed=$(curl -sL --connect-timeout 3 --max-time 4 -o /dev/null -w "%{speed_download}" "$proxy" 2>/dev/null | cut -d'.' -f1 || echo 0)
        
        local speed_kb=$((speed / 1024))
        log_info "-> 节点: $proxy | 估算带宽: ${speed_kb} KB/s" >&2

        if [ "$speed" -gt "$max_speed" ]; then
            max_speed=$speed
            best_proxy=$proxy
        fi
    done

    if [ -n "$best_proxy" ] && [ "$max_speed" -gt 0 ]; then
        SELECTED_PROXY="$best_proxy"
        local final_speed_kb=$((max_speed / 1024))
        log_success "竞速完成！已选择最优带宽代理: $SELECTED_PROXY (峰值约 ${final_speed_kb} KB/s)"
    elif [ "$TERMUX_MODE" = true ]; then
        # Termux 下如果全挂了，往往是本地 DNS 或出口受限，强制选第一个作为尝试
        SELECTED_PROXY="${GITHUB_PROXIES[0]}"
        log_warning "所有代理测速响应异常，但在 Termux 模式下将强制尝试首选代理: $SELECTED_PROXY"
    else
        log_warning "未能检测到有效带宽的代理，将尝试直连模式"
    fi
}

# ============================================
# 参数解析
# ============================================

HEADLESS=false
HTTP_PORT=$DEFAULT_HTTP_PORT
PUBLIC_HOST=$DEFAULT_HOST
SKIP_FIREWALL=true  # 默认跳过
TERMUX_MODE=false
GC_LIMIT=""  # 空表示自动检测
DELETE_MODE=false  # 彻底删除模式
USE_MYSQL=false    # 使用 MySQL 数据库

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --headless|-H)
                HEADLESS=true
                shift
                ;;
            --http-port)
                HTTP_PORT="$2"
                shift 2
                ;;
            --host)
                PUBLIC_HOST="$2"
                shift 2
                ;;
            --open-firewall)
                SKIP_FIREWALL=false
                shift
                ;;
            --termux)
                TERMUX_MODE=true
                HEADLESS=true  # Termux 模式强制无头
                ENABLE_GH_PROXY=true  # Termux 模式自动开启加速
                # Termux 模式下，如果不指定 GC 限制，则默认为 128
                [ -z "$GC_LIMIT" ] && GC_LIMIT=128
                shift
                ;;
            --gc-limit)
                GC_LIMIT="$2"
                shift 2
                ;;
            --gh-proxy)
                ENABLE_GH_PROXY=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            --delete)
                DELETE_MODE=true
                shift
                ;;
            --mysql)
                USE_MYSQL=true
                shift
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
NDHSM Linux DeployOnDebian13 全自动部署脚本

用法: bash deploy.sh [选项]

选项:
  --headless, -H      无头模式，跳过交互
  --http-port PORT    HTTP/MUIP 端口（默认: $DEFAULT_HTTP_PORT）
  --host HOST         公网地址（默认: $DEFAULT_HOST）
  --open-firewall     尝试配置防火墙（默认跳过，需要 root 权限）
  --termux            Termux 优化（无头模式 + GC 限制 128MB）
  --gc-limit MB       手动设置 GC 内存限制 (单位 MB，默认自动检测)
  --gh-proxy          开启 GitHub 下载加速（自动从预设中选择）
  --delete            彻底删除安装目录及全部数据
  --mysql             将数据库类型替换为 MySQL
  --help, -h          显示帮助信息

示例:
  # 交互模式
  bash deploy.sh

  # 无头模式 (Termux)
  bash deploy.sh --termux --headless --http-port 23300
EOF
}

# ============================================
# 删除安装功能
# ============================================

delete_installation() {
    echo ""
    echo -e "${RED}============================================${NC}"
    echo -e "${RED}  彻底删除模式${NC}"
    echo -e "${RED}============================================${NC}"
    echo ""
    
    if [ ! -d "$INSTALL_DIR" ]; then
        log_info "安装目录不存在: $INSTALL_DIR"
        exit 0
    fi
    
    # 非无头模式下请求确认
    if [ "$HEADLESS" = false ]; then
        echo -e "${YELLOW}警告: 此操作将删除以下内容:${NC}"
        echo -e "  - 目录: $INSTALL_DIR"
        echo -e "  - 所有配置文件、日志、数据库"
        echo ""
        read -p "确认删除？输入 'yes' 继续: " confirm
        if [ "$confirm" != "yes" ]; then
            log_info "操作已取消"
            exit 0
        fi
    fi
    
    # 停止服务
    log_info "正在停止服务..."
    pkill -f "$INSTALL_DIR/DanhengServer" 2>/dev/null || true
    pkill -f "$INSTALL_DIR/GameServer" 2>/dev/null || true
    sleep 2
    
    # 删除目录
    log_info "正在删除安装目录..."
    rm -rf "$INSTALL_DIR"
    
    log_success "已彻底删除 $INSTALL_DIR"
    exit 0
}

# ============================================
# 步骤 1: 安装依赖
# ============================================

install_dependencies() {
    log_step 1 "检查并安装依赖..."
    
    # 定义所有必需的软件包
    local deps=("curl" "wget" "git" "unzip" "p7zip-full" "jq" "ca-certificates" "apt-transport-https" "libicu-dev")
    local missing=()

    # 统一通过 dpkg 检查包是否安装
    for dep in "${deps[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$dep" 2>/dev/null | grep -q "ok installed"; then
            missing+=("$dep")
        fi
    done

    # 如果没有缺失项，直接返回
    if [ ${#missing[@]} -eq 0 ]; then
        log_success "所有核心依赖已就绪，跳过安装步骤"
        return 0
    fi

    # 执行安装
    log_info "待安装依赖: ${missing[*]}"
    apt-get update -qq && apt-get install -y -qq "${missing[@]}"
    
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
        
        local final_api_url="$api_url"
        if [ -n "$SELECTED_PROXY" ]; then
            final_api_url="${SELECTED_PROXY}${api_url}"
            log_info "使用加速代理访问 API..." >&2
        fi

        local release_info
        if ! release_info=$(curl -sSL --connect-timeout 10 "$final_api_url" 2>/dev/null); then
            log_warning "无法通过当前连接获取 $source_name API 信息" >&2
            
            # 如果刚才用了代理，尝试回退到直连作为保底
            if [ -n "$SELECTED_PROXY" ]; then
                log_info "尝试直连访问 API..." >&2
                if ! release_info=$(curl -sSL --connect-timeout 10 "$api_url" 2>/dev/null); then
                    return 1
                fi
            else
                return 1
            fi
        fi

        if [ -z "$release_info" ] || [ "$release_info" == "null" ]; then
             log_warning "$source_name API 返回数据无效" >&2
             return 1
        fi
        
        # 尝试匹配架构 (仅下载 self-contained 版本)
        local url
        url=$(echo "$release_info" | jq -r ".assets[] | select(.name | contains(\"$arch\") and contains(\"self-contained\")) | .browser_download_url" 2>/dev/null | head -1)
        
        echo "$url"
    }

    # 从 GitHub 获取下载链接
    download_url=$(get_download_url "$GITHUB_SERVER_RELEASES" "GitHub")
    
    # 检查是否成功
    if [ -z "$download_url" ] || [ "$download_url" == "null" ]; then
        log_error "未找到适用的下载包，这通常是由于网络无法连接到 GitHub API 导致的。"
        log_error "请检查您的网络连接，或尝试多次运行脚本。"
        exit 1
    fi
    
    log_info "下载地址: $download_url"
    
    # 下载
    filename=$(basename "$download_url")
    local final_url="$download_url"
    if [ -n "$SELECTED_PROXY" ]; then
        final_url="${SELECTED_PROXY}${download_url}"
        log_info "使用加速地址下载..."
    fi

    if wget --show-progress -O "$filename" "$final_url"; then
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
    elif [[ $filename == *.7z ]]; then
        if ! 7z x -y "$filename" > /dev/null; then
            log_error "解压失败 (7z)"
            exit 1
        fi
    else
        log_error "不支持的压缩格式: $filename，这不是您的问题，请在Github上提交Issue"
        exit 1
    fi
    
    # 保留压缩包，待服务成功启动后删除
    
    # 将子目录内容移至安装目录根目录
    for subdir in "$INSTALL_DIR"/*-self-contained "$INSTALL_DIR"/*-self-contained/; do
        if [ -d "$subdir" ]; then
            log_info "正在整理文件结构...（该步骤可能需要较长时间）"
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
    log_step 3 "克隆资源文件...）"
    
    local resources_dir="$INSTALL_DIR/Resources"
    
    if [ -d "$resources_dir" ]; then
        log_info "Resources 目录已存在，跳过克隆"
        return 0
    fi
    
    local repo_url="$GITHUB_RESOURCES_REPO"
    local final_repo="$repo_url"
    if [ -n "$SELECTED_PROXY" ]; then
        final_repo="${SELECTED_PROXY}${repo_url}"
    fi
    
    log_info "正在克隆资源仓库...（该步骤可能需要较长时间）"
    git clone --depth 1 "$final_repo" "$resources_dir"
    
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
    mkdir -p "$INSTALL_DIR/Config"
    local wait_count=0
    while [ ! -f "$config_path" ] && [ $wait_count -lt 30 ]; do
        sleep 1
        wait_count=$((wait_count + 1))
    done
    
    if [ ! -f "$config_path" ]; then
        log_error "Config.json 未能由服务端自动生成，部署无法继续"
        exit 1
    fi
    
    # 停止服务
    log_info "停止服务以修改配置..."
    pkill -f "$INSTALL_DIR/DanhengServer" || pkill -f "$INSTALL_DIR/GameServer" || true
    sleep 2
    
    # 交互模式下询问用户
    if [ "$HEADLESS" = false ]; then
        echo ""
        log_info "请配置服务器参数（直接回车使用默认值）:"
        echo ""
        
        read -p "HTTP/MUIP 端口 [${HTTP_PORT}]: " input
        HTTP_PORT=${input:-$HTTP_PORT}
        
        read -p "公网地址 [${PUBLIC_HOST}]: " input
        PUBLIC_HOST=${input:-$PUBLIC_HOST}
        
        echo ""
    fi
    
    # 使用 jq 修改配置文件
    if command -v jq &>/dev/null; then
        local tmp_config=$(mktemp)
        jq --arg http_port "$HTTP_PORT" \
           --arg public_host "$PUBLIC_HOST" \
           '.HttpServer.Port = ($http_port | tonumber) |
            .HttpServer.PublicAddress = $public_host' \
           "$config_path" > "$tmp_config" && mv "$tmp_config" "$config_path"
        log_success "配置文件已更新: $config_path"
        
        # MySQL 配置替换
        if [ "$USE_MYSQL" = true ]; then
            log_info "应用 MySQL 数据库配置..."
            local tmp_mysql=$(mktemp)
            jq '.Database.DatabaseType = "mysql"' "$config_path" > "$tmp_mysql" && mv "$tmp_mysql" "$config_path"
            log_success "数据库类型已切换为 MySQL"
        fi
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
        log_error "未找到服务端可执行文件"
        exit 1
    fi
    
    chmod +x "$server_exe"
    
    nohup "$server_exe" > "$INSTALL_DIR/server.log" 2>&1 &
    local server_pid=$!
    sleep 3
    
    if kill -0 "$server_pid" 2>/dev/null; then
        log_success "服务已重新启动 (PID: $server_pid)"
        rm -f "$INSTALL_DIR"/*.zip "$INSTALL_DIR"/*.tar.gz 2>/dev/null || true
    else
        log_error "服务重启失败，请检查日志: $INSTALL_DIR/server.log"
        exit 1
    fi
}

# ============================================
# 步骤 5: 配置防火墙
# ============================================

configure_firewall() {
    if [ "$SKIP_FIREWALL" = true ]; then
        log_info "跳过防火墙配置"
        return 0
    fi
    
    if [ "$IS_ROOT" = false ]; then
        log_warning "缺少 root 权限，无法配置防火墙，已跳过"
        return 0
    fi

    log_step 5 "配置防火墙..."
    
    # 检测防火墙类型并配置
    if command -v ufw &> /dev/null; then
        log_info "检测到 UFW..."
        if ufw allow "$HTTP_PORT"/tcp; then
            log_success "UFW 规则已添加"
        else
            log_warning "UFW 规则添加失败"
        fi
        
    elif command -v firewall-cmd &> /dev/null; then
        log_info "检测到 firewalld..."
        if firewall-cmd --permanent --add-port="$HTTP_PORT"/tcp; then
            firewall-cmd --reload || true
            log_success "firewalld 规则已添加"
        else
            log_warning "firewalld 规则添加失败"
        fi
        
    elif command -v iptables &> /dev/null; then
        log_info "检测到 iptables..."
        if iptables -I INPUT -p tcp --dport "$HTTP_PORT" -j ACCEPT; then
            log_success "iptables 规则已添加（注意：重启后可能失效，建议安装 iptables-persistent 永久保存）"
        else
            log_warning "iptables 规则添加失败"
        fi
        
    else
        log_info "未检测到常见防火墙或配置失败，建议手动开放端口: $HTTP_PORT"
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
    
    # 计算 GC 堆限制
    local gc_limit
    if [ -n "$GC_LIMIT" ]; then
        # 用户手动指定 (单位 MB，转换为字节)
        gc_limit=$((GC_LIMIT * 1048576))
        log_info "GC 限制 (手动): ${GC_LIMIT}MB"
    else
        # 自动检测 (可用内存的 50%，最小 128MB，最大 2GB)
        local available_mem_kb=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}')
        if [ -z "$available_mem_kb" ]; then
            available_mem_kb=$(free | awk '/^Mem:/{print $7}')
        fi
        gc_limit=$((available_mem_kb * 1024 / 2))
        [ "$gc_limit" -lt 134217728 ] && gc_limit=134217728    # 最小 128MB
        [ "$gc_limit" -gt 2147483648 ] && gc_limit=2147483648  # 最大 2GB
        log_info "可用内存: $((available_mem_kb / 1024))MB, GC 限制: $((gc_limit / 1048576))MB"
    fi
    
    export DOTNET_GCHeapHardLimit=$gc_limit
    export DOTNET_GC_HEAP_LIMIT=$gc_limit
    export DOTNET_EnableDiagnostics=0
    export DOTNET_gcServer=0
    export DOTNET_TieredCompilation=0
    export DOTNET_GCConcurrent=1

    
    # 使用 nohup 启动
    log_info "使用 nohup 后台启动服务..."
    nohup "$server_exe" > "$INSTALL_DIR/server.log" 2>&1 &
    local server_pid=$!
    sleep 3
    
    if kill -0 "$server_pid" 2>/dev/null; then
        log_success "服务已启动 (PID: $server_pid)"
        log_info "日志文件: $INSTALL_DIR/server.log"
    else
        log_error "服务启动失败，请检查日志: $INSTALL_DIR/server.log"
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
    echo -e "${CYAN}  NDHSM Linux DeployOnDebian13 自动部署脚本${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""
    
    # 解析参数
    parse_args "$@"
    
    # 删除模式检测
    if [ "$DELETE_MODE" = true ]; then
        delete_installation
    fi
    
    # 选项：Github 加速
    select_github_proxy

    # 检查 root 权限 (用于防火墙等可选功能)
    check_root
    
    # 执行部署步骤
    install_dependencies
    download_server
    clone_resources
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
    echo -e "运行用户: ${CYAN}$(whoami)${NC}"
    echo ""
    echo -e "管理命令:"
    echo -e "  查看日志:   ${YELLOW}tail -f $INSTALL_DIR/server.log${NC}"
    echo -e "  停止服务:   ${YELLOW}pkill -f $INSTALL_DIR/DanhengServer${NC}"
    echo ""
}

# 运行主流程
main "$@"
