# ============================================
# NDHSM Windows 管理工具 - 主窗口界面
# 相关文件: main.py, config.py, muip_client.py,
#           auto_setup.py, proxy_manager.py
# ============================================
"""
基于 PySide6 和 Fluent Widgets 的主窗口
- 导航栏布局
- 首页：服务器状态、快捷操作
- 命令页：命令输入和执行
- 玩家页：玩家列表和信息
- 设置页：配置编辑
"""

import sys
from typing import Optional
from PySide6.QtCore import Qt, QThread, Signal, QTimer
from PySide6.QtWidgets import (
    QApplication, QWidget, QVBoxLayout, QHBoxLayout, QStackedWidget,
    QLabel, QLineEdit, QTextEdit, QSpinBox, QFrame, QScrollArea
)
from PySide6.QtGui import QIcon, QFont

# Fluent Widgets 导入
from qfluentwidgets import (
    NavigationInterface, NavigationItemPosition, NavigationAvatarWidget,
    FluentWindow, SubtitleLabel, BodyLabel, CaptionLabel,
    PrimaryPushButton, PushButton, TransparentPushButton, ToggleButton,
    LineEdit, TextEdit, SpinBox, SwitchButton,
    CardWidget, SimpleCardWidget, HeaderCardWidget,
    InfoBar, InfoBarPosition, MessageBox,
    FluentIcon as FIF, Theme, setTheme, isDarkTheme
)

from config import (
    APP_NAME, APP_TITLE, APP_VERSION,
    load_config, save_config, get_default_config, get_muip_url, get_admin_key,
    DEFAULT_HTTP_PORT, DEFAULT_GAME_PORT, DEFAULT_HOST
)
from muip_client import MuipClient
from auto_setup import AutoSetup, quick_setup
from proxy_manager import ProxyManager, get_proxy_manager


# ============================================
# 样式常量
# ============================================

CARD_STYLE = """
    CardWidget {
        border-radius: 8px;
        background-color: rgba(255, 255, 255, 0.7);
    }
"""


# ============================================
# 工作线程
# ============================================

class MuipWorker(QThread):
    """MUIP 操作工作线程"""
    finished = Signal(bool, str)
    
    def __init__(self, client: MuipClient, operation: str, **kwargs):
        super().__init__()
        self.client = client
        self.operation = operation
        self.kwargs = kwargs
    
    def run(self):
        try:
            if self.operation == "connect":
                success, msg = self.client.connect(self.kwargs.get("admin_key"))
            elif self.operation == "exec":
                success, msg = self.client.exec_command(
                    self.kwargs.get("command", ""),
                    self.kwargs.get("uid", 10001)
                )
            elif self.operation == "server_info":
                success, data = self.client.get_server_info()
                msg = str(data) if success else data.get("message", "获取失败")
            else:
                success, msg = False, "未知操作"
            
            self.finished.emit(success, msg)
        except Exception as e:
            self.finished.emit(False, str(e))


class SetupWorker(QThread):
    """自动配置工作线程"""
    progress = Signal(str, int, str)
    finished = Signal(bool, str)
    
    def __init__(self, http_port: int = 520, game_port: int = 23301):
        super().__init__()
        self.http_port = http_port
        self.game_port = game_port
    
    def run(self):
        def progress_callback(stage, percent, msg):
            self.progress.emit(stage, percent, msg)
        
        setup = AutoSetup(progress=progress_callback)
        success, msg = setup.run_full_setup(
            http_port=self.http_port,
            game_port=self.game_port
        )
        self.finished.emit(success, msg)


# ============================================
# 页面组件
# ============================================

