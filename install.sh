#!/bin/bash

# SnapSync v3.0 一键安装脚本
# 自动安装所有依赖和配置

set -euo pipefail

# ===== 颜色定义 =====
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# ===== 路径定义 =====
readonly INSTALL_DIR="/opt/snapsync"
readonly CONFIG_DIR="/etc/snapsync"
readonly LOG_DIR="/var/log/snapsync"
readonly BACKUP_DIR="/backups"

# ===== 权限检查 =====
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 需要 root 权限${NC}"
    echo -e "${YELLOW}使用: sudo $0${NC}"
    exit 1
fi

# ===== 工具函数 =====
log() {
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
        OS_VERSION="$VERSION_ID"
        log "${GREEN}系统: $PRETTY_NAME${NC}"
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
    
    # 更新包列表
    log "${YELLOW}更新包列表...${NC}"
    eval "$PKG_UPDATE" >/dev/null 2>&1 || true
    
    # 基础工具
    local base_packages=(
        "curl" "tar" "gzip" "rsync" "jq" "bc"
        "openssh-client" "findutils" "coreutils"
    )
    
    # 可选工具
    local optional_packages=(
        "pigz" "acl" "attr" "pv" "bzip2" "xz-utils"
    )
    
    # 安装基础包
    log "${YELLOW}安装基础工具...${NC}"
    for pkg in "${base_packages[@]}"; do
        if ! command -v "${pkg##*:}" &>/dev/null; then
            log "  安装 $pkg..."
            eval "$PKG_INSTALL $pkg" >/dev/null 2>&1 || log "  ${YELLOW}⚠ $pkg 安装失败${NC}"
        else
            log "  ${GREEN}✓ $pkg 已安装${NC}"
        fi
    done
    
    # 安装可选包
    log "\n${YELLOW}安装增强工具...${NC}"
    for pkg in "${optional_packages[@]}"; do
        if ! command -v "$pkg" &>/dev/null; then
            log "  安装 $pkg (可选)..."
            eval "$PKG_INSTALL $pkg" >/dev/null 2>&1 || log "  ${YELLOW}⚠ 跳过 $pkg${NC}"
        else
            log "  ${GREEN}✓ $pkg 已安装${NC}"
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
    mkdir -p "$BACKUP_DIR"/{system_snapshots,metadata,checksums}
    
    log "${GREEN}✓ 目录创建完成${NC}\n"
}

