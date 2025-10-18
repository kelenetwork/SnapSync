#!/bin/bash

# SnapSync v3.0 安装脚本 - 已修复所有已知bug
# 直接运行此脚本即可完成安装

set -euo pipefail

# ===== 颜色定义 =====
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# ===== 路径定义 (不使用readonly避免冲突) =====
INSTALL_DIR="/opt/snapsync"
CONFIG_DIR="/etc/snapsync"
LOG_DIR="/var/log/snapsync"
DEFAULT_BACKUP_DIR="/backups"

# ===== 权限检查 =====
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 需要 root 权限${NC}"
    echo -e "${YELLOW}使用: sudo bash $0${NC}"
    exit 1
fi

# ===== 工具函数 =====
log() {
    mkdir -p "$LOG_DIR"
    echo -e "$(date '+%F %T') $*" | tee -a "$LOG_DIR/install.log"
}

show_banner() {
    clear
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════════════╗
║                                               ║
║        ███████╗███╗   ██╗ █████╗ ██████╗     ║
║        ██╔════╝████╗  ██║██╔══██╗██╔══██╗    ║
║        ███████╗██╔██╗ ██║███████║██████╔╝    ║
║        ╚════██║██║╚██╗██║██╔══██║██╔═══╝     ║
║        ███████║██║ ╚████║██║  ██║██║         ║
║        ╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝         ║
║                                               ║
║         ███████╗██╗   ██╗███╗   ██╗ ██████╗  ║
║         ██╔════╝╚██╗ ██╔╝████╗  ██║██╔════╝  ║
║         ███████╗ ╚████╔╝ ██╔██╗ ██║██║       ║
║         ╚════██║  ╚██╔╝  ██║╚██╗██║██║       ║
║         ███████║   ██║   ██║ ╚████║╚██████╗  ║
║         ╚══════╝   ╚═╝   ╚═╝  ╚═══╝ ╚═════╝  ║
║                                               ║
║              无损快照备份系统 v3.0               ║
║                                               ║
╚═══════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo -e "${CYAN}欢迎使用 SnapSync 安装程序！${NC}\n"
    sleep 2
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
        PKG_INSTALL="apt-get install -y"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
        PKG_UPDATE="yum makecache -q"
        PKG_INSTALL="yum install -y"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
        PKG_UPDATE="dnf makecache -q"
        PKG_INSTALL="dnf install -y"
    else
        log "${RED}错误: 未检测到支持的包管理器${NC}"
        exit 1
    fi
    
    log "${GREEN}包管理器: $PKG_MANAGER${NC}\n"
}

# ===== 安装依赖 =====
install_dependencies() {
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${CYAN}安装系统依赖${NC}"
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    log "${YELLOW}更新包列表...${NC}"
    eval "$PKG_UPDATE" >/dev/null 2>&1 || log "${YELLOW}⚠ 更新失败，继续${NC}"
    
    # 基础工具
    local base_packages="curl tar gzip rsync jq bc openssh-client findutils coreutils"
    
    # 可选工具
    local optional_packages="pigz acl attr pv bzip2 xz-utils"
    
    log "${YELLOW}安装基础工具...${NC}"
    for pkg in $base_packages; do
        if ! command -v "$pkg" &>/dev/null && ! dpkg -l 2>/dev/null | grep -q "^ii  $pkg "; then
            log "  安装 $pkg..."
            eval "$PKG_INSTALL $pkg" >/dev/null 2>&1 || log "  ${YELLOW}⚠ $pkg 安装失败${NC}"
        else
            log "  ${GREEN}✓ $pkg${NC}"
        fi
    done
    
    log "\n${YELLOW}安装增强工具...${NC}"
    for pkg in $optional_packages; do
        if ! command -v "$pkg" &>/dev/null && ! dpkg -l 2>/dev/null | grep -q "^ii  $pkg "; then
            log "  安装 $pkg (可选)..."
            eval "$PKG_INSTALL $pkg" >/dev/null 2>&1 || log "  ${YELLOW}⚠ 跳过 $pkg${NC}"
        fi
    done
    
    log "\n${GREEN}✓ 依赖安装完成${NC}\n"
}

