# ============================================
# NDHSM Linux DeployOnDebian13 全自动部署脚本
# 相关文件:
#   - ./ChangeSource.sh (独立换源脚本)
#   - ./DHS.sh (启动脚本模板)
#   - ../TermuxToDebian13/setup_debian.sh (Termux 环境初始化)
#   - ../../Readme.md (项目主说明文档)
# ============================================
#
# 功能说明:
# 1. 一键换源 (交互式选择或无头模式跳过)
# 2. 自动安装系统依赖
# 3. 从 GitHub 下载自包含版本服务器
# 4. 下载资源文件
# 5. 创建 DHS 快捷启动指令 (基于 screen 管理)
#
# 使用方法:
#   交互模式: bash deploy.sh
#   无头模式: bash deploy.sh --headless
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
GITHUB_CONFIG_RELEASES="https://api.github.com/repos/GamblerIX/DanHengServerConfig/releases/latest"

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
        log_error "此脚本需要 root 权限运行"
        log_info "请使用: sudo bash deploy.sh [选项]"
        exit 1
    fi
    IS_ROOT=true
    log_info "当前以 root 身份运行"
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
            log_error "不支持的架构: $arch "
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
                shift
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
NDHSM Linux DeployOnDebian13 全自动部署脚本

用法: bash deploy.sh [选项]

选项:
  --headless, -H      无头模式，跳过交互（默认不换源）
  --http-port PORT    HTTP/MUIP 端口（默认: $DEFAULT_HTTP_PORT）
  --host HOST         公网地址（默认: $DEFAULT_HOST）
  --termux            Termux 优化（无头模式 + GC 限制 128MB）
  --help, -h          显示帮助信息

示例:
  # 交互模式（会询问是否换源）
  bash deploy.sh

  # 无头模式（跳过换源）
  bash deploy.sh --headless

  # Termux 无头模式
  bash deploy.sh --termux
EOF
}


# ============================================
# 步骤 1: 换源
# ============================================

change_apt_source() {
    log_step 1 "配置 APT 源..."
    
    if [ "$HEADLESS" = true ]; then
        log_info "无头模式，跳过换源"
        return 0
    fi

    # 询问是否换源
    echo ""
    echo -e "${CYAN}是否运行换源脚本？${NC}"
    echo "  1) 是 (运行 ChangeSource.sh)"
    echo "  2) 否 (跳过)"
    echo ""
    read -p "请输入选项 [1/2] (默认: 1): " choice
    choice=${choice:-1}
    
    if [ "$choice" != "1" ]; then
        log_info "已跳过换源"
        return 0
    fi
    
    local remote_script_url="https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/DeployOnDebian13/ChangeSource.sh"
    local tmp_script="/tmp/ChangeSource.sh"

    log_info "正在下载换源脚本..."
    if curl -sSL -o "$tmp_script" "$remote_script_url"; then
        chmod +x "$tmp_script"
        log_info "运行下载的 ChangeSource.sh..."
        bash "$tmp_script" || {
             log_warning "换源脚本运行异常"
        }
        rm -f "$tmp_script"
    else
        log_warning "下载换源脚本失败，跳过换源步骤。"
    fi
}

# ============================================
# 步骤 2: 安装依赖
# ============================================