# ===== 下载文件 =====
download_files() {
    log "${CYAN}下载程序文件...${NC}"
    
    local repo_url="https://raw.githubusercontent.com/kelenetwork/SnapSync/main"
    
    # 主脚本
    log "  下载 snapsync.sh..."
    curl -sL "${repo_url}/snapsync.sh" -o "$INSTALL_DIR/snapsync.sh" 2>/dev/null || {
        log "${YELLOW}  使用本地文件${NC}"
        cp snapsync.sh "$INSTALL_DIR/snapsync.sh" 2>/dev/null || true
    }
    
    # 模块文件
    for module in backup.sh restore.sh config.sh utils.sh; do
        log "  下载 $module..."
        curl -sL "${repo_url}/modules/$module" -o "$INSTALL_DIR/modules/$module" 2>/dev/null || {
            log "${YELLOW}  使用本地文件${NC}"
            cp "modules/$module" "$INSTALL_DIR/modules/$module" 2>/dev/null || true
        }
    done
    
    # Bot 文件
    log "  下载 telegram_bot.sh..."
    curl -sL "${repo_url}/bot/telegram_bot.sh" -o "$INSTALL_DIR/bot/telegram_bot.sh" 2>/dev/null || {
        log "${YELLOW}  使用本地文件${NC}"
        cp "bot/telegram_bot.sh" "$INSTALL_DIR/bot/telegram_bot.sh" 2>/dev/null || true
    }
    
    # 设置执行权限
    chmod +x "$INSTALL_DIR"/*.sh 2>/dev/null || true
    chmod +x "$INSTALL_DIR"/modules/*.sh 2>/dev/null || true
    chmod +x "$INSTALL_DIR"/bot/*.sh 2>/dev/null || true
    
    log "${GREEN}✓ 文件下载完成${NC}\n"
}

# ===== 配置向导 =====
run_config_wizard() {
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${CYAN}配置向导${NC}"
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    # Telegram 配置
    echo -e "${YELLOW}1. Telegram 通知配置${NC}"
    echo "   提示: 访问 @BotFather 创建 Bot 获取 Token"
    echo ""
    
    read -p "启用 Telegram 通知? [Y/n]: " enable_tg
    enable_tg=${enable_tg:-Y}
    
    if [[ "$enable_tg" =~ ^[Yy]$ ]]; then
        read -p "Bot Token: " bot_token
        read -p "Chat ID: " chat_id
        
        # 测试连接
        if [[ -n "$bot_token" ]] && [[ -n "$chat_id" ]]; then
            echo "测试连接..."
            local test_response=$(curl -sS "https://api.telegram.org/bot${bot_token}/sendMessage" \
                -d "chat_id=${chat_id}" \
                -d "text=SnapSync 安装测试" 2>/dev/null || echo "")
            
            if [[ "$test_response" =~ "\"ok\":true" ]]; then
                log "${GREEN}✓ Telegram 测试成功${NC}"
            else
                log "${YELLOW}⚠ Telegram 测试失败，请检查配置${NC}"
            fi
        fi
    else
        bot_token=""
        chat_id=""
    fi
    
    echo ""
    
    # 远程备份配置
    echo -e "${YELLOW}2. 远程备份配置${NC}"
    echo "   提示: 需要 SSH 访问远程服务器"
    echo ""
    
    read -p "启用远程备份? [Y/n]: " enable_remote
    enable_remote=${enable_remote:-Y}
    
    if [[ "$enable_remote" =~ ^[Yy]$ ]]; then
        read -p "远程服务器地址: " remote_host
        read -p "远程用户名 [root]: " remote_user
        remote_user=${remote_user:-root}
        read -p "SSH 端口 [22]: " remote_port
        remote_port=${remote_port:-22}
        read -p "远程备份路径 [/backups]: " remote_path
        remote_path=${remote_path:-/backups}
        
        # SSH 密钥设置
        setup_ssh_key "$remote_user" "$remote_host" "$remote_port"
    else
        remote_host=""
        remote_user="root"
        remote_port="22"
        remote_path="/backups"
    fi
    
    echo ""
    
    # 本地配置
    echo -e "${YELLOW}3. 本地备份配置${NC}"
    read -p "本地备份目录 [/backups]: " backup_dir
    backup_dir=${backup_dir:-/backups}
    
    read -p "压缩级别 (1-9) [6]: " compression
    compression=${compression:-6}
    
    read -p "保留快照数量 [5]: " keep_count
    keep_count=${keep_count:-5}
    
    echo ""
    
    # 定时任务
    echo -e "${YELLOW}4. 定时任务配置${NC}"
    read -p "启用自动备份? [Y/n]: " enable_auto
    enable_auto=${enable_auto:-Y}
    
    if [[ "$enable_auto" =~ ^[Yy]$ ]]; then
        read -p "备份间隔 (天) [7]: " interval
        interval=${interval:-7}
        read -p "备份时间 [03:00]: " backup_time
        backup_time=${backup_time:-03:00}
    else
        interval="7"
        backup_time="03:00"
    fi
    
    echo ""
    
    # 生成配置文件
    generate_config "$enable_tg" "$bot_token" "$chat_id" \
                    "$enable_remote" "$remote_host" "$remote_user" "$remote_port" "$remote_path" \
                    "$backup_dir" "$compression" "$keep_count" \
                    "$enable_auto" "$interval" "$backup_time"
}

# SSH 密钥设置
setup_ssh_key() {
    local user="$1"
    local host="$2"
    local port="$3"
    
    local ssh_key="/root/.ssh/id_ed25519"
    
    echo ""
    if [[ ! -f "$ssh_key" ]]; then
        echo "生成 SSH 密钥..."
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
        ssh-keygen -t ed25519 -N "" -f "$ssh_key" -q
        log "${GREEN}✓ SSH 密钥已生成${NC}"
    else
        log "${GREEN}✓ SSH 密钥已存在${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}请将以下公钥添加到远程服务器:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    cat "${ssh_key}.pub"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}添加方法:${NC}"
    echo "1. SSH 到远程服务器: ssh $user@$host -p $port"
    echo "2. 执行命令:"
    echo "   mkdir -p ~/.ssh && chmod 700 ~/.ssh"
    echo "   echo '$(cat ${ssh_key}.pub)' >> ~/.ssh/authorized_keys"
    echo "   chmod 600 ~/.ssh/authorized_keys"
    echo ""
    
    read -p "已添加公钥? [Y/n]: " key_added
    if [[ ! "$key_added" =~ ^[Nn]$ ]]; then
        echo "测试 SSH 连接..."
        if ssh -i "$ssh_key" -p "$port" -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
            "$user@$host" "echo 'SSH 测试成功'" &>/dev/null; then
            log "${GREEN}✓ SSH 连接测试成功${NC}"
        else
            log "${YELLOW}⚠ SSH 连接测试失败，请检查配置${NC}"
        fi
    fi
}

# 生成配置文件
generate_config() {
    local enable_tg="$1"
    local bot_token="$2"
    local chat_id="$3"
    local enable_remote="$4"
    local remote_host="$5"
    local remote_user="$6"
    local remote_port="$7"
    local remote_path="$8"
    local backup_dir="$9"
    local compression="${10}"
    local keep_count="${11}"
    local enable_auto="${12}"
    local interval="${13}"
    local backup_time="${14}"
    
    cat > "$CONFIG_DIR/config.conf" << EOF
#!/bin/bash
# SnapSync v3.0 配置文件
# 生成时间: $(date '+%F %T')
# 主机: $(hostname)

# ===== Telegram 配置 =====
TELEGRAM_ENABLED="${enable_tg}"
TELEGRAM_BOT_TOKEN="${bot_token}"
TELEGRAM_CHAT_ID="${chat_id}"

# ===== 远程备份配置 =====
REMOTE_ENABLED="${enable_remote}"
REMOTE_HOST="${remote_host}"
REMOTE_USER="${remote_user}"
REMOTE_PORT="${remote_port}"
REMOTE_PATH="${remote_path}"
REMOTE_KEEP_DAYS="30"

# ===== 本地备份配置 =====
BACKUP_DIR="${backup_dir}"
COMPRESSION_LEVEL="${compression}"
PARALLEL_THREADS="auto"
LOCAL_KEEP_COUNT="${keep_count}"

# ===== 定时任务配置 =====
AUTO_BACKUP_ENABLED="${enable_auto}"
BACKUP_INTERVAL_DAYS="${interval}"
BACKUP_TIME="${backup_time}"

# ===== 高级配置 =====
ENABLE_ACL="true"
ENABLE_XATTR="true"
ENABLE_VERIFICATION="true"
DISK_THRESHOLD="90"
MEMORY_THRESHOLD="85"

# ===== 系统信息 =====
HOSTNAME="$(hostname)"
INSTALL_DATE="$(date '+%F %T')"
INSTALL_VERSION="3.0"
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
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/snapsync/modules/backup.sh
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # 备份定时器
    source "$CONFIG_DIR/config.conf"
    cat > /etc/systemd/system/snapsync-backup.timer << EOF
[Unit]
Description=SnapSync Automatic Backup Timer
Requires=snapsync-backup.service

[Timer]
OnCalendar=*-*-* ${BACKUP_TIME}:00
Persistent=true
RandomizedDelaySec=30min

[Install]
WantedBy=timers.target
EOF

    # Bot 服务
    cat > /etc/systemd/system/snapsync-bot.service << 'EOF'
[Unit]
Description=SnapSync Telegram Bot
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/snapsync/bot/telegram_bot.sh
Restart=always
RestartSec=10
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载 systemd
    systemctl daemon-reload
    
    # 启用服务
    if [[ "${AUTO_BACKUP_ENABLED:-}" =~ ^[Yy]|true$ ]]; then
        systemctl enable snapsync-backup.timer &>/dev/null
        systemctl start snapsync-backup.timer &>/dev/null
        log "${GREEN}  ✓ 自动备份已启用${NC}"
    fi
    
    if [[ "${TELEGRAM_ENABLED:-}" =~ ^[Yy]|true$ ]]; then
        systemctl enable snapsync-bot.service &>/dev/null
        systemctl start snapsync-bot.service &>/dev/null
        log "${GREEN}  ✓ Telegram Bot 已启动${NC}"
    fi
    
    log "${GREEN}✓ 系统服务设置完成${NC}\n"
}

# ===== 创建命令快捷方式 =====
create_shortcuts() {
    log "${CYAN}创建命令快捷方式...${NC}"
    
    # 创建主命令
    ln -sf "$INSTALL_DIR/snapsync.sh" /usr/local/bin/snapsync
    
    # 创建快捷命令
    cat > /usr/local/bin/snapsync-backup << 'EOF'
#!/bin/bash
/opt/snapsync/modules/backup.sh "$@"
EOF
    chmod +x /usr/local/bin/snapsync-backup
    
    cat > /usr/local/bin/snapsync-restore << 'EOF'
#!/bin/bash
/opt/snapsync/modules/restore.sh "$@"
EOF
    chmod +x /usr/local/bin/snapsync-restore
    
    log "${GREEN}✓ 命令快捷方式已创建${NC}\n"
}

# ===== 完成安装 =====
finish_installation() {
    log "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${GREEN}✓ SnapSync v3.0 安装完成！${NC}"
    log "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    echo -e "${CYAN}安装信息:${NC}"
    echo -e "  程序目录: ${INSTALL_DIR}"
    echo -e "  配置文件: ${CONFIG_DIR}/config.conf"
    echo -e "  日志目录: ${LOG_DIR}"
    echo -e "  备份目录: ${BACKUP_DIR}"
    echo ""
    
    echo -e "${CYAN}可用命令:${NC}"
    echo -e "  ${GREEN}snapsync${NC}         - 打开管理控制台"
    echo -e "  ${GREEN}snapsync-backup${NC}  - 立即创建快照"
    echo -e "  ${GREEN}snapsync-restore${NC} - 恢复系统快照"
    echo ""
    
    echo -e "${CYAN}系统服务:${NC}"
    if [[ "${AUTO_BACKUP_ENABLED:-}" =~ ^[Yy]|true$ ]]; then
        local next_backup=$(systemctl list-timers snapsync-backup.timer 2>/dev/null | awk 'NR==2 {print $1" "$2}' || echo "N/A")
        echo -e "  ${GREEN}✓${NC} 自动备份已启用"
        echo -e "    下次运行: ${next_backup}"
    else
        echo -e "  ${YELLOW}○${NC} 自动备份未启用"
    fi
    
    if [[ "${TELEGRAM_ENABLED:-}" =~ ^[Yy]|true$ ]]; then
        echo -e "  ${GREEN}✓${NC} Telegram Bot 已启动"
    else
        echo -e "  ${YELLOW}○${NC} Telegram Bot 未启用"
    fi
    echo ""
    
    echo -e "${CYAN}快速开始:${NC}"
    echo -e "  1. 运行 '${GREEN}snapsync${NC}' 打开控制台"
    echo -e "  2. 选择 '创建系统快照' 进行首次备份"
    echo -e "  3. 查看 '${CONFIG_DIR}/config.conf' 修改配置"
    echo ""
    
    echo -e "${YELLOW}提示: 建议在测试环境验证恢复功能${NC}\n"
    
    read -p "是否立即打开控制台? [Y/n]: " open_console
    if [[ ! "$open_console" =~ ^[Nn]$ ]]; then
        snapsync
    fi
}

# ===== 主程序 =====
main() {
    # 创建日志目录
    mkdir -p "$LOG_DIR"
    
    # 显示横幅
    show_banner
    
    # 检测系统
    detect_system
    
    # 安装依赖
    install_dependencies
    
    # 创建目录
    create_directories
    
    # 下载文件
    download_files
    
    # 配置向导
    run_config_wizard
    
    # 设置服务
    setup_systemd_services
    
    # 创建快捷方式
    create_shortcuts
    
    # 完成安装
    finish_installation
}

# 运行主程序
main "$@"