class HomePage(QWidget):
    """首页：服务器状态和快捷操作"""
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.muip_client: Optional[MuipClient] = None
        self.proxy_manager = get_proxy_manager()
        self.init_ui()
        
        # 状态刷新定时器
        self.status_timer = QTimer(self)
        self.status_timer.timeout.connect(self.refresh_status)
        self.status_timer.start(5000)
    
    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(20)
        layout.setContentsMargins(36, 20, 36, 20)
        
        # 标题
        title = SubtitleLabel(f"欢迎使用 {APP_TITLE}")
        title.setFont(QFont("Microsoft YaHei", 24, QFont.Bold))
        layout.addWidget(title)
        
        # 状态卡片区域
        cards_layout = QHBoxLayout()
        cards_layout.setSpacing(16)
        
        # 服务器状态卡片
        self.server_card = self._create_status_card(
            "服务器状态", "未连接", FIF.CLOUD
        )
        cards_layout.addWidget(self.server_card)
        
        # 代理状态卡片
        self.proxy_card = self._create_status_card(
            "代理状态", "已停止", FIF.GLOBE
        )
        cards_layout.addWidget(self.proxy_card)
        
        # 在线玩家卡片
        self.players_card = self._create_status_card(
            "在线玩家", "0", FIF.PEOPLE
        )
        cards_layout.addWidget(self.players_card)
        
        layout.addLayout(cards_layout)
        
        # 快捷操作
        actions_label = SubtitleLabel("快捷操作")
        layout.addWidget(actions_label)
        
        actions_layout = QHBoxLayout()
        actions_layout.setSpacing(12)
        
        self.connect_btn = PrimaryPushButton("连接服务器")
        self.connect_btn.setIcon(FIF.LINK)
        self.connect_btn.clicked.connect(self.on_connect)
        actions_layout.addWidget(self.connect_btn)
        
        self.proxy_btn = PushButton("启动代理")
        self.proxy_btn.setIcon(FIF.PLAY)
        self.proxy_btn.clicked.connect(self.on_toggle_proxy)
        actions_layout.addWidget(self.proxy_btn)
        
        self.setup_btn = PushButton("自动配置")
        self.setup_btn.setIcon(FIF.SETTING)
        self.setup_btn.clicked.connect(self.on_auto_setup)
        actions_layout.addWidget(self.setup_btn)
        
        actions_layout.addStretch()
        layout.addLayout(actions_layout)
        
        # 日志区域
        log_label = SubtitleLabel("运行日志")
        layout.addWidget(log_label)
        
        self.log_text = TextEdit()
        self.log_text.setReadOnly(True)
        self.log_text.setMinimumHeight(200)
        self.log_text.setPlaceholderText("日志信息将在这里显示...")
        layout.addWidget(self.log_text)
        
        layout.addStretch()
    
    def _create_status_card(self, title: str, value: str, icon) -> CardWidget:
        """创建状态卡片"""
        card = CardWidget()
        card.setFixedSize(200, 120)
        
        card_layout = QVBoxLayout(card)
        card_layout.setContentsMargins(20, 16, 20, 16)
        
        title_label = CaptionLabel(title)
        title_label.setStyleSheet("color: gray;")
        card_layout.addWidget(title_label)
        
        value_label = SubtitleLabel(value)
        value_label.setFont(QFont("Microsoft YaHei", 20, QFont.Bold))
        value_label.setObjectName("valueLabel")
        card_layout.addWidget(value_label)
        
        card_layout.addStretch()
        
        return card
    
    def log(self, message: str):
        """添加日志"""
        self.log_text.append(message)
    
    def refresh_status(self):
        """刷新状态"""
        # 刷新代理状态
        if self.proxy_manager.is_running:
            self._update_card_value(self.proxy_card, "运行中")
            self.proxy_btn.setText("停止代理")
            self.proxy_btn.setIcon(FIF.PAUSE)
        else:
            self._update_card_value(self.proxy_card, "已停止")
            self.proxy_btn.setText("启动代理")
            self.proxy_btn.setIcon(FIF.PLAY)
    
    def _update_card_value(self, card: CardWidget, value: str):
        """更新卡片显示值"""
        label = card.findChild(SubtitleLabel, "valueLabel")
        if label:
            label.setText(value)
    
    def on_connect(self):
        """连接服务器"""
        self.log("正在连接服务器...")
        self.connect_btn.setEnabled(False)
        
        admin_key = get_admin_key()
        if not admin_key:
            self.log("[警告] 未配置管理密钥，请先运行服务器生成密钥")
            InfoBar.warning(
                title="警告",
                content="未配置管理密钥",
                parent=self,
                position=InfoBarPosition.TOP
            )
            self.connect_btn.setEnabled(True)
            return
        
        self.muip_client = MuipClient()
        self.worker = MuipWorker(self.muip_client, "connect", admin_key=admin_key)
        self.worker.finished.connect(self._on_connect_finished)
        self.worker.start()
    
    def _on_connect_finished(self, success: bool, msg: str):
        """连接完成回调"""
        self.connect_btn.setEnabled(True)
        
        if success:
            self._update_card_value(self.server_card, "已连接")
            self.log(f"[成功] {msg}")
            InfoBar.success(
                title="连接成功",
                content=msg,
                parent=self,
                position=InfoBarPosition.TOP
            )
        else:
            self._update_card_value(self.server_card, "连接失败")
            self.log(f"[错误] {msg}")
            InfoBar.error(
                title="连接失败",
                content=msg,
                parent=self,
                position=InfoBarPosition.TOP
            )
    
    def on_toggle_proxy(self):
        """切换代理状态"""
        if self.proxy_manager.is_running:
            self.log("正在停止代理...")
            if self.proxy_manager.stop():
                self.log("[成功] 代理已停止")
            else:
                self.log("[错误] 停止代理失败")
        else:
            self.log("正在启动代理...")
            if self.proxy_manager.start(headless=True, quiet=True):
                self.log("[成功] 代理已启动")
            else:
                self.log("[错误] 启动代理失败")
        
        self.refresh_status()
    
    def on_auto_setup(self):
        """自动配置"""
        self.log("开始自动配置...")
        self.setup_btn.setEnabled(False)
        
        self.setup_worker = SetupWorker()
        self.setup_worker.progress.connect(
            lambda s, p, m: self.log(f"[{s}] {p}% - {m}")
        )
        self.setup_worker.finished.connect(self._on_setup_finished)
        self.setup_worker.start()
    
    def _on_setup_finished(self, success: bool, msg: str):
        """配置完成回调"""
        self.setup_btn.setEnabled(True)
        
        if success:
            self.log(f"[成功] {msg}")
            InfoBar.success(
                title="配置完成",
                content=msg,
                parent=self,
                position=InfoBarPosition.TOP
            )
        else:
            self.log(f"[错误] {msg}")
            InfoBar.error(
                title="配置失败",
                content=msg,
                parent=self,
                position=InfoBarPosition.TOP
            )


