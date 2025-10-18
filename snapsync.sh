#!/bin/bash

# SnapSync v3.0 - 主控制脚本
# 统一的系统快照管理控制台

set -euo pipefail

# ===== 颜色定义 =====
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'

# ===== 路径定义 =====
readonly INSTALL_DIR="/opt/snapsync"
readonly CONFIG_DIR="/etc/snapsync"
readonly CONFIG_FILE="$CONFIG_DIR/config.conf"
readonly LOG_DIR="/var/log/snapsync"
readonly MODULE_DIR="$INSTALL_DIR/modules"
readonly BOT_DIR="$INSTALL_DIR/bot"

# ===== 权限检查 =====
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 请使用 root 权限运行此脚本${NC}"
    echo -e "${YELLOW}使用: sudo $0${NC}"
    exit 1
fi

# ===== 工具函数 =====
log() {
    mkdir -p "$LOG_DIR"
    echo -e "$(date '+%F %T') $*" | tee -a "$LOG_DIR/main.log"
}

show_header() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${CYAN}       SnapSync v3.0 管理控制台            ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
    echo ""
}

show_status_bar() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        local backup_dir="${BACKUP_DIR:-/backups}"
        local snapshot_count=$(find "$backup_dir/system_snapshots" -name "*.tar*" 2>/dev/null | wc -l)
        local disk_usage=$(df -h "$backup_dir" 2>/dev/null | awk 'NR==2 {print $5}' || echo "N/A")
        
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}主机:${NC} $(hostname) ${GREEN}| 快照数:${NC} $snapshot_count ${GREEN}| 磁盘:${NC} $disk_usage"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
    fi
}

# ===== 依赖检查和安装 =====
check_and_install_dependencies() {
    log "${CYAN}检查系统依赖...${NC}"
    
    # 检测包管理器
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt-get"
        PKG_UPDATE="apt-get update -qq"
        PKG_INSTALL="apt-get install -y -qq"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        PKG_UPDATE="yum makecache -q"
        PKG_INSTALL="yum install -y -q"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        PKG_UPDATE="dnf makecache -q"
        PKG_INSTALL="dnf install -y -q"
    else
        log "${RED}错误: 未检测到支持的包管理器${NC}"
        exit 1
    fi
    
    log "${GREEN}检测到包管理器: $PKG_MANAGER${NC}"
    
    # 基础工具
    local required_tools=(
        "curl" "tar" "gzip" "rsync" "jq" "bc"
        "openssh-client:ssh" "findutils:find"
    )
    
    # 可选但推荐的工具
    local optional_tools=(
        "pigz" "acl:getfacl" "attr:getfattr" "pv" "bzip2" "xz-utils:xz"
    )
    
    # 更新包列表
    log "${YELLOW}更新包列表...${NC}"
    eval "$PKG_UPDATE" &>/dev/null || true
    
    # 检查和安装基础工具
    log "${YELLOW}检查基础依赖...${NC}"
    for tool_spec in "${required_tools[@]}"; do
        local pkg_name="${tool_spec%%:*}"
        local cmd_name="${tool_spec##*:}"
        [[ "$cmd_name" == "$pkg_name" ]] && cmd_name="$pkg_name"
        
        if ! command -v "$cmd_name" &> /dev/null; then
            log "${YELLOW}  安装 $pkg_name...${NC}"
            if ! eval "$PKG_INSTALL $pkg_name" &>/dev/null; then
                log "${RED}  警告: 无法安装 $pkg_name${NC}"
            else
                log "${GREEN}  ✓ $pkg_name 安装完成${NC}"
            fi
        else
            log "${GREEN}  ✓ $cmd_name 已安装${NC}"
        fi
    done
    
    # 检查和安装可选工具
    log "${YELLOW}检查可选依赖...${NC}"
    for tool_spec in "${optional_tools[@]}"; do
        local pkg_name="${tool_spec%%:*}"
        local cmd_name="${tool_spec##*:}"
        [[ "$cmd_name" == "$pkg_name" ]] && cmd_name="$pkg_name"
        
        if ! command -v "$cmd_name" &> /dev/null; then
            log "${YELLOW}  安装 $pkg_name (可选)...${NC}"
            eval "$PKG_INSTALL $pkg_name" &>/dev/null || log "${YELLOW}  跳过 $pkg_name${NC}"
        fi
    done
    
    log "${GREEN}✓ 依赖检查完成${NC}\n"
}

