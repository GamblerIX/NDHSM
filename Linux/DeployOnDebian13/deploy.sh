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
GITHUB_RESOURCES_RELEASES="https://api.github.com/repos/GamblerIX/DanHengServerResources/releases/latest"

# GitHub 加速代理
GITHUB_PROXIES=(
    "https://gh-proxy.org/"
    "https://ghproxy.net/"
    "https://gh.xmly.dev/"
    "http://gh.halonice.com/"
    "https://proxy.gitwarp.com/"
    "https://gh.zwnes.xyz/"
)
ENABLE_GH_PROXY=false
SELECTED_PROXY=""
FORCED_PROXY="" # 强制指定的代理

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

# 获取架构
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
            --ghproxyset)
                FORCED_PROXY="$2"
                ENABLE_GH_PROXY=true
                shift 2
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
  --ghproxyset URL    强制指定加速代理地址 (例如 https://gh-proxy.org/ )
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
        
        # 构建代理尝试列表
        local try_list=()
        if [ -n "$FORCED_PROXY" ]; then
            try_list=("$FORCED_PROXY")
        elif [ "$ENABLE_GH_PROXY" = true ]; then
            try_list=("${GITHUB_PROXIES[@]}" "") # 代理列表 + 直连保底
        else
            try_list=("") # 仅直连
        fi
        
        log_info "将尝试 ${#try_list[@]} 个连接端点..." >&2

        for proxy in "${try_list[@]}"; do
            local final_api_url="${proxy}${api_url}"
            local prefix_info="直连"
            [ -n "$proxy" ] && prefix_info="代理 $proxy"
            
            log_info "正在尝试获取版本信息 ($prefix_info)..." >&2

            local release_info
            # 增加 -v 以便在极端情况下调试 (当前仅保留 -sSL)
            if release_info=$(curl -sSL --connect-timeout 10 --retry 2 "$final_api_url" 2>/dev/null); then
                # 简单验证 JSON合法性
                if [ -n "$release_info" ] && [ "$release_info" != "null" ] && echo "$release_info" | jq . >/dev/null 2>&1; then
                    # 尝试匹配架构
                    local url
                    url=$(echo "$release_info" | jq -r ".assets[] | select(.name | contains(\"$arch\") and contains(\"self-contained\")) | .browser_download_url" 2>/dev/null | head -1)
                    if [ -n "$url" ] && [ "$url" != "null" ]; then
                        echo "$url"
                        return 0
                    else
                        log_warning "API 请求成功但未能在 JSON 中找到对应架构 ($arch) 的资源" >&2
                    fi
                else
                    log_warning "API 返回内容无效或非 JSON 格式" >&2
                fi
            else
                 log_warning "连接失败 ($prefix_info)" >&2
            fi
            
            # 如果是强制代理模式且失败了，直接报错
            if [ -n "$FORCED_PROXY" ]; then
                log_error "强制指定的代理无法获取 API 信息，请检查代理地址或网络" >&2
                return 1
            fi
        done
        return 1
    }

    # 获取下载链接
    download_url=$(get_download_url "$GITHUB_SERVER_RELEASES" "GitHub")
    
    # 检查是否成功
    if [ -z "$download_url" ] || [ "$download_url" == "null" ]; then
        log_error "在所有尝试（含代理）后均未能获取有效的下载链接，请检查网络或稍后重试"
        exit 1
    fi
    
    log_info "解析到资产下载地址: $download_url"
    
    # 下载执行
    filename=$(basename "$download_url")
    local success=false
    
    # 构建代理尝试列表
    local try_list=()
    if [ -n "$FORCED_PROXY" ]; then
        try_list=("$FORCED_PROXY")
    elif [ "$ENABLE_GH_PROXY" = true ]; then
        try_list=("${GITHUB_PROXIES[@]}" "") 
    else
        try_list=("") 
    fi

    for proxy in "${try_list[@]}"; do
        local final_url="${proxy}${download_url}"
        local prefix_info="直连"
        [ -n "$proxy" ] && prefix_info="代理 $proxy"

        log_info "正在尝试下载文件 ($prefix_info)..."
        
        if wget --show-progress -O "$filename" "$final_url"; then
            success=true
            break
        fi

        if [ -n "$FORCED_PROXY" ]; then
            log_error "强制指定的代理下载失败"
            rm -f "$filename"
            exit 1
        fi
        log_warning "当前节点下载失败，尝试下一个..."
    done

    if [ "$success" = false ]; then
        log_error "所有下载方式均已失败"
        exit 1
    fi
    
    log_success "下载成功"
    
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
# 步骤 3: 下载资源文件 (ZIP)
# ============================================

