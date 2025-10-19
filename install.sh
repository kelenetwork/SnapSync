#!/bin/bash

# SnapSync v3.0 安装脚本 - 增强版（带配置向导）

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

pause() {
    echo ""
    read -p "按 Enter 继续..."
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
    
    if command -v "$pkg" &>/dev/null; then
        log "  ${GREEN}✓ $pkg${NC} (已存在)"
        return 0
    fi
    
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
    
    for pkg_name in "${pkg_map[@]}"; do
        install_package "$pkg_name" "no" || true
    done
    
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
    
    mkdir -p "$INSTALL_DIR"/{modules,bot}
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$DEFAULT_BACKUP_DIR/system_snapshots"
    
    if [[ -f "$SCRIPT_DIR/snapsync.sh" ]]; then
        cp "$SCRIPT_DIR/snapsync.sh" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/snapsync.sh"
        log "${GREEN}✓ 主脚本${NC}"
    else
        log "${RED}✗ 未找到 snapsync.sh${NC}"
    fi
    
    for module in backup.sh restore.sh config.sh; do
        if [[ -f "$SCRIPT_DIR/$module" ]]; then
            cp "$SCRIPT_DIR/$module" "$INSTALL_DIR/modules/"
            chmod +x "$INSTALL_DIR/modules/$module"
            log "${GREEN}✓ $module${NC}"
        else
            log "${YELLOW}⚠ 未找到 $module${NC}"
        fi
    done
    
    if [[ -f "$SCRIPT_DIR/telegram_bot.sh" ]]; then
        cp "$SCRIPT_DIR/telegram_bot.sh" "$INSTALL_DIR/bot/"
        chmod +x "$INSTALL_DIR/bot/telegram_bot.sh"
        log "${GREEN}✓ Bot脚本${NC}"
    else
        log "${YELLOW}⚠ 未找到 telegram_bot.sh${NC}"
    fi
    
    if [[ -f "$SCRIPT_DIR/telegram-test.sh" ]]; then
        rm -f /usr/local/bin/telegram-test
        cp "$SCRIPT_DIR/telegram-test.sh" "/usr/local/bin/telegram-test"
        chmod +x "/usr/local/bin/telegram-test"
        log "${GREEN}✓ 诊断工具${NC}"
    else
        log "${YELLOW}⚠ 未找到 telegram-test.sh${NC}"
    fi
    
    log "\n${GREEN}✓ 文件安装完成${NC}\n"
}