install_dependencies() {
    log_step 2 "检查并安装依赖..."
    
    # 定义所有必需的软件包
    local deps=("curl" "screen" "wget" "git" "unzip" "p7zip-full" "jq" "ca-certificates" "apt-transport-https" "libicu-dev")
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

    # 如果跳过换源，先更新索引
    if [ "$NO_MIRROR" = true ]; then
        log_info "正在更新软件包索引...（）"
        apt-get update -qq || log_warning "apt-get update 遇到警告"
    fi

    # 执行安装
    log_info "待安装依赖: ${missing[*]}"
    if ! apt-get install -y "${missing[@]}"; then
        log_error "依赖安装失败，请检查网络连接或软件源配置"
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

# 通用下载解压函数
# 参数: $1=API地址 $2=资源名称 $3=目标目录 $4=检测标记(可选,用于智能定位)
download_and_extract() {
    local api_url="$1" name="$2" target_dir="$3" marker="$4"
    local tmp_dir="/tmp/dh_${name}_tmp"
    
    # 获取下载地址
    log_info "正在获取 $name 下载地址..."
    local release_info download_url
    release_info=$(curl -sSL --connect-timeout 5 --retry 3 "$api_url" 2>/dev/null) || {
        log_error "无法连接到 GitHub API ($name)"; exit 1
    }
    
    # 优先查找 asset，回退到 zipball
    download_url=$(echo "$release_info" | jq -r ".assets[] | select(.name | test(\"${name}.*\\\\.zip\"; \"i\")) | .browser_download_url" 2>/dev/null | head -1)
    [ -z "$download_url" ] || [ "$download_url" = "null" ] && {
        log_warning "未找到 ${name}*.zip Asset，使用 zipball..."
        download_url=$(echo "$release_info" | jq -r '.zipball_url' 2>/dev/null)
    }
    [ -z "$download_url" ] || [ "$download_url" = "null" ] && { log_error "无法获取 $name 下载地址"; exit 1; }
    
    # 下载并解压
    local filename="${name}.zip"
    log_info "正在下载 $name..."
    wget -q --show-progress -O "$filename" "$download_url" || { log_error "$name 下载失败"; rm -f "$filename"; exit 1; }
    
    rm -rf "$tmp_dir" && mkdir -p "$tmp_dir"
    log_info "正在解压 $name..."
    unzip -o -q "$filename" -d "$tmp_dir" || { log_error "$name 解压失败"; rm -f "$filename"; exit 1; }
    rm -f "$filename"
    
    # 智能定位根目录 (如果指定了标记目录)
    local src_dir="$tmp_dir"
    if [ -n "$marker" ]; then
        if [ ! -d "$tmp_dir/$marker" ]; then
            local found=$(find "$tmp_dir" -mindepth 2 -maxdepth 2 -type d -name "$marker" | head -1)
            [ -n "$found" ] && src_dir=$(dirname "$found")
        fi
        [ ! -d "$src_dir/$marker" ] && { log_error "$name 目录结构识别失败"; rm -rf "$tmp_dir"; exit 1; }
    else
        # 无标记时：若只有一个子目录则进入
        [ "$(ls -A "$tmp_dir" | wc -l)" -eq 1 ] && [ -d "$tmp_dir/$(ls -A "$tmp_dir")" ] && src_dir="$tmp_dir/$(ls -A "$tmp_dir")"
    fi
    
    # 部署文件
    mkdir -p "$target_dir"
    log_info "正在部署 $name 到 $target_dir..."
    cp -r "$src_dir"/* "$target_dir/"
    rm -rf "$tmp_dir"
}

download_resources() {
    log_step 4 "下载资源文件 (Resources & Config)..."
    
    local resources_dir="$INSTALL_DIR/resources"
    local config_dir="$INSTALL_DIR/config"
    
    # 下载 Resources (检测 ExcelOutput 目录)
    if [ -d "$resources_dir/ExcelOutput" ]; then
        log_info "Resources 已存在，跳过下载"
    else
        download_and_extract "$GITHUB_RESOURCES_RELEASES" "resources" "$resources_dir" "ExcelOutput"
    fi
    
    # 下载 Config
    if [ -d "$config_dir" ] && [ "$(ls -A "$config_dir" 2>/dev/null)" ]; then
        log_info "Config 已存在，跳过下载"
    else
        download_and_extract "$GITHUB_CONFIG_RELEASES" "config" "$config_dir" ""
    fi
    
    log_success "资源文件 (Resources & Config) 部署完成"
}


# ============================================
# 步骤 5: 创建快捷指令
# ============================================

create_shortcut() {
    log_step 5 "创建快捷指令 DHS..."
    
    local shortcut_path="/usr/local/bin/DHS"
    local script_path="$INSTALL_DIR/dhs_runner.sh"
    local remote_dhs_url="https://raw.githubusercontent.com/GamblerIX/DanHeng/main/NDHSM/Linux/DeployOnDebian13/DHS.sh"
    
    log_info "正在下载 DHS.sh 启动脚本..."
    if ! curl -sSL --connect-timeout 10 --retry 3 -o "$script_path" "$remote_dhs_url"; then
        log_error "DHS.sh 下载失败"
        exit 1
    fi
    
    # 替换占位符
    sed -i "s|__PROJECT_DIR__|$INSTALL_DIR|g" "$script_path"
    sed -i "s|__TERMUX_MODE__|$TERMUX_MODE|g" "$script_path"
    
    chmod +x "$script_path"
    
    # 创建软链接
    rm -f "$shortcut_path"
    ln -s "$script_path" "$shortcut_path"
    log_success "快捷指令已创建: DHS"
    log_info "启动服务: DHS"
    log_info "停止服务: DHS --stop"
    log_info "查看输出: screen -r DanHengServer"
}

# ============================================
# 主流程
# ============================================

TOTAL_STEPS=5

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
    
    # 检查 root 权限
    check_root
    
    # 解析参数
    parse_args "$@"
    
    # 执行部署步骤
    change_apt_source
    install_dependencies
    download_server
    download_resources
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