# ===== 创建目录结构 =====
create_directories() {
    log "${CYAN}创建目录结构...${NC}"
    
    mkdir -p "$INSTALL_DIR"/{modules,bot,scripts}
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"
    
    # 使用配置的备份目录或默认目录
    local backup_dir="${BACKUP_DIR_CONFIG:-$DEFAULT_BACKUP_DIR}"
    mkdir -p "$backup_dir"/{system_snapshots,metadata,checksums}
    
    chmod 755 "$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR"
    
    log "${GREEN}✓ 目录创建完成${NC}\n"
}

# ===== 复制程序文件 =====
copy_program_files() {
    log "${CYAN}复制程序文件...${NC}"
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # 复制主脚本
    if [[ -f "$script_dir/snapsync.sh" ]]; then
        cp "$script_dir/snapsync.sh" "$INSTALL_DIR/snapsync.sh"
        chmod +x "$INSTALL_DIR/snapsync.sh"
        log "${GREEN}  ✓ snapsync.sh${NC}"
    fi
    
    # 复制模块
    for module in backup.sh restore.sh config.sh utils.sh; do
        if [[ -f "$script_dir/modules/$module" ]]; then
            cp "$script_dir/modules/$module" "$INSTALL_DIR/modules/"
            chmod +x "$INSTALL_DIR/modules/$module"
            log "${GREEN}  ✓ modules/$module${NC}"
        elif [[ -f "$script_dir/$module" ]]; then
            cp "$script_dir/$module" "$INSTALL_DIR/modules/"
            chmod +x "$INSTALL_DIR/modules/$module"
            log "${GREEN}  ✓ $module${NC}"
        fi
    done
    
    # 复制Bot
    if [[ -f "$script_dir/bot/telegram_bot.sh" ]]; then
        cp "$script_dir/bot/telegram_bot.sh" "$INSTALL_DIR/bot/"
        chmod +x "$INSTALL_DIR/bot/telegram_bot.sh"
        log "${GREEN}  ✓ bot/telegram_bot.sh${NC}"
    elif [[ -f "$script_dir/telegram_bot.sh" ]]; then
        cp "$script_dir/telegram_bot.sh" "$INSTALL_DIR/bot/"
        chmod +x "$INSTALL_DIR/bot/telegram_bot.sh"
        log "${GREEN}  ✓ telegram_bot.sh${NC}"
    fi
    
    # 复制诊断工具
    if [[ -f "$script_dir/telegram-test.sh" ]]; then
        cp "$script_dir/telegram-test.sh" "$INSTALL_DIR/scripts/"
        chmod +x "$INSTALL_DIR/scripts/telegram-test.sh"
        ln -sf "$INSTALL_DIR/scripts/telegram-test.sh" /usr/local/bin/telegram-test
        log "${GREEN}  ✓ telegram-test.sh${NC}"
    fi
    
    log "${GREEN}✓ 程序文件复制完成${NC}\n"
}

# ===== SSH密钥设置 =====
setup_ssh_key() {
    local user="$1"
    local host="$2"
    local port="$3"
    
    local ssh_key="/root/.ssh/id_ed25519"
    
    if [[ ! -f "$ssh_key" ]]; then
        log "${YELLOW}生成 SSH 密钥...${NC}"
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
        ssh-keygen -t ed25519 -N "" -f "$ssh_key" -q
        log "${GREEN}✓ SSH 密钥已生成${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}请将以下公钥添加到远程服务器:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    cat "${ssh_key}.pub"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "在远程服务器上执行:"
    echo "  ssh $user@$host -p $port"
    echo "  mkdir -p ~/.ssh && chmod 700 ~/.ssh"
    echo "  echo '$(cat ${ssh_key}.pub)' >> ~/.ssh/authorized_keys"
    echo "  chmod 600 ~/.ssh/authorized_keys"
    echo ""
    
    read -p "已添加公钥? [Y/n]: " key_added
    if [[ ! "$key_added" =~ ^[Nn]$ ]]; then
        if ssh -i "$ssh_key" -p "$port" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$user@$host" "echo test" &>/dev/null; then
            log "${GREEN}✓ SSH 连接测试成功${NC}"
        else
            log "${YELLOW}⚠ SSH 连接测试失败${NC}"
        fi
    fi
}

