# ============================================
# NDHSM Linux DeployOnDebian13 全自动部署脚本
# 相关文件:
#   - ../TermuxToDebian13/setup_debian.sh (Termux 环境初始化)
#   - ../../Readme.md (项目主说明文档)
# ============================================
#
# 功能说明:
# 1. 一键换源 (阿里云/官方)
# 2. 自动安装系统依赖
# 3. 从 GitHub 下载自包含版本服务器
# 4. 下载资源文件
# 5. 自动生成/配置 Config.json
# 6. 创建 DHS 快捷启动指令
#
# 使用方法:
#   交互模式: bash deploy.sh
#   无头模式: bash deploy.sh --headless --mirror1 --http-port 23300
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
TERMUX_MODE=false
GC_LIMIT=""  # 空表示自动检测
DELETE_MODE=false  # 彻底删除模式
USE_MYSQL=false    # 使用 MySQL 数据库
MIRROR_OPTION=""   # 换源选项: 1=阿里云, 2=官方

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
            --mirror1)
                MIRROR_OPTION="1"
                shift
                ;;
            --mirror2)
                MIRROR_OPTION="2"
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
  --termux            Termux 优化（无头模式 + GC 限制 128MB）
  --gc-limit MB       手动设置 GC 内存限制 (单位 MB，默认自动检测)
  --mirror1           切换 APT 源为阿里云镜像（国内推荐）
  --mirror2           切换 APT 源为官方源
  --delete            彻底删除安装目录及全部数据
  --mysql             将数据库类型替换为 MySQL
  --help, -h          显示帮助信息

示例:
  # 交互模式
  bash deploy.sh

  # 无头模式 + 阿里云源
  bash deploy.sh --headless --mirror1

  # Termux 无头模式
  bash deploy.sh --termux --mirror1
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
    
    # 删除快捷指令
    rm -f /usr/local/bin/DHS 2>/dev/null || true
    
    log_success "已彻底删除 $INSTALL_DIR"
    exit 0
}

# ============================================
# 步骤 1: 换源
# ============================================