class CommandPage(QWidget):
    """命令页：执行服务器命令"""
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.muip_client: Optional[MuipClient] = None
        self.init_ui()
    
    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(16)
        layout.setContentsMargins(36, 20, 36, 20)
        
        # 标题
        title = SubtitleLabel("命令执行")
        layout.addWidget(title)
        
        # 命令输入区
        input_card = HeaderCardWidget()
        input_card.setTitle("输入命令")
        input_layout = QVBoxLayout()
        
        # UID 输入
        uid_layout = QHBoxLayout()
        uid_layout.addWidget(BodyLabel("目标 UID:"))
        self.uid_input = SpinBox()
        self.uid_input.setRange(10001, 99999999)
        self.uid_input.setValue(10001)
        uid_layout.addWidget(self.uid_input)
        uid_layout.addStretch()
        input_layout.addLayout(uid_layout)
        
        # 命令输入
        self.cmd_input = LineEdit()
        self.cmd_input.setPlaceholderText("输入命令，如: /give 1001 100")
        self.cmd_input.returnPressed.connect(self.on_execute)
        input_layout.addWidget(self.cmd_input)
        
        # 快捷命令按钮
        quick_layout = QHBoxLayout()
        quick_cmds = [
            ("/help", "帮助"),
            ("/give all", "给予全部"),
            ("/heal", "恢复"),
            ("/unstuck", "解卡"),
        ]
        for cmd, label in quick_cmds:
            btn = TransparentPushButton(label)
            btn.clicked.connect(lambda checked, c=cmd: self.cmd_input.setText(c))
            quick_layout.addWidget(btn)
        quick_layout.addStretch()
        input_layout.addLayout(quick_layout)
        
        # 执行按钮
        self.exec_btn = PrimaryPushButton("执行命令")
        self.exec_btn.setIcon(FIF.SEND)
        self.exec_btn.clicked.connect(self.on_execute)
        input_layout.addWidget(self.exec_btn)
        
        input_card.viewLayout.addLayout(input_layout)
        layout.addWidget(input_card)
        
        # 输出区
        output_label = SubtitleLabel("命令输出")
        layout.addWidget(output_label)
        
        self.output_text = TextEdit()
        self.output_text.setReadOnly(True)
        self.output_text.setMinimumHeight(300)
        layout.addWidget(self.output_text)
        
        layout.addStretch()
    
    def set_client(self, client: MuipClient):
        """设置 MUIP 客户端"""
        self.muip_client = client
    
    def on_execute(self):
        """执行命令"""
        command = self.cmd_input.text().strip()
        if not command:
            return
        
        if not self.muip_client or not self.muip_client.is_authorized:
            self.output_text.append("[错误] 请先在首页连接服务器")
            return
        
        uid = self.uid_input.value()
        self.output_text.append(f"> {command} (UID: {uid})")
        self.exec_btn.setEnabled(False)
        
        self.worker = MuipWorker(
            self.muip_client, 
            "exec", 
            command=command, 
            uid=uid
        )
        self.worker.finished.connect(self._on_exec_finished)
        self.worker.start()
    
    def _on_exec_finished(self, success: bool, msg: str):
        """执行完成回调"""
        self.exec_btn.setEnabled(True)
        
        if success:
            self.output_text.append(msg)
        else:
            self.output_text.append(f"[错误] {msg}")