# ===== 配置向导 =====
config_wizard() {
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${CYAN}配置向导${NC}"
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    # 默认配置
    local BACKUP_DIR="/backups"
    local TELEGRAM_ENABLED="false"
    local TELEGRAM_BOT_TOKEN=""
    local TELEGRAM_CHAT_ID=""
    local REMOTE_ENABLED="false"
    local REMOTE_HOST=""
    local REMOTE_USER="root"
    local REMOTE_PORT="22"
    local REMOTE_PATH="/backups"
    local REMOTE_KEEP_DAYS="30"
    local LOCAL_KEEP_COUNT="5"
    local AUTO_BACKUP_ENABLED="false"
    local BACKUP_INTERVAL_DAYS="7"
    local BACKUP_TIME="03:00"
    
    # 1. Telegram 配置
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}1. Telegram Bot 配置${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Telegram Bot 可以远程管理快照（可选）"
    echo ""
    read -p "是否启用 Telegram Bot? [y/N]: " enable_tg
    
    if [[ "$enable_tg" =~ ^[Yy]$ ]]; then
        TELEGRAM_ENABLED="true"
        
        echo ""
        echo -e "${CYAN}获取 Bot Token:${NC}"
        echo "  1. 在 Telegram 搜索 @BotFather"
        echo "  2. 发送 /newbot 创建新 Bot"
        echo "  3. 按提示设置名称"
        echo "  4. 复制获得的 Token"
        echo ""
        read -p "输入 Bot Token: " TELEGRAM_BOT_TOKEN
        
        if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
            echo ""
            echo -e "${CYAN}获取 Chat ID:${NC}"
            echo "  1. 向你的 Bot 发送任意消息（如 /start）"
            echo "  2. 访问以下网址（可在手机浏览器打开）:"
            echo -e "     ${GREEN}https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates${NC}"
            echo "  3. 在返回的 JSON 中找到: \"chat\":{\"id\":数字}"
            echo "  4. 复制这个数字"
            echo ""
            read -p "输入 Chat ID: " TELEGRAM_CHAT_ID
            
            if [[ -n "$TELEGRAM_CHAT_ID" ]]; then
                echo ""
                log "${GREEN}✓ Telegram 配置完成${NC}"
            else
                log "${YELLOW}⚠ 未输入 Chat ID，Telegram 功能将不可用${NC}"
                TELEGRAM_ENABLED="false"
            fi
        else
            log "${YELLOW}⚠ 未输入 Bot Token，Telegram 功能将不可用${NC}"
            TELEGRAM_ENABLED="false"
        fi
    else
        log "${YELLOW}⚠ 跳过 Telegram 配置${NC}"
    fi
    
    # 2. 远程备份配置
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}2. 远程备份配置${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "可将快照自动上传到远程服务器（可选）"
    echo ""
    read -p "是否启用远程备份? [y/N]: " enable_remote
    
    if [[ "$enable_remote" =~ ^[Yy]$ ]]; then
        REMOTE_ENABLED="true"
        
        echo ""
        read -p "远程服务器地址 (如: 192.168.1.100): " REMOTE_HOST
        read -p "SSH 用户名 [root]: " input_user
        REMOTE_USER="${input_user:-root}"
        read -p "SSH 端口 [22]: " input_port
        REMOTE_PORT="${input_port:-22}"
        read -p "远程备份路径 [/backups]: " input_path
        REMOTE_PATH="${input_path:-/backups}"
        read -p "远程保留天数 [30]: " input_days
        REMOTE_KEEP_DAYS="${input_days:-30}"
        
        if [[ -n "$REMOTE_HOST" ]]; then
            # 生成 SSH 密钥
            if [[ ! -f /root/.ssh/id_ed25519 ]]; then
                echo ""
                log "${CYAN}生成 SSH 密钥...${NC}"
                mkdir -p /root/.ssh
                ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N "" -q
                chmod 700 /root/.ssh
                chmod 600 /root/.ssh/id_ed25519
                log "${GREEN}✓ SSH 密钥已生成${NC}"
            fi
            
            echo ""
            log "${YELLOW}重要: 请将以下公钥添加到远程服务器${NC}"
            echo ""
            echo -e "${CYAN}公钥内容:${NC}"
            cat /root/.ssh/id_ed25519.pub
            echo ""
            echo -e "${CYAN}在远程服务器 (${REMOTE_USER}@${REMOTE_HOST}) 执行:${NC}"
            echo "  mkdir -p ~/.ssh"
            echo "  echo '$(cat /root/.ssh/id_ed25519.pub)' >> ~/.ssh/authorized_keys"
            echo "  chmod 700 ~/.ssh"
            echo "  chmod 600 ~/.ssh/authorized_keys"
            echo ""
            
            pause
            
            # 测试连接
            echo ""
            log "${CYAN}测试远程连接...${NC}"
            if ssh -i /root/.ssh/id_ed25519 \
                   -o StrictHostKeyChecking=no \
                   -o ConnectTimeout=10 \
                   -p "$REMOTE_PORT" \
                   "${REMOTE_USER}@${REMOTE_HOST}" \
                   "echo ok" &>/dev/null; then
                log "${GREEN}✓ 远程连接测试成功${NC}"
            else
                log "${RED}✗ 远程连接测试失败${NC}"
                log "${YELLOW}请确保公钥已正确添加到远程服务器${NC}"
                echo ""
                read -p "是否继续安装? [y/N]: " continue_install
                if [[ ! "$continue_install" =~ ^[Yy]$ ]]; then
                    log "${RED}安装已取消${NC}"
                    exit 1
                fi
            fi
        else
            log "${YELLOW}⚠ 未输入服务器地址，远程备份将不可用${NC}"
            REMOTE_ENABLED="false"
        fi
    else
        log "${YELLOW}⚠ 跳过远程备份配置${NC}"
    fi
    
    # 3. 本地备份策略
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}3. 本地备份策略${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    read -p "本地备份目录 [/backups]: " input_backup_dir
    BACKUP_DIR="${input_backup_dir:-/backups}"
    
    read -p "本地保留快照数量 [5]: " input_keep
    LOCAL_KEEP_COUNT="${input_keep:-5}"
    
    log "${GREEN}✓ 本地策略: 保留最新 ${LOCAL_KEEP_COUNT} 个快照${NC}"
    
    # 4. 定时备份
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}4. 定时备份${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "可设置自动定时备份（可选）"
    echo ""
    read -p "是否启用定时备份? [y/N]: " enable_auto
    
    if [[ "$enable_auto" =~ ^[Yy]$ ]]; then
        AUTO_BACKUP_ENABLED="true"
        
        echo ""
        echo "定时模式:"
        echo "  1) 每天"
        echo "  2) 每周"
        echo "  3) 每月"
        echo ""
        read -p "选择 [1-3, 默认2]: " schedule_choice
        schedule_choice="${schedule_choice:-2}"
        
        case "$schedule_choice" in
            1)
                BACKUP_INTERVAL_DAYS="1"
                schedule_desc="每天"
                ;;
            2)
                BACKUP_INTERVAL_DAYS="7"
                schedule_desc="每周"
                ;;
            3)
                BACKUP_INTERVAL_DAYS="30"
                schedule_desc="每月"
                ;;
            *)
                BACKUP_INTERVAL_DAYS="7"
                schedule_desc="每周"
                ;;
        esac
        
        read -p "备份时间 (HH:MM格式, 如 03:00) [03:00]: " input_time
        BACKUP_TIME="${input_time:-03:00}"
        
        log "${GREEN}✓ 定时备份: ${schedule_desc}，时间 ${BACKUP_TIME}${NC}"
    else
        log "${YELLOW}⚠ 跳过定时备份配置${NC}"
    fi
    
    # 保存配置
    echo ""
    log "${CYAN}保存配置...${NC}"
    
    cat > "$CONFIG_DIR/config.conf" << EOF