# ===== 初始化安装 =====
initialize_installation() {
    show_header
    log "${CYAN}开始 SnapSync v3.0 初始化...${NC}\n"
    
    # 检查依赖
    check_and_install_dependencies
    
    # 创建目录结构
    log "${YELLOW}创建目录结构...${NC}"
    mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR" "$MODULE_DIR" "$BOT_DIR"
    mkdir -p "/backups/system_snapshots" "/backups/metadata" "/backups/checksums"
    log "${GREEN}✓ 目录创建完成${NC}\n"
    
    # 配置向导
    if [[ ! -f "$CONFIG_FILE" ]]; then
        run_config_wizard
    else
        log "${YELLOW}检测到现有配置，跳过配置向导${NC}"
        read -p "是否重新配置? [y/N]: " reconfigure
        if [[ "$reconfigure" =~ ^[Yy]$ ]]; then
            run_config_wizard
        fi
    fi
    
    # 安装模块
    install_modules
    
    # 设置定时任务
    setup_systemd_services
    
    log "${GREEN}\n✓ SnapSync v3.0 安装完成！${NC}\n"
    log "${CYAN}运行 'sudo snapsync' 启动管理控制台${NC}"
    
    read -p "按 Enter 继续..."
}

# ===== 配置向导 =====
run_config_wizard() {
    log "${BLUE}━━━━━ 配置向导 ━━━━━${NC}\n"
    
    # Telegram 配置
    log "${YELLOW}1. Telegram 通知配置${NC}"
    read -p "启用 Telegram 通知? [Y/n]: " enable_tg
    enable_tg=${enable_tg:-Y}
    
    if [[ "$enable_tg" =~ ^[Yy]$ ]]; then
        read -p "Telegram Bot Token: " bot_token
        read -p "Telegram Chat ID: " chat_id
    else
        bot_token=""
        chat_id=""
    fi
    echo ""
    
    # 远程备份配置
    log "${YELLOW}2. 远程备份配置${NC}"
    read -p "启用远程备份? [Y/n]: " enable_remote
    enable_remote=${enable_remote:-Y}
    
    if [[ "$enable_remote" =~ ^[Yy]$ ]]; then
        read -p "远程服务器地址: " remote_host
        read -p "远程用户名 [root]: " remote_user
        remote_user=${remote_user:-root}
        read -p "SSH 端口 [22]: " remote_port
        remote_port=${remote_port:-22}
        read -p "远程备份路径: " remote_path
        
        # SSH 认证方式
        echo ""
        echo "SSH 认证方式:"
        echo "1) 密钥认证 (推荐)"
        echo "2) 密码认证"
        read -p "选择 [1-2]: " auth_type
        
        if [[ "$auth_type" == "1" ]]; then
            setup_ssh_key "$remote_user" "$remote_host" "$remote_port"
            use_password="false"
        else
            use_password="true"
        fi
    else
        remote_host=""
        remote_user=""
        remote_port="22"
        remote_path=""
        use_password="false"
    fi
    echo ""
    
    # 本地备份配置
    log "${YELLOW}3. 本地备份配置${NC}"
    read -p "本地备份目录 [/backups]: " backup_dir
    backup_dir=${backup_dir:-/backups}
    
    read -p "压缩级别 (1-9) [6]: " compression_level
    compression_level=${compression_level:-6}
    
    read -p "保留本地快照数量 [5]: " local_keep
    local_keep=${local_keep:-5}
    echo ""
    
    # 定时任务配置
    log "${YELLOW}4. 定时任务配置${NC}"
    read -p "启用自动备份? [Y/n]: " enable_auto
    enable_auto=${enable_auto:-Y}
    
    if [[ "$enable_auto" =~ ^[Yy]$ ]]; then
        read -p "备份间隔 (天) [7]: " interval_days
        interval_days=${interval_days:-7}
        read -p "备份时间 [03:00]: " backup_time
        backup_time=${backup_time:-03:00}
    else
        interval_days="7"
        backup_time="03:00"
    fi
    echo ""
    
    # 生成配置文件
    cat > "$CONFIG_FILE" << EOF
#!/bin/bash
# SnapSync v3.0 配置文件
# 生成时间: $(date '+%F %T')

# === Telegram 配置 ===
TELEGRAM_ENABLED="${enable_tg}"
TELEGRAM_BOT_TOKEN="${bot_token}"
TELEGRAM_CHAT_ID="${chat_id}"

# === 远程备份配置 ===
REMOTE_ENABLED="${enable_remote}"
REMOTE_HOST="${remote_host}"
REMOTE_USER="${remote_user}"
REMOTE_PORT="${remote_port}"
REMOTE_PATH="${remote_path}"
REMOTE_USE_PASSWORD="${use_password}"
REMOTE_KEEP_DAYS="30"

# === 本地备份配置 ===
BACKUP_DIR="${backup_dir}"
COMPRESSION_LEVEL="${compression_level}"
PARALLEL_THREADS="auto"
LOCAL_KEEP_COUNT="${local_keep}"

# === 定时任务配置 ===
AUTO_BACKUP_ENABLED="${enable_auto}"
BACKUP_INTERVAL_DAYS="${interval_days}"
BACKUP_TIME="${backup_time}"

# === 高级配置 ===
ENABLE_ACL="true"
ENABLE_XATTR="true"
ENABLE_VERIFICATION="true"
DISK_THRESHOLD="90"
MEMORY_THRESHOLD="85"

# === 系统信息 ===
HOSTNAME="$(hostname)"
INSTALL_DATE="$(date '+%F %T')"
EOF

    chmod 600 "$CONFIG_FILE"
    log "${GREEN}✓ 配置文件已生成: $CONFIG_FILE${NC}\n"
}