class SettingsPage(QWidget):
    """设置页：配置编辑"""
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.init_ui()
        self.load_settings()
    
    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(16)
        layout.setContentsMargins(36, 20, 36, 20)
        
        # 标题
        title = SubtitleLabel("设置")
        layout.addWidget(title)
        
        # 服务器配置卡片
        server_card = HeaderCardWidget()
        server_card.setTitle("服务器配置")
        server_layout = QVBoxLayout()
        
        # HTTP 端口
        http_layout = QHBoxLayout()
        http_layout.addWidget(BodyLabel("HTTP/MUIP 端口:"))
        self.http_port = SpinBox()
        self.http_port.setRange(1, 65535)
        self.http_port.setValue(DEFAULT_HTTP_PORT)
        http_layout.addWidget(self.http_port)
        http_layout.addStretch()
        server_layout.addLayout(http_layout)
        
        # 游戏端口
        game_layout = QHBoxLayout()
        game_layout.addWidget(BodyLabel("游戏服务器端口:"))
        self.game_port = SpinBox()
        self.game_port.setRange(1, 65535)
        self.game_port.setValue(DEFAULT_GAME_PORT)
        game_layout.addWidget(self.game_port)
        game_layout.addStretch()
        server_layout.addLayout(game_layout)
        
        # 主机地址
        host_layout = QHBoxLayout()
        host_layout.addWidget(BodyLabel("主机地址:"))
        self.host_input = LineEdit()
        self.host_input.setText(DEFAULT_HOST)
        host_layout.addWidget(self.host_input)
        host_layout.addStretch()
        server_layout.addLayout(host_layout)
        
        # SSL 开关
        ssl_layout = QHBoxLayout()
        ssl_layout.addWidget(BodyLabel("启用 SSL:"))
        self.ssl_switch = SwitchButton()
        self.ssl_switch.setChecked(True)
        ssl_layout.addWidget(self.ssl_switch)
        ssl_layout.addStretch()
        server_layout.addLayout(ssl_layout)
        
        server_card.viewLayout.addLayout(server_layout)
        layout.addWidget(server_card)
        
        # 保存按钮
        btn_layout = QHBoxLayout()
        self.save_btn = PrimaryPushButton("保存配置")
        self.save_btn.setIcon(FIF.SAVE)
        self.save_btn.clicked.connect(self.save_settings)
        btn_layout.addWidget(self.save_btn)
        
        self.reset_btn = PushButton("恢复默认")
        self.reset_btn.clicked.connect(self.reset_settings)
        btn_layout.addWidget(self.reset_btn)
        
        btn_layout.addStretch()
        layout.addLayout(btn_layout)
        
        layout.addStretch()
    
    def load_settings(self):
        """加载配置"""
        config = load_config()
        if config:
            http_config = config.get("HttpServer", {})
            game_config = config.get("GameServer", {})
            
            self.http_port.setValue(http_config.get("Port", DEFAULT_HTTP_PORT))
            self.game_port.setValue(game_config.get("Port", DEFAULT_GAME_PORT))
            self.host_input.setText(http_config.get("PublicAddress", DEFAULT_HOST))
            self.ssl_switch.setChecked(http_config.get("UseSSL", True))
    
    def save_settings(self):
        """保存配置"""
        config = load_config() or get_default_config()
        
        config["HttpServer"]["Port"] = self.http_port.value()
        config["HttpServer"]["PublicAddress"] = self.host_input.text()
        config["HttpServer"]["UseSSL"] = self.ssl_switch.isChecked()
        config["GameServer"]["Port"] = self.game_port.value()
        config["GameServer"]["PublicAddress"] = self.host_input.text()
        
        if save_config(config):
            InfoBar.success(
                title="保存成功",
                content="配置已保存",
                parent=self,
                position=InfoBarPosition.TOP
            )
        else:
            InfoBar.error(
                title="保存失败",
                content="无法保存配置文件",
                parent=self,
                position=InfoBarPosition.TOP
            )
    
    def reset_settings(self):
        """恢复默认"""
        self.http_port.setValue(DEFAULT_HTTP_PORT)
        self.game_port.setValue(DEFAULT_GAME_PORT)
        self.host_input.setText(DEFAULT_HOST)
        self.ssl_switch.setChecked(True)


