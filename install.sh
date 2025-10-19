#!/bin/bash

# SnapSync v3.0 安装脚本 - 完整修复版
# 修复：
# 1. 处理重复安装
# 2. 依赖包名适配
# 3. 更智能的错误处理

set -euo pipefail

# ===== 颜色定义 =====
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# ===== 路径定义 =====
INSTALL_DIR="/opt/snapsync"
CONFIG_DIR="/etc/snapsync"
LOG_DIR="/var/log/snapsync"
DEFAULT_BACKUP_DIR="/backups"

# 记录安装源路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ===== 权限检查 =====
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 需要 root 权限${NC}"
    echo -e "${YELLOW}使用: sudo bash $0${NC}"
    exit 1
fi

# ===== 工具函数 =====
log() {
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    echo -e "$(date '+%F %T') $*" | tee -a "$LOG_DIR/install.log"
}

# ===== 检测系统 =====
detect_system() {
    log "${CYAN}检测系统信息...${NC}"
    
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_NAME="$ID"
        OS_VERSION="${VERSION_ID:-unknown}"
        log "${GREEN}系统: ${PRETTY_NAME:-$ID}${NC}"
    else
        log "${RED}无法检测系统版本${NC}"
        exit 1
    fi
    
    # 检测包管理器
    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt-get"
        PKG_UPDATE="apt-get update -qq"
        PKG_INSTALL="apt-get install -y -qq"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
        PKG_UPDATE="yum makecache -q"
        PKG_INSTALL="yum install -y -q"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
        PKG_UPDATE="dnf makecache -q"
        PKG_INSTALL="dnf install -y -q"
    else
        log "${RED}错误: 未检测到支持的包管理器${NC}"
        exit 1
    fi
    
    log "${GREEN}包管理器: $PKG_MANAGER${NC}\n"
}

# ===== 安装单个包 =====
install_package() {
    local pkg="$1"
    local is_optional="${2:-no}"
    
    # 检查命令是否存在
    if command -v "$pkg" &>/dev/null; then
        log "  ${GREEN}✓ $pkg${NC} (已存在)"
        return 0
    fi
    
    # 尝试安装
    log "  安装 $pkg..."
    if eval "$PKG_INSTALL $pkg" >/dev/null 2>&1; then
        log "  ${GREEN}✓ $pkg${NC}"
        return 0
    else
        if [[ "$is_optional" == "yes" ]]; then
            log "  ${YELLOW}⚠ 跳过 $pkg (可选)${NC}"
            return 0
        else
            log "  ${RED}✗ $pkg 安装失败${NC}"
            return 1
        fi
    fi
}

# ===== 安装依赖 =====
install_dependencies() {
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${CYAN}安装系统依赖${NC}"
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    log "${YELLOW}更新包列表...${NC}"
    eval "$PKG_UPDATE" >/dev/null 2>&1 || log "${YELLOW}⚠ 更新失败，继续${NC}"
    
    # 基础工具
    log "\n${YELLOW}安装基础工具...${NC}"
    
    declare -A pkg_map
    if [[ "$PKG_MANAGER" == "apt-get" ]]; then
        pkg_map=(
            ["openssh-client"]="openssh-client"
            ["tar"]="tar"
            ["gzip"]="gzip"
            ["curl"]="curl"
            ["rsync"]="rsync"
            ["jq"]="jq"
            ["bc"]="bc"
            ["findutils"]="findutils"
        )
    else
        pkg_map=(
            ["openssh-clients"]="openssh-clients"
            ["tar"]="tar"
            ["gzip"]="gzip"
            ["curl"]="curl"
            ["rsync"]="rsync"
            ["jq"]="jq"
            ["bc"]="bc"
            ["findutils"]="findutils"
        )
    fi
    
    # 安装必需包
    for pkg_name in "${pkg_map[@]}"; do
        install_package "$pkg_name" "no" || true
    done
    
    # 可选工具
    log "\n${YELLOW}安装增强工具...${NC}"
    
    local optional_pkgs=""
    if [[ "$PKG_MANAGER" == "apt-get" ]]; then
        optional_pkgs="pigz acl attr pv bzip2 xz-utils"
    else
        optional_pkgs="pigz acl attr pv bzip2 xz"
    fi
    
    for pkg in $optional_pkgs; do
        install_package "$pkg" "yes"
    done
    
    log "\n${GREEN}✓ 依赖安装完成${NC}\n"
}

# ===== 安装文件 =====
install_files() {
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${CYAN}安装程序文件${NC}"
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    # 创建目录
    mkdir -p "$INSTALL_DIR"/{modules,bot}
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$DEFAULT_BACKUP_DIR/system_snapshots"
    
    # 复制主脚本
    if [[ -f "$SCRIPT_DIR/snapsync.sh" ]]; then
        cp "$SCRIPT_DIR/snapsync.sh" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/snapsync.sh"
        log "${GREEN}✓ 主脚本${NC}"
    else
        log "${RED}✗ 未找到 snapsync.sh${NC}"
    fi
    
    # 复制模块
    for module in backup.sh restore.sh config.sh; do
        if [[ -f "$SCRIPT_DIR/$module" ]]; then
            cp "$SCRIPT_DIR/$module" "$INSTALL_DIR/modules/"
            chmod +x "$INSTALL_DIR/modules/$module"
            log "${GREEN}✓ $module${NC}"
        else
            log "${YELLOW}⚠ 未找到 $module${NC}"
        fi
    done
    
    # 复制Bot脚本
    if [[ -f "$SCRIPT_DIR/telegram_bot.sh" ]]; then
        cp "$SCRIPT_DIR/telegram_bot.sh" "$INSTALL_DIR/bot/"
        chmod +x "$INSTALL_DIR/bot/telegram_bot.sh"
        log "${GREEN}✓ Bot脚本${NC}"
    else
        log "${YELLOW}⚠ 未找到 telegram_bot.sh${NC}"
    fi
    
    # 复制诊断工具
    if [[ -f "$SCRIPT_DIR/telegram-test.sh" ]]; then
        # 先删除可能存在的旧链接
        rm -f /usr/local/bin/telegram-test
        cp "$SCRIPT_DIR/telegram-test.sh" "/usr/local/bin/telegram-test"
        chmod +x "/usr/local/bin/telegram-test"
        log "${GREEN}✓ 诊断工具${NC}"
    else
        log "${YELLOW}⚠ 未找到 telegram-test.sh${NC}"
    fi
    
    log "\n${GREEN}✓ 文件安装完成${NC}\n"
}