#!/bin/bash

# SnapSync v3.0 配置文件
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

# ===== Telegram 配置 =====
TELEGRAM_ENABLED="$TELEGRAM_ENABLED"
TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"

# ===== 远程备份配置 =====
REMOTE_ENABLED="$REMOTE_ENABLED"
REMOTE_HOST="$REMOTE_HOST"
REMOTE_USER="$REMOTE_USER"
REMOTE_PORT="$REMOTE_PORT"
REMOTE_PATH="$REMOTE_PATH"
REMOTE_KEEP_DAYS="$REMOTE_KEEP_DAYS"

# ===== 本地备份配置 =====
BACKUP_DIR="$BACKUP_DIR"
COMPRESSION_LEVEL="6"
PARALLEL_THREADS="auto"
LOCAL_KEEP_COUNT="$LOCAL_KEEP_COUNT"

# ===== 定时任务配置 =====
AUTO_BACKUP_ENABLED="$AUTO_BACKUP_ENABLED"
BACKUP_INTERVAL_DAYS="$BACKUP_INTERVAL_DAYS"
BACKUP_TIME="$BACKUP_TIME"

# ===== 高级配置 =====
ENABLE_ACL="true"
ENABLE_XATTR="true"
ENABLE_VERIFICATION="true"
DISK_THRESHOLD="90"
HOSTNAME="$(hostname)"
EOF
    
    chmod 600 "$CONFIG_DIR/config.conf"
    log "${GREEN}✓ 配置已保存到: $CONFIG_DIR/config.conf${NC}\n"
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
    
    # 加载配置
    source "$CONFIG_DIR/config.conf"
    
    # 根据配置创建定时器
    local timer_schedule="weekly"
    case "$BACKUP_INTERVAL_DAYS" in
        1) timer_schedule="daily" ;;
        7) timer_schedule="weekly" ;;
        30) timer_schedule="monthly" ;;
    esac
    
    cat > /etc/systemd/system/snapsync-backup.timer << EOF
[Unit]
Description=SnapSync Backup Timer