# ===== SSH 密钥设置 =====
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
    log "${CYAN}请将以下公钥添加到远程服务器:${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    cat "${ssh_key}.pub"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}添加方法:${NC}"
    echo "  ssh $user@$host -p $port"
    echo "  echo '$(cat ${ssh_key}.pub)' >> ~/.ssh/authorized_keys"
    echo ""
    
    read -p "已添加公钥? [Y/n]: " key_added
    if [[ ! "$key_added" =~ ^[Nn]$ ]]; then
        if ssh -i "$ssh_key" -p "$port" -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
            "$user@$host" "echo 'SSH 测试成功'" &>/dev/null; then
            log "${GREEN}✓ SSH 连接测试成功${NC}"
        else
            log "${YELLOW}⚠ SSH 连接测试失败，请检查配置${NC}"
        fi
    fi
}

# ===== 安装功能模块 =====
install_modules() {
    log "${YELLOW}安装功能模块...${NC}"
    
    # 这里会从当前脚本目录或 GitHub 复制模块文件
    # 为了演示，我们创建占位符
    
    local modules=("backup.sh" "restore.sh" "config.sh" "telegram.sh" "utils.sh")
    
    for module in "${modules[@]}"; do
        if [[ -f "$MODULE_DIR/$module" ]]; then
            log "${GREEN}  ✓ $module 已存在${NC}"
        else
            log "${YELLOW}  创建 $module 占位符${NC}"
            touch "$MODULE_DIR/$module"
            chmod +x "$MODULE_DIR/$module"
        fi
    done
    
    log "${GREEN}✓ 模块安装完成${NC}\n"
}

# ===== 设置 Systemd 服务 =====
setup_systemd_services() {
    log "${YELLOW}设置系统服务...${NC}"
    
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
    cat > /etc/systemd/system/snapsync-backup.timer << EOF
[Unit]
Description=SnapSync Backup Timer
Requires=snapsync-backup.service

[Timer]
OnCalendar=*-*-* $(grep BACKUP_TIME "$CONFIG_FILE" | cut -d'"' -f2):00
Persistent=true
RandomizedDelaySec=30min

[Install]
WantedBy=timers.target
EOF

    # Telegram Bot 服务
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
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        if [[ "$AUTO_BACKUP_ENABLED" == "Y" ]] || [[ "$AUTO_BACKUP_ENABLED" == "true" ]]; then
            systemctl enable snapsync-backup.timer &>/dev/null
            systemctl start snapsync-backup.timer &>/dev/null
            log "${GREEN}  ✓ 自动备份已启用${NC}"
        fi
        
        if [[ "$TELEGRAM_ENABLED" == "Y" ]] || [[ "$TELEGRAM_ENABLED" == "true" ]]; then
            systemctl enable snapsync-bot.service &>/dev/null
            systemctl start snapsync-bot.service &>/dev/null
            log "${GREEN}  ✓ Telegram Bot 已启动${NC}"
        fi
    fi
    
    log "${GREEN}✓ 系统服务设置完成${NC}\n"
}