# ===== 创建配置 =====
create_config() {
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${CYAN}创建配置文件${NC}"
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    if [[ -f "$CONFIG_DIR/config.conf" ]]; then
        log "${YELLOW}配置文件已存在，保留现有配置${NC}"
        return
    fi
    
    cat > "$CONFIG_DIR/config.conf" << 'EOF'
#!/bin/bash

# SnapSync v3.0 配置文件

# ===== Telegram 配置 =====
TELEGRAM_ENABLED="false"
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

# ===== 远程备份配置 =====
REMOTE_ENABLED="false"
REMOTE_HOST=""
REMOTE_USER="root"
REMOTE_PORT="22"
REMOTE_PATH="/backups"
REMOTE_KEEP_DAYS="30"

# ===== 本地备份配置 =====
BACKUP_DIR="/backups"
COMPRESSION_LEVEL="6"
PARALLEL_THREADS="auto"
LOCAL_KEEP_COUNT="5"

# ===== 定时任务配置 =====
AUTO_BACKUP_ENABLED="false"
BACKUP_INTERVAL_DAYS="7"
BACKUP_TIME="03:00"

# ===== 高级配置 =====
ENABLE_ACL="true"
ENABLE_XATTR="true"
ENABLE_VERIFICATION="true"
DISK_THRESHOLD="90"
HOSTNAME="$(hostname)"
EOF
    
    chmod 600 "$CONFIG_DIR/config.conf"
    log "${GREEN}✓ 配置文件已创建${NC}\n"
}

# ===== 创建系统服务 =====
create_services() {
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${CYAN}创建系统服务${NC}"
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    # Bot服务
    cat > /etc/systemd/system/snapsync-bot.service << EOF
[Unit]
Description=SnapSync Telegram Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR/bot
ExecStart=/bin/bash $INSTALL_DIR/bot/telegram_bot.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # 备份服务
    cat > /etc/systemd/system/snapsync-backup.service << EOF
[Unit]
Description=SnapSync Backup Service
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash $INSTALL_DIR/modules/backup.sh
EOF
    
    # 定时器
    cat > /etc/systemd/system/snapsync-backup.timer << EOF
[Unit]
Description=SnapSync Backup Timer

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    systemctl daemon-reload
    log "${GREEN}✓ 系统服务已创建${NC}\n"
}

# ===== 创建命令快捷方式 =====
create_shortcuts() {
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${CYAN}创建命令快捷方式${NC}"
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    ln -sf "$INSTALL_DIR/snapsync.sh" /usr/local/bin/snapsync
    ln -sf "$INSTALL_DIR/modules/backup.sh" /usr/local/bin/snapsync-backup
    ln -sf "$INSTALL_DIR/modules/restore.sh" /usr/local/bin/snapsync-restore
    
    log "${GREEN}✓ snapsync${NC}"
    log "${GREEN}✓ snapsync-backup${NC}"
    log "${GREEN}✓ snapsync-restore${NC}"
    log "${GREEN}✓ telegram-test${NC}\n"
}

# ===== 完成安装 =====
finish_installation() {
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${GREEN}✓✓✓ 安装完成！✓✓✓${NC}"
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    echo -e "${YELLOW}快速开始:${NC}"
    echo -e "  1. 启动控制台: ${CYAN}sudo snapsync${NC}"
    echo -e "  2. 创建快照:   ${CYAN}sudo snapsync-backup${NC}"
    echo -e "  3. 恢复快照:   ${CYAN}sudo snapsync-restore${NC}"
    echo -e "  4. 测试TG:     ${CYAN}sudo telegram-test${NC}"
    echo ""
    echo -e "${YELLOW}配置建议:${NC}"
    echo -e "  • 运行 ${CYAN}sudo snapsync${NC} 进入配置向导"
    echo -e "  • 配置 Telegram Bot（可选）"
    echo -e "  • 配置远程备份服务器（可选）"
    echo ""
}

# ===== 主程序 =====
main() {
    clear
    echo ""
    log "${BLUE}╔════════════════════════════════════════════╗${NC}"
    log "${BLUE}║${CYAN}       SnapSync v3.0 安装程序              ${BLUE}║${NC}"
    log "${BLUE}╚════════════════════════════════════════════╝${NC}"
    echo ""
    
    # 检查是否已安装
    if [[ -d "$INSTALL_DIR" ]]; then
        log "${YELLOW}检测到已安装 SnapSync${NC}"
        read -p "是否重新安装（会保留配置）? [y/N]: " reinstall
        if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
            log "${GREEN}已取消${NC}"
            exit 0
        fi
    fi
    
    detect_system
    install_dependencies
    install_files
    create_config
    create_services
    create_shortcuts
    finish_installation
}

main "$@"