[Timer]
OnCalendar=$timer_schedule
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    systemctl daemon-reload
    log "${GREEN}✓ 系统服务已创建${NC}\n"
    
    # 启动服务
    if [[ "$TELEGRAM_ENABLED" == "true" ]]; then
        log "${CYAN}启动 Telegram Bot...${NC}"
        systemctl enable snapsync-bot &>/dev/null
        systemctl start snapsync-bot &>/dev/null
        
        if systemctl is-active snapsync-bot &>/dev/null; then
            log "${GREEN}✓ Bot 服务已启动${NC}"
        else
            log "${YELLOW}⚠ Bot 服务启动失败，请检查配置${NC}"
        fi
    fi
    
    if [[ "$AUTO_BACKUP_ENABLED" == "true" ]]; then
        log "${CYAN}启用定时备份...${NC}"
        systemctl enable snapsync-backup.timer &>/dev/null
        systemctl start snapsync-backup.timer &>/dev/null
        log "${GREEN}✓ 定时备份已启用${NC}"
    fi
    
    echo ""
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
    
    source "$CONFIG_DIR/config.conf"
    
    echo -e "${YELLOW}配置摘要:${NC}"
    echo -e "  • 备份目录: ${CYAN}${BACKUP_DIR}${NC}"
    echo -e "  • 本地保留: ${CYAN}${LOCAL_KEEP_COUNT}${NC} 个快照"
    echo -e "  • Telegram: ${CYAN}${TELEGRAM_ENABLED}${NC}"
    echo -e "  • 远程备份: ${CYAN}${REMOTE_ENABLED}${NC}"
    echo -e "  • 定时备份: ${CYAN}${AUTO_BACKUP_ENABLED}${NC}"
    echo ""
    
    echo -e "${YELLOW}快速开始:${NC}"
    echo -e "  ${GREEN}1.${NC} 启动控制台: ${CYAN}sudo snapsync${NC}"
    echo -e "  ${GREEN}2.${NC} 创建快照:   ${CYAN}sudo snapsync-backup${NC}"
    echo -e "  ${GREEN}3.${NC} 恢复快照:   ${CYAN}sudo snapsync-restore${NC}"
    
    if [[ "$TELEGRAM_ENABLED" == "true" ]]; then
        echo -e "  ${GREEN}4.${NC} 测试 Bot:   ${CYAN}在 Telegram 发送 /start${NC}"
        echo -e "  ${GREEN}5.${NC} 诊断工具:   ${CYAN}sudo telegram-test${NC}"
    fi
    
    echo ""
    
    if [[ "$TELEGRAM_ENABLED" == "true" ]]; then
        echo -e "${YELLOW}Telegram Bot 提示:${NC}"
        echo -e "  • 向你的 Bot 发送 ${CYAN}/start${NC} 呼出菜单"
        echo -e "  • 如果无响应，运行: ${CYAN}sudo telegram-test${NC}"
        echo -e "  • 查看 Bot 日志: ${CYAN}sudo tail -f /var/log/snapsync/bot.log${NC}"
        echo ""
    fi
    
    if [[ "$REMOTE_ENABLED" == "true" ]]; then
        echo -e "${YELLOW}远程备份提示:${NC}"
        echo -e "  • 确保远程服务器已添加 SSH 公钥"
        echo -e "  • 测试连接: ${CYAN}ssh -i /root/.ssh/id_ed25519 -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST}${NC}"
        echo ""
    fi
    
    if [[ "$AUTO_BACKUP_ENABLED" == "true" ]]; then
        echo -e "${YELLOW}定时备份:${NC}"
        echo -e "  • 查看状态: ${CYAN}systemctl status snapsync-backup.timer${NC}"
        echo -e "  • 查看计划: ${CYAN}systemctl list-timers snapsync-backup.timer${NC}"
        echo ""
    fi
    
    echo -e "${GREEN}SnapSync 安装成功！祝使用愉快！${NC}"
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
        echo ""
        echo "检测到现有安装，请选择："
        echo "  1) 覆盖安装（保留现有配置）"
        echo "  2) 重新配置（会覆盖配置文件）"
        echo "  3) 取消安装"
        echo ""
        read -p "请选择 [1-3]: " reinstall_choice
        
        case "$reinstall_choice" in
            1)
                log "${CYAN}覆盖安装模式（保留配置）${NC}"
                SKIP_CONFIG=true
                ;;
            2)
                log "${CYAN}重新配置模式${NC}"
                SKIP_CONFIG=false
                ;;
            3)
                log "${GREEN}已取消${NC}"
                exit 0
                ;;
            *)
                log "${RED}无效选择${NC}"
                exit 1
                ;;
        esac
    else
        SKIP_CONFIG=false
    fi
    
    detect_system
    install_dependencies
    install_files
    
    if [[ "$SKIP_CONFIG" != true ]]; then
        config_wizard
    else
        log "${YELLOW}跳过配置向导（保留现有配置）${NC}\n"
    fi
    
    create_services
    create_shortcuts
    finish_installation
}

main "$@"