# ===== 配置向导 =====
run_config_wizard() {
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${CYAN}配置向导${NC}"
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    # Telegram配置
    echo -e "${YELLOW}1. Telegram 通知配置${NC}"
    echo "   提示: 访问 @BotFather 创建 Bot"
    read -p "启用 Telegram? [Y/n]: " enable_tg
    enable_tg=${enable_tg:-Y}
    
    local bot_token="" chat_id=""
    if [[ "$enable_tg" =~ ^[Yy]$ ]]; then
        read -p "Bot Token: " bot_token
        read -p "Chat ID: " chat_id
    fi
    
    # 远程备份配置
    echo ""
    echo -e "${YELLOW}2. 远程备份配置${NC}"
    read -p "启用远程备份? [Y/n]: " enable_remote
    enable_remote=${enable_remote:-Y}
    
    local remote_host="" remote_user="root" remote_port="22" remote_path="/backups"
    if [[ "$enable_remote" =~ ^[Yy]$ ]]; then
        read -p "远程服务器地址: " remote_host
        read -p "远程用户名 [root]: " remote_user
        remote_user=${remote_user:-root}
        read -p "SSH 端口 [22]: " remote_port
        remote_port=${remote_port:-22}
        read -p "远程路径 [/backups]: " remote_path
        remote_path=${remote_path:-/backups}
        
        setup_ssh_key "$remote_user" "$remote_host" "$remote_port"
    fi
    
    # 本地配置
    echo ""
    echo -e "${YELLOW}3. 本地备份配置${NC}"
    read -p "本地备份目录 [/backups]: " backup_dir
    backup_dir=${backup_dir:-/backups}
    BACKUP_DIR_CONFIG="$backup_dir"
    
    read -p "压缩级别 (1-9) [6]: " compression
    compression=${compression:-6}
    
    read -p "保留快照数量 [5]: " keep_count
    keep_count=${keep_count:-5}
    
    # 定时任务
    echo ""
    echo -e "${YELLOW}4. 定时任务配置${NC}"
    read -p "启用自动备份? [Y/n]: " enable_auto
    enable_auto=${enable_auto:-Y}
    
    local interval="7" backup_time="03:00"
    if [[ "$enable_auto" =~ ^[Yy]$ ]]; then
        read -p "备份间隔(天) [7]: " interval
        interval=${interval:-7}
        read -p "备份时间 [03:00]: " backup_time
        backup_time=${backup_time:-03:00}
    fi
    
    # 生成配置文件
    cat > "$CONFIG_DIR/config.conf" << EOF
#!/bin/bash
# SnapSync v3.0 配置文件
# 生成时间: $(date '+%F %T')

# Telegram配置
TELEGRAM_ENABLED="${enable_tg}"
TELEGRAM_BOT_TOKEN="${bot_token}"
TELEGRAM_CHAT_ID="${chat_id}"

# 远程备份
REMOTE_ENABLED="${enable_remote}"
REMOTE_HOST="${remote_host}"
REMOTE_USER="${remote_user}"
REMOTE_PORT="${remote_port}"
REMOTE_PATH="${remote_path}"
REMOTE_KEEP_DAYS="30"

# 本地备份
BACKUP_DIR="${backup_dir}"
COMPRESSION_LEVEL="${compression}"
PARALLEL_THREADS="auto"
LOCAL_KEEP_COUNT="${keep_count}"

# 定时任务
AUTO_BACKUP_ENABLED="${enable_auto}"
BACKUP_INTERVAL_DAYS="${interval}"
BACKUP_TIME="${backup_time}"

# 高级配置
ENABLE_ACL="true"
ENABLE_XATTR="true"
ENABLE_VERIFICATION="true"
DISK_THRESHOLD="90"
MEMORY_THRESHOLD="85"

# 系统信息
HOSTNAME="$(hostname)"
INSTALL_DATE="$(date '+%F %T')"
EOF

    chmod 600 "$CONFIG_DIR/config.conf"
    log "${GREEN}✓ 配置文件已生成${NC}\n"
}