# ============================================
# 主窗口
# ============================================

class MainWindow(FluentWindow):
    """主窗口"""
    
    def __init__(self):
        super().__init__()
        self.setWindowTitle(f"{APP_TITLE} v{APP_VERSION}")
        self.resize(1100, 750)
        
        # 初始化页面
        self.home_page = HomePage()
        self.command_page = CommandPage()
        self.settings_page = SettingsPage()
        
        # 添加导航项
        self.addSubInterface(self.home_page, FIF.HOME, "首页")
        self.addSubInterface(self.command_page, FIF.COMMAND_PROMPT, "命令")
        self.addSubInterface(
            self.settings_page, 
            FIF.SETTING, 
            "设置",
            NavigationItemPosition.BOTTOM
        )
        
        # 设置导航栏
        self.navigationInterface.setExpandWidth(200)
        
        # 连接信号
        self.home_page.muip_client = None
    
    def closeEvent(self, event):
        """关闭时清理资源"""
        # 停止代理
        proxy = get_proxy_manager()
        if proxy.is_running:
            proxy.stop()
        
        event.accept()


# ============================================
# 启动函数
# ============================================

def run_app():
    """启动应用"""
    app = QApplication(sys.argv)
    
    # 设置主题
    setTheme(Theme.AUTO)
    
    # 创建并显示主窗口
    window = MainWindow()
    window.show()
    
    return app.exec()


if __name__ == "__main__":
    sys.exit(run_app())