download_resources() {
    log_step 3 "下载资源文件..."
    
    local resources_dir="$INSTALL_DIR/Resources"
    
    if [ -d "$resources_dir" ]; then
        log_info "Resources 目录已存在，跳过下载"
        return 0
    fi
    
    cd "$INSTALL_DIR"
    
    # 构建代理尝试列表
    local try_list=()
    if [ -n "$FORCED_PROXY" ]; then
        try_list=("$FORCED_PROXY")
    elif [ "$ENABLE_GH_PROXY" = true ]; then
        try_list=("${GITHUB_PROXIES[@]}" "")
    else
        try_list=("")
    fi
    
    # 获取资源 ZIP 下载地址
    local download_url=""
    log_info "正在获取资源文件下载地址..."
    
    for proxy in "${try_list[@]}"; do
        local final_api_url="${proxy}${GITHUB_RESOURCES_RELEASES}"
        local prefix_info="直连"
        [ -n "$proxy" ] && prefix_info="代理 $proxy"
        
        log_info "正在尝试获取资源版本信息 ($prefix_info)..."
        
        local release_info
        if release_info=$(curl -sSL --connect-timeout 10 --retry 2 "$final_api_url" 2>/dev/null); then
            if [ -n "$release_info" ] && [ "$release_info" != "null" ] && echo "$release_info" | jq . >/dev/null 2>&1; then
                # 查找 zipball 或 assets 中的 ZIP 文件
                download_url=$(echo "$release_info" | jq -r '.zipball_url // .assets[0].browser_download_url' 2>/dev/null)
                if [ -n "$download_url" ] && [ "$download_url" != "null" ]; then
                    break
                fi
            fi
        fi
        
        if [ -n "$FORCED_PROXY" ]; then
            log_error "强制指定的代理无法获取资源 API 信息"
            exit 1
        fi
    done
    
    if [ -z "$download_url" ] || [ "$download_url" == "null" ]; then
        log_error "无法获取资源文件下载地址"
        exit 1
    fi
    
    log_info "解析到资源下载地址: $download_url"
    
    # 下载 ZIP 文件
    local filename="resources.zip"
    local success=false
    
    for proxy in "${try_list[@]}"; do
        local final_url="${proxy}${download_url}"
        local prefix_info="直连"
        [ -n "$proxy" ] && prefix_info="代理 $proxy"
        
        log_info "正在尝试下载资源文件 ($prefix_info)..."
        
        if wget --show-progress -O "$filename" "$final_url"; then
            success=true
            break
        fi
        
        if [ -n "$FORCED_PROXY" ]; then
            log_error "强制指定的代理下载资源失败"
            rm -f "$filename"
            exit 1
        fi
        log_warning "当前节点下载失败，尝试下一个..."
    done
    
    if [ "$success" = false ]; then
        log_error "所有资源下载方式均已失败"
        rm -f "$filename"
        exit 1
    fi
    
    # 解压 ZIP 文件
    log_info "正在解压资源文件..."
    if ! unzip -o -q "$filename"; then
        log_error "资源文件解压失败"
        rm -f "$filename"
        exit 1
    fi
    
    # 整理目录结构 (GitHub zipball 会创建带版本号的子目录)
    for subdir in "$INSTALL_DIR"/GamblerIX-DanHengServerResources-* "$INSTALL_DIR"/DanHengServerResources-*; do
        if [ -d "$subdir" ]; then
            log_info "正在整理资源目录结构..."
            mv "$subdir" "$resources_dir" 2>/dev/null || true
            break
        fi
    done
    
    # 清理下载的 ZIP 文件
    rm -f "$filename"
    
    if [ ! -d "$resources_dir" ]; then
        log_error "资源目录未能正确创建"
        exit 1
    fi
    
    log_success "资源文件下载完成"
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
    
    # 检查 root 权限 (用于防火墙等可选功能)
    check_root
    
    # 执行部署步骤
    install_dependencies
    download_server
    download_resources
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