# ===== 设置系统服务 =====
setup_systemd_services() {
    log "${CYAN}设置系统服务...${NC}"
    
    # 备份服务
    cat > /etc/systemd/system/snapsync-backup.service << 'EOF'
[Unit]
Description=SnapSync Backup Service
After=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/snapsync/modules/backup.sh
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # 定时器
    local timer_time="03:00"
    [[ -f "$CONFIG_DIR/config.conf" ]] && source "$CONFIG_DIR/config.conf" && timer_time="${BACKUP_TIME:-03:00}"
    
    cat > /etc/systemd/system/snapsync-backup.timer << EOF
[Unit]
Description=SnapSync Backup Timer

[Timer]
OnCalendar=*-*-* ${timer_time}:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Bot服务
    cat > /etc/systemd/system/snapsync-bot.service << 'EOF'
[Unit]
Description=SnapSync Telegram Bot
After=network-online.target

[Service]
Type=simple
ExecStart=/opt/snapsync/bot/telegram_bot.sh
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    
    # 启用服务
    if [[ -f "$CONFIG_DIR/config.conf" ]]; then
        source "$CONFIG_DIR/config.conf"
        
        if [[ "${AUTO_BACKUP_ENABLED}" =~ ^[Yy]|true$ ]]; then
            systemctl enable snapsync-backup.timer &>/dev/null
            systemctl start snapsync-backup.timer &>/dev/null
            log "${GREEN}  ✓ 自动备份已启用${NC}"
        fi
        
        if [[ "${TELEGRAM_ENABLED}" =~ ^[Yy]|true$ ]] && [[ -x "$INSTALL_DIR/bot/telegram_bot.sh" ]]; then
            systemctl enable snapsync-bot.service &>/dev/null
            systemctl start snapsync-bot.service &>/dev/null
            log "${GREEN}  ✓ Telegram Bot已启动${NC}"
        fi
    fi
    
    log "${GREEN}✓ 系统服务设置完成${NC}\n"
}

# ===== 创建命令快捷方式 =====
create_shortcuts() {
    log "${CYAN}创建命令快捷方式...${NC}"
    
    rm -f /usr/local/bin/snapsync* 2>/dev/null || true
    
    # 主命令
    ln -sf "$INSTALL_DIR/snapsync.sh" /usr/local/bin/snapsync
    
    # 备份命令
    cat > /usr/local/bin/snapsync-backup << 'EOF'
#!/bin/bash
exec /opt/snapsync/modules/backup.sh "$@"
EOF
    chmod +x /usr/local/bin/snapsync-backup
    
    # 恢复命令
    cat > /usr/local/bin/snapsync-restore << 'EOF'
#!/bin/bash
exec /opt/snapsync/modules/restore.sh "$@"
EOF
    chmod +x /usr/local/bin/snapsync-restore
    
    log "${GREEN}✓ 命令快捷方式创建完成${NC}\n"
}

# ===== 完成安装 =====
finish_installation() {
    log "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${GREEN}✓ SnapSync v3.0 安装完成！${NC}"
    log "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    echo -e "${CYAN}安装信息:${NC}"
    echo -e "  程序目录: $INSTALL_DIR"
    echo -e "  配置文件: $CONFIG_DIR/config.conf"
    echo -e "  日志目录: $LOG_DIR"
    [[ -f "$CONFIG_DIR/config.conf" ]] && source "$CONFIG_DIR/config.conf" && echo -e "  备份目录: ${BACKUP_DIR}"
    echo ""
    
    echo -e "${CYAN}可用命令:${NC}"
    echo -e "  ${GREEN}snapsync${NC}         - 管理控制台"
    echo -e "  ${GREEN}snapsync-backup${NC}  - 创建快照"
    echo -e "  ${GREEN}snapsync-restore${NC} - 恢复快照"
    echo -e "  ${GREEN}telegram-test${NC}    - 测试Telegram通知"
    echo ""
    
    echo -e "${CYAN}快速开始:${NC}"
    echo -e "  运行: ${GREEN}snapsync${NC} 或 ${GREEN}snapsync-backup${NC}"
    echo ""
}

# ===== 主程序 =====
main() {
    mkdir -p "$LOG_DIR"
    show_banner
    detect_system
    install_dependencies
    create_directories     # ← 先创建目录
    run_config_wizard      # ← 再运行配置向导
    copy_program_files
    setup_systemd_services
    create_shortcuts
    finish_installation
    
    read -p "立即运行 snapsync? [Y/n]: " run_now
    [[ ! "$run_now" =~ ^[Nn]$ ]] && command -v snapsync &>/dev/null && snapsync
}

main "$@"