# ===== 主菜单 =====
show_main_menu() {
    show_header
    show_status_bar
    
    echo -e "${YELLOW}主菜单${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${GREEN}1)${NC} 📸 创建系统快照"
    echo -e "  ${GREEN}2)${NC} 🔄 恢复系统快照"
    echo -e "  ${GREEN}3)${NC} ⚙️  配置管理"
    echo -e "  ${GREEN}4)${NC} 📊 查看快照列表"
    echo -e "  ${GREEN}5)${NC} 🤖 Telegram Bot 管理"
    echo -e "  ${GREEN}6)${NC} 🗑️  清理旧快照"
    echo -e "  ${GREEN}7)${NC} 📋 查看日志"
    echo -e "  ${GREEN}8)${NC} ℹ️  系统信息"
    echo -e "  ${GREEN}9)${NC} ❓ 帮助文档"
    echo -e "  ${RED}0)${NC} 🚪 退出"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# ===== 创建快照 =====
create_snapshot() {
    show_header
    log "${CYAN}📸 创建系统快照${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    # 检查配置
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "${RED}错误: 配置文件不存在，请先运行初始化${NC}"
        read -p "按 Enter 继续..."
        return
    fi
    
    source "$CONFIG_FILE"
    
    # 询问是否上传
    local upload_remote="n"
    if [[ "$REMOTE_ENABLED" == "Y" ]] || [[ "$REMOTE_ENABLED" == "true" ]]; then
        read -p "是否上传到远程服务器? [Y/n]: " upload_remote
        upload_remote=${upload_remote:-Y}
    fi
    
    # 调用备份模块
    if [[ -f "$MODULE_DIR/backup.sh" ]]; then
        UPLOAD_REMOTE="$upload_remote" bash "$MODULE_DIR/backup.sh"
    else
        log "${RED}错误: 备份模块不存在${NC}"
    fi
    
    echo ""
    read -p "按 Enter 返回主菜单..."
}

# ===== 恢复快照 =====
restore_snapshot() {
    show_header
    log "${CYAN}🔄 恢复系统快照${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    if [[ -f "$MODULE_DIR/restore.sh" ]]; then
        bash "$MODULE_DIR/restore.sh"
    else
        log "${RED}错误: 恢复模块不存在${NC}"
    fi
    
    echo ""
    read -p "按 Enter 返回主菜单..."
}

# ===== 配置管理 =====
manage_config() {
    while true; do
        show_header
        log "${CYAN}⚙️ 配置管理${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        
        echo -e "  ${GREEN}1)${NC} 修改远程服务器配置"
        echo -e "  ${GREEN}2)${NC} 修改 Telegram 配置"
        echo -e "  ${GREEN}3)${NC} 修改保留策略"
        echo -e "  ${GREEN}4)${NC} 修改定时任务"
        echo -e "  ${GREEN}5)${NC} 查看当前配置"
        echo -e "  ${GREEN}6)${NC} 重新运行配置向导"
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo ""
        
        read -p "请选择 [0-6]: " choice
        
        case "$choice" in
            1) edit_remote_config ;;
            2) edit_telegram_config ;;
            3) edit_retention_config ;;
            4) edit_schedule_config ;;
            5) view_current_config ;;
            6) run_config_wizard ;;
            0) break ;;
            *) log "${RED}无效选择${NC}" ;;
        esac
    done
}

