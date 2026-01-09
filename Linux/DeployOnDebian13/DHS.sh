#!/bin/bash
# ============================================
# DHS - DanHeng Server 启动/停止脚本
# 相关文件:
#   - __PROJECT_DIR__/Config.json (服务器配置)
#   - __PROJECT_DIR__/DanhengServer (可执行文件)
# ============================================

# 配置变量（由 deploy.sh 替换占位符）
PROJECT_DIR="__PROJECT_DIR__"
SCREEN_NAME="DanHengServer"
BIN_NAME="DanhengServer"
TERMUX_MODE="__TERMUX_MODE__"

# ============================================
# 前置检查
# ============================================

# 修复管道执行时的 TTY 问题
if [ ! -t 0 ] && [ -e /dev/tty ]; then
    exec < /dev/tty
fi

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "❌ 此脚本需要 root 权限运行"
        echo "👉 请使用: sudo DHS [--stop]"
        exit 1
    fi
}

# 检查可执行文件
check_executable() {
    local bin_path="$PROJECT_DIR/$BIN_NAME"
    if [ ! -f "$bin_path" ]; then
        echo "❌ 可执行文件不存在: $bin_path"
        exit 1
    fi
    if [ ! -x "$bin_path" ]; then
        echo "⚠️  可执行文件无执行权限，正在修复..."
        chmod +x "$bin_path"
    fi
}

# ============================================
# 停止功能
# ============================================
stop_server() {
    # 检测：如果 screen 没有运行 且 进程也没在运行
    if ! screen -list | grep -q "$SCREEN_NAME" && ! pgrep -f "$BIN_NAME" > /dev/null; then
        echo "⚠️  未检测到运行中的 $SCREEN_NAME，已跳过停止操作。"
        return
    fi

    echo "🛑 正在停止 $SCREEN_NAME 服务..."
    
    # 查找并杀掉 screen 会话
    screen -ls | grep "$SCREEN_NAME" | cut -d. -f1 | awk '{print $1}' | xargs -r kill -9
    
    # 双重保险：直接杀掉二进制程序进程
    pkill -9 -f "$BIN_NAME"

    # 清理死掉的 screen socket
    screen -wipe > /dev/null 2>&1

    echo "✅ 所有 $SCREEN_NAME 相关进程已停止。"
}

# ============================================
# 启动功能
# ============================================
start_server() {
    # 检查可执行文件
    check_executable
    
    # 检查是否已经运行
    if screen -list | grep -q "$SCREEN_NAME"; then
        echo "⚠️  警告：$SCREEN_NAME 已经在运行中！"
        echo "👉 请输入 'screen -r $SCREEN_NAME' 查看，或先执行 'DHS --stop' 停止。"
        exit 1
    fi

    # 强制设置 UTF-8 编码
    export LC_ALL=en_US.UTF-8
    export LANG=en_US.UTF-8
    export LC_CTYPE=en_US.UTF-8

    # 检查并进入目录
    if [ ! -d "$PROJECT_DIR" ]; then
        echo "❌ 错误：目录 $PROJECT_DIR 不存在！"
        exit 1
    fi
    cd "$PROJECT_DIR" || exit 1

    # GC 限制计算
    if [ "$TERMUX_MODE" = "true" ]; then
        # Termux 模式：固定 128MB 堆限制
        limit_bytes=$((128 * 1048576))
        export DOTNET_GCHeapHardLimit=$limit_bytes
        export DOTNET_GC_HEAP_LIMIT=$limit_bytes
        echo "📱 Termux 模式: GC 堆限制 128MB"
    else
        # 自动计算 GC（取 50% 可用内存，限制在 128MB-4GB）
        available_mem_kb=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}')
        if [ -z "$available_mem_kb" ]; then
            available_mem_kb=$(free | awk '/^Mem:/{print $7}')
        fi
        calc_limit=$((available_mem_kb * 1024 / 2))
        [ "$calc_limit" -lt 134217728 ] && calc_limit=134217728
        [ "$calc_limit" -gt 4294967296 ] && calc_limit=4294967296
        export DOTNET_GCHeapHardLimit=$calc_limit
        export DOTNET_GC_HEAP_LIMIT=$calc_limit
    fi

    export DOTNET_EnableDiagnostics=0
    export DOTNET_gcServer=0
    export DOTNET_TieredCompilation=0
    export DOTNET_GCConcurrent=1

    # 启动 screen
    screen -dmS "$SCREEN_NAME" bash -c "./$BIN_NAME"

    # 输出信息
    echo "✅ $SCREEN_NAME 已启动"
    echo "📂 运行目录：$PROJECT_DIR"
    echo "🔌 查看输出：screen -r $SCREEN_NAME"
    echo "🛑 停止服务：DHS --stop"
}

# ============================================
# 删除安装功能
# ============================================
delete_installation() {
    echo ""
    echo "🗑️  ============================================"
    echo "🗑️    彻底删除模式"
    echo "🗑️  ============================================"
    echo ""
    
    if [ ! -d "$PROJECT_DIR" ]; then
        echo "⚠️  安装目录不存在: $PROJECT_DIR"
        exit 0
    fi
    
    # 请求确认
    echo "⚠️  警告: 此操作将删除以下内容:"
    echo "    - 目录: $PROJECT_DIR"
    echo "    - 所有配置文件、日志、数据库"
    echo ""
    read -p "确认删除？输入 'yes' 继续: " confirm
    if [ "$confirm" != "yes" ]; then
        echo "❌ 操作已取消"
        exit 0
    fi
    
    # 先停止服务
    stop_server
    sleep 1
    
    # 删除目录
    echo "🗑️  正在删除安装目录..."
    rm -rf "$PROJECT_DIR"
    
    # 删除快捷指令
    rm -f /usr/local/bin/DHS 2>/dev/null || true
    
    echo "✅ 已彻底删除 $PROJECT_DIR"
    exit 0
}

# ============================================
# 语言设置功能
# ============================================
set_chs_language() {
    local config_file="$PROJECT_DIR/Config.json"
    
    if [ ! -f "$config_file" ]; then
        echo "❌ 错误：未找到 Config.json"
        echo "👉 请先运行一次服务端 (直接运行 DHS) 以生成配置文件，然后按 Ctrl+C 或运行 DHS --stop 终止后再试。"
        exit 1
    fi
    
    echo "🌐 正在将语言设置为 CHS (简体中文)..."
    if sed -i 's/"Language": "EN"/"Language": "CHS"/g' "$config_file"; then
        echo "✅ 语言已成功设置为 CHS"
    else
        echo "❌ 语言设置失败"
        exit 1
    fi
}

# ============================================
# 主逻辑
# ============================================

# 先检查 root 权限
check_root

case "$1" in
    --stop)
        stop_server
        ;;
    --delete)
        delete_installation
        ;;
    --help|-h)
        echo "DHS - DanHeng Server 管理脚本"
        echo ""
        echo "用法: DHS [选项]"
        echo ""
        echo "选项:"
        echo "  (无参数)    启动服务"
        echo "  --stop      停止服务"
        echo "  --chs       将 Language 设置为 CHS (简体中文)"
        echo "  --delete    彻底删除安装目录及全部数据"
        echo "  --help, -h  显示帮助信息"
        ;;
    --chs|--CHS)
        set_chs_language
        ;;
    *)
        start_server
        ;;
esac