change_apt_source() {
    if [ -z "$MIRROR_OPTION" ]; then
        return 0
    fi
    
    log_step 1 "配置 APT 源..."
    
    local sources_file="/etc/apt/sources.list"
    local sources_dir="/etc/apt/sources.list.d"
    local backup_file="/etc/apt/sources.list.bak"
    
    # 备份原文件
    [ ! -f "$backup_file" ] && cp "$sources_file" "$backup_file"
    
    # 清理可能冲突的源文件
    rm -f "$sources_dir"/*.sources 2>/dev/null || true
    
    if [ "$MIRROR_OPTION" = "1" ]; then
        log_info "切换到阿里云镜像源（使用 HTTP 以兼容无证书环境）..."
        cat > "$sources_file" << 'EOF'
deb http://mirrors.aliyun.com/debian/ bookworm main contrib non-free non-free-firmware
deb http://mirrors.aliyun.com/debian/ bookworm-updates main contrib non-free non-free-firmware
deb http://mirrors.aliyun.com/debian-security bookworm-security main contrib non-free non-free-firmware
EOF
        log_success "已切换到阿里云镜像源"
    elif [ "$MIRROR_OPTION" = "2" ]; then
        log_info "恢复官方源..."
        cat > "$sources_file" << 'EOF'
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF
        log_success "已恢复官方源"
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
}

# ============================================
# 步骤 2: 安装依赖
# ============================================

install_dependencies() {
    log_step 2 "检查并安装依赖..."
    
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

    # 如果未换源，先更新索引
    if [ -z "$MIRROR_OPTION" ]; then
        log_info "正在更新软件包索引..."
        apt-get update -qq || log_warning "apt-get update 遇到警告"
    fi

    # 执行安装
    log_info "待安装依赖: ${missing[*]}"
    if ! apt-get install -y "${missing[@]}"; then
        log_error "依赖安装失败，请检查网络连接或软件源配置"
        log_info "提示: 可尝试使用 --mirror1 或 --mirror2 参数切换软件源"
        exit 1
    fi
    
    log_success "依赖安装完成"
}

# ============================================
# 步骤 3: 下载服务器 (已存在则跳过)
# ============================================

download_server() {
    log_step 3 "下载 DanHengServer..."
    
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
    
    # 获取下载链接 (直连 GitHub API)
    log_info "正在获取版本信息..."
    local release_info
    if ! release_info=$(curl -sSL --connect-timeout 15 --retry 3 "$GITHUB_SERVER_RELEASES" 2>/dev/null); then
        log_error "无法连接到 GitHub API，请检查网络"
        exit 1
    fi
    
    # 验证 JSON 并提取下载链接
    if [ -z "$release_info" ] || [ "$release_info" = "null" ]; then
        log_error "API 返回为空"
        exit 1
    fi
    
    local download_url
    download_url=$(echo "$release_info" | jq -r ".assets[] | select(.name | contains(\"$arch\") and contains(\"self-contained\")) | .browser_download_url" 2>/dev/null | head -1)
    
    if [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
        log_error "未能找到对应架构 ($arch) 的下载资源"
        exit 1
    fi
    
    log_info "解析到下载地址: $download_url"
    
    # 下载
    local filename=$(basename "$download_url")
    log_info "正在下载文件..."
    if ! wget --show-progress -O "$filename" "$download_url"; then
        log_error "下载失败"
        rm -f "$filename"
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
        log_error "不支持的压缩格式: $filename"
        exit 1
    fi
    
    # 将子目录内容移至安装目录根目录
    for subdir in "$INSTALL_DIR"/*-self-contained "$INSTALL_DIR"/*-self-contained/; do
        if [ -d "$subdir" ]; then
            log_info "正在整理文件结构..."
            mv "$subdir"/* "$INSTALL_DIR/" 2>/dev/null || true
            rmdir "$subdir" 2>/dev/null || true
        fi
    done
    
    # 清理压缩包
    rm -f "$filename"
    
    log_success "服务器文件准备就绪"
}

# ============================================
# 步骤 4: 下载资源文件 (ZIP)
# ============================================

download_resources() {
    log_step 4 "下载资源文件..."
    
    local resources_dir="$INSTALL_DIR/Resources"
    
    if [ -d "$resources_dir" ]; then
        log_info "Resources 目录已存在，跳过下载"
        return 0
    fi
    
    cd "$INSTALL_DIR"
    
    # 获取资源 ZIP 下载地址
    log_info "正在获取资源文件下载地址..."
    local release_info
    if ! release_info=$(curl -sSL --connect-timeout 15 --retry 3 "$GITHUB_RESOURCES_RELEASES" 2>/dev/null); then
        log_error "无法连接到 GitHub API"
        exit 1
    fi
    
    local download_url
    download_url=$(echo "$release_info" | jq -r '.zipball_url // .assets[0].browser_download_url' 2>/dev/null)
    
    if [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
        log_error "无法获取资源文件下载地址"
        exit 1
    fi
    
    log_info "解析到资源下载地址: $download_url"
    
    # 下载 ZIP 文件
    local filename="resources.zip"
    log_info "正在下载资源文件..."
    if ! wget --show-progress -O "$filename" "$download_url"; then
        log_error "资源下载失败"
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
# 步骤 5: 配置 Config.json
# ============================================

configure_server() {
    log_step 5 "配置 Config.json..."
    
    local config_path="$INSTALL_DIR/Config.json"
    mkdir -p "$INSTALL_DIR/Config"

    # 如果文件不存在，手动创建一个包含基本端口配置的文件
    if [ ! -f "$config_path" ]; then
        log_info "Config.json 不存在，正在创建默认配置..."
        cat <<EOF > "$config_path"
{
  "HttpServer": {
    "BindAddress": "0.0.0.0",
    "PublicAddress": "$PUBLIC_HOST",
    "Port": $HTTP_PORT,
    "UseSSL": false,
    "UseFetchRemoteHotfix": false
  },
  "GameServer": {
    "BindAddress": "0.0.0.0",
    "PublicAddress": "127.0.0.1",
    "Port": 23301,
    "GameServerId": "dan_heng",
    "GameServerName": "DanhengServer",
    "GameServerDescription": "Private Server",
    "UsePacketEncryption": true
  },
  "Database": {
    "DatabaseType": "sqlite",
    "DatabaseName": "danheng.db"
  }
}
EOF
        log_success "默认配置文件已创建"
    else
        log_info "Config.json 已存在，准备修改..."
    fi
 
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
    
    log_success "配置已完成"
}

# ============================================
# 步骤 6: 创建快捷指令
# ============================================

create_shortcut() {
    log_step 6 "创建快捷指令 DHS..."
    
    local shortcut_path="/usr/local/bin/DHS"
    local script_content="#!/bin/bash
set -e

# 配置
INSTALL_DIR=\"$INSTALL_DIR\"
GC_LIMIT=\"$GC_LIMIT\"

# 自动计算 GC (如果未指定)
if [ -z \"\$GC_LIMIT\" ]; then
    available_mem_kb=\$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print \$2}')
    if [ -z \"\$available_mem_kb\" ]; then
        available_mem_kb=\$(free | awk '/^Mem:/{print \$7}')
    fi
    # 50% 内存
    calc_limit=\$((available_mem_kb * 1024 / 2))
    # 限制范围 [128MB, 4GB]
    [ \"\$calc_limit\" -lt 134217728 ] && calc_limit=134217728
    [ \"\$calc_limit\" -gt 4294967296 ] && calc_limit=4294967296
    
    export DOTNET_GCHeapHardLimit=\$calc_limit
    export DOTNET_GC_HEAP_LIMIT=\$calc_limit
else
    # 手动指定 (MB)
    limit_bytes=\$((GC_LIMIT * 1048576))
    export DOTNET_GCHeapHardLimit=\$limit_bytes
    export DOTNET_GC_HEAP_LIMIT=\$limit_bytes
fi

export DOTNET_EnableDiagnostics=0
export DOTNET_gcServer=0
export DOTNET_TieredCompilation=0
export DOTNET_GCConcurrent=1

cd \"\$INSTALL_DIR\"

echo \"正在启动 DanHengServer...\"
if [ -f \"DanhengServer\" ]; then
    ./DanhengServer
elif [ -f \"GameServer\" ]; then
    ./GameServer
else
    echo \"错误: 未找到可执行文件\"
    exit 1
fi
"

    # 写入文件
    echo "$script_content" > "$INSTALL_DIR/dhs_runner.sh"
    chmod +x "$INSTALL_DIR/dhs_runner.sh"
    
    # 创建软链接
    if [ "$IS_ROOT" = true ]; then
        rm -f "$shortcut_path"
        ln -s "$INSTALL_DIR/dhs_runner.sh" "$shortcut_path"
        log_success "快捷指令已创建: DHS (输入 'DHS' 即可启动服务)"
    else
        log_warning "非 root 用户无法创建 /usr/local/bin/DHS，请手动运行: $INSTALL_DIR/dhs_runner.sh"
        log_info "或者设置别名: alias DHS='$INSTALL_DIR/dhs_runner.sh'"
    fi
}

# ============================================
# 主流程
# ============================================

TOTAL_STEPS=6

main() {
    echo ""
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}  NDHSM Linux DeployOnDebian13 自动部署脚本${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""
    
    # 修复管道执行时的交互问题
    if [ ! -t 0 ] && [ -e /dev/tty ]; then
        exec < /dev/tty
    fi
    
    # 解析参数
    parse_args "$@"
    
    # 删除模式检测
    if [ "$DELETE_MODE" = true ]; then
        delete_installation
    fi
    
    # 检查 root 权限
    check_root
    
    # 执行部署步骤
    change_apt_source
    install_dependencies
    download_server
    download_resources
    configure_server
    create_shortcut
    
    # 清理临时文件
    rm -f "$INSTALL_DIR"/*.zip "$INSTALL_DIR"/*.tar.gz 2>/dev/null || true
    
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  部署完成！${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo -e "安装目录: ${CYAN}$INSTALL_DIR${NC}"
    echo -e "HTTP 端口: ${CYAN}$HTTP_PORT${NC}"
    echo -e "运行用户: ${CYAN}$(whoami)${NC}"
    echo ""
    echo -e "启动方式:"
    echo -e "  直接运行:   ${YELLOW}DHS${NC}"
    echo ""
}

# 运行主流程
main "$@"