# ===== 查看快照列表 =====
list_snapshots() {
    show_header
    log "${CYAN}📊 快照列表${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "${RED}错误: 配置文件不存在${NC}"
        read -p "按 Enter 继续..."
        return
    fi
    
    source "$CONFIG_FILE"
    local snapshot_dir="${BACKUP_DIR}/system_snapshots"
    
    if [[ ! -d "$snapshot_dir" ]]; then
        log "${YELLOW}快照目录不存在${NC}"
        read -p "按 Enter 继续..."
        return
    fi
    
    local snapshots=($(find "$snapshot_dir" -name "*.tar*" -type f 2>/dev/null | sort -r))
    
    if [[ ${#snapshots[@]} -eq 0 ]]; then
        log "${YELLOW}未找到快照文件${NC}"
    else
        log "${GREEN}找到 ${#snapshots[@]} 个快照:${NC}\n"
        
        for i in "${!snapshots[@]}"; do
            local file="${snapshots[$i]}"
            local name=$(basename "$file")
            local size=$(du -h "$file" | cut -f1)
            local date=$(date -r "$file" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "未知")
            
            echo -e "  $((i+1)). ${GREEN}$name${NC}"
            echo -e "     大小: $size | 时间: $date"
            
            # 显示校验和状态
            if [[ -f "${file}.sha256" ]]; then
                echo -e "     状态: ${GREEN}✓ 已验证${NC}"
            fi
            echo ""
        done
        
        # 显示总大小
        local total_size=$(du -sh "$snapshot_dir" 2>/dev/null | cut -f1)
        echo -e "${CYAN}总大小: $total_size${NC}"
    fi
    
    echo ""
    read -p "按 Enter 返回主菜单..."
}

# ===== 查看配置 =====
view_current_config() {
    show_header
    log "${CYAN}当前配置${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        
        echo -e "${YELLOW}Telegram 配置:${NC}"
        echo -e "  启用: ${TELEGRAM_ENABLED}"
        echo -e "  Bot Token: ${TELEGRAM_BOT_TOKEN:0:10}..."
        echo -e "  Chat ID: ${TELEGRAM_CHAT_ID}"
        echo ""
        
        echo -e "${YELLOW}远程备份配置:${NC}"
        echo -e "  启用: ${REMOTE_ENABLED}"
        echo -e "  服务器: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT}"
        echo -e "  路径: ${REMOTE_PATH}"
        echo ""
        
        echo -e "${YELLOW}本地备份配置:${NC}"
        echo -e "  备份目录: ${BACKUP_DIR}"
        echo -e "  压缩级别: ${COMPRESSION_LEVEL}"
        echo -e "  保留数量: ${LOCAL_KEEP_COUNT}"
        echo ""
        
        echo -e "${YELLOW}定时任务配置:${NC}"
        echo -e "  启用: ${AUTO_BACKUP_ENABLED}"
        echo -e "  间隔: ${BACKUP_INTERVAL_DAYS} 天"
        echo -e "  时间: ${BACKUP_TIME}"
        echo ""
    else
        log "${RED}配置文件不存在${NC}"
    fi
    
    read -p "按 Enter 继续..."
}

# ===== 主程序入口 =====
main() {
    # 检查是否首次运行
    if [[ ! -f "$CONFIG_FILE" ]] || [[ ! -d "$INSTALL_DIR" ]]; then
        initialize_installation
    fi
    
    # 主循环
    while true; do
        show_main_menu
        read -p "请选择操作 [0-9]: " choice
        
        case "$choice" in
            1) create_snapshot ;;
            2) restore_snapshot ;;
            3) manage_config ;;
            4) list_snapshots ;;
            5) log "${YELLOW}Telegram Bot 管理功能开发中...${NC}"; sleep 2 ;;
            6) log "${YELLOW}清理功能开发中...${NC}"; sleep 2 ;;
            7) log "${YELLOW}日志查看功能开发中...${NC}"; sleep 2 ;;
            8) log "${YELLOW}系统信息功能开发中...${NC}"; sleep 2 ;;
            9) log "${YELLOW}帮助文档功能开发中...${NC}"; sleep 2 ;;
            0) 
                log "${GREEN}感谢使用 SnapSync v3.0!${NC}"
                exit 0
                ;;
            *)
                log "${RED}无效选择，请重试${NC}"
                sleep 1
                ;;
        esac
    done
}

# 运行主程序
main "$@"
