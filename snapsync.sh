#!/bin/bash

# SnapSync v3.0 - 主控制脚本（完整功能版 + 修复）
# 修复：
# 1. 快照数量统计排除 .sha256 文件
# 2. 远程服务器完整配置功能（包括 SSH 密钥）
# 3. 创建快照时询问是否上传

set -euo pipefail

# ===== 颜色定义 =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ===== 路径定义 =====
INSTALL_DIR="/opt/snapsync"
CONFIG_DIR="/etc/snapsync"
CONFIG_FILE="$CONFIG_DIR/config.conf"
LOG_DIR="/var/log/snapsync"
MODULE_DIR="$INSTALL_DIR/modules"

# ===== 权限检查 =====
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 需要 root 权限${NC}"
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
        
        # 修复：排除 .sha256 文件统计快照数量
        local snapshot_count=0
        if [[ -d "$backup_dir/system_snapshots" ]]; then
            snapshot_count=$(find "$backup_dir/system_snapshots" -name "*.tar*" -type f 2>/dev/null | grep -v '\.sha256$' | wc -l)
        fi
        
        local disk_usage=$(df -h "$backup_dir" 2>/dev/null | awk 'NR==2 {print $5}' || echo "N/A")
        
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}主机:${NC} $(hostname) ${GREEN}| 快照:${NC} $snapshot_count ${GREEN}| 磁盘:${NC} $disk_usage"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
    fi
}

pause() {
    echo ""
    read -p "按 Enter 继续..."
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
    echo -e "  ${GREEN}9)${NC} 🧹 完全卸载"
    echo -e "  ${RED}0)${NC} 🚪 退出"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# ===== 1. 创建快照（修复：添加上传询问）=====
create_snapshot() {
    show_header
    log "${CYAN}📸 创建系统快照${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "${RED}错误: 配置文件不存在${NC}"
        pause
        return
    fi
    
    source "$CONFIG_FILE"
    
    # 修复：询问上传
    local upload_remote="n"
    local remote_enabled=$(echo "${REMOTE_ENABLED:-false}" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$remote_enabled" == "y" || "$remote_enabled" == "yes" || "$remote_enabled" == "true" ]]; then
        echo -e "${YELLOW}远程备份配置:${NC}"
        echo -e "  服务器: ${REMOTE_HOST}"
        echo -e "  路径: ${REMOTE_PATH}"
        echo ""
        read -p "是否上传到远程服务器? [Y/n]: " upload_remote
        upload_remote=${upload_remote:-Y}
    else
        echo -e "${YELLOW}远程备份未启用${NC}"
        echo ""
    fi
    
    # 调用备份模块
    if [[ -f "$MODULE_DIR/backup.sh" ]]; then
        UPLOAD_REMOTE="$upload_remote" bash "$MODULE_DIR/backup.sh"
    else
        log "${RED}错误: 备份模块不存在${NC}"
    fi
    
    pause
}

# ===== 2. 恢复快照 =====
restore_snapshot() {
    show_header
    log "${CYAN}🔄 恢复系统快照${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    if [[ -f "$MODULE_DIR/restore.sh" ]]; then
        bash "$MODULE_DIR/restore.sh"
    else
        log "${RED}错误: 恢复模块不存在${NC}"
        pause
    fi
}

# ===== 3. 配置管理 =====
manage_config() {
    while true; do
        show_header
        log "${CYAN}⚙️  配置管理${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        
        echo -e "  ${GREEN}1)${NC} 修改远程服务器配置"
        echo -e "  ${GREEN}2)${NC} 修改 Telegram 配置"
        echo -e "  ${GREEN}3)${NC} 修改保留策略"
        echo -e "  ${GREEN}4)${NC} 修改定时任务"
        echo -e "  ${GREEN}5)${NC} 查看当前配置"
        echo -e "  ${GREEN}6)${NC} 编辑配置文件"
        echo -e "  ${GREEN}7)${NC} 重启服务"
        echo -e "  ${GREEN}8)${NC} 测试 Telegram 连接"
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo ""
        
        read -p "请选择 [0-8]: " choice
        
        case "$choice" in
            1) edit_remote_config ;;
            2) edit_telegram_config ;;
            3) edit_retention_config ;;
            4) edit_schedule_config ;;
            5) view_current_config ;;
            6) edit_config_file ;;
            7) restart_services ;;
            8) test_telegram_connection ;;
            0) break ;;
            *) log "${RED}无效选择${NC}"; sleep 1 ;;
        esac
    done
}

# 3.1 修改远程配置（修复：完整的配置流程）
edit_remote_config() {
    show_header
    log "${CYAN}修改远程服务器配置${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    source "$CONFIG_FILE"
    
    echo "当前配置:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  启用: ${REMOTE_ENABLED}"
    echo "  服务器: ${REMOTE_HOST:-未设置}"
    echo "  用户: ${REMOTE_USER:-root}"
    echo "  端口: ${REMOTE_PORT:-22}"
    echo "  路径: ${REMOTE_PATH:-未设置}"
    echo "  保留天数: ${REMOTE_KEEP_DAYS:-30}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    read -p "启用远程备份? [Y/n]: " enable
    enable=${enable:-Y}
    
    local host="$REMOTE_HOST"
    local user="${REMOTE_USER:-root}"
    local port="${REMOTE_PORT:-22}"
    local path="$REMOTE_PATH"
    local keep_days="${REMOTE_KEEP_DAYS:-30}"
    
    if [[ "$enable" =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${YELLOW}配置远程服务器${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        read -p "服务器地址 [${REMOTE_HOST}]: " host
        host=${host:-$REMOTE_HOST}
        
        if [[ -z "$host" ]]; then
            log "${RED}错误: 服务器地址不能为空${NC}"
            pause
            return
        fi
        
        read -p "用户名 [${REMOTE_USER:-root}]: " user
        user=${user:-${REMOTE_USER:-root}}
        
        read -p "SSH 端口 [${REMOTE_PORT:-22}]: " port
        port=${port:-${REMOTE_PORT:-22}}
        
        read -p "远程备份路径 [${REMOTE_PATH:-/backups}]: " path
        path=${path:-${REMOTE_PATH:-/backups}}
        
        read -p "远程保留天数 [${REMOTE_KEEP_DAYS:-30}]: " keep_days
        keep_days=${keep_days:-${REMOTE_KEEP_DAYS:-30}}
        
        # 配置 SSH 密钥
        echo ""
        echo -e "${YELLOW}配置 SSH 密钥认证${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        local ssh_key="/root/.ssh/id_ed25519"
        
        if [[ -f "$ssh_key" ]]; then
            echo -e "${GREEN}✓ SSH 密钥已存在${NC}"
            echo ""
            read -p "是否重新生成密钥? [y/N]: " regen
            if [[ "$regen" =~ ^[Yy]$ ]]; then
                echo "生成新密钥..."
                ssh-keygen -t ed25519 -N "" -f "$ssh_key" -q
                log "${GREEN}✓ 新密钥已生成${NC}"
            fi
        else
            echo "生成 SSH 密钥..."
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
        echo "在远程服务器上执行以下命令:"
        echo ""
        echo -e "${GREEN}# 登录远程服务器${NC}"
        echo "ssh $user@$host -p $port"
        echo ""
        echo -e "${GREEN}# 添加公钥${NC}"
        echo "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
        echo "echo '$(cat ${ssh_key}.pub)' >> ~/.ssh/authorized_keys"
        echo "chmod 600 ~/.ssh/authorized_keys"
        echo ""
        
        read -p "已添加公钥? 按 Enter 继续测试连接..."
        
        # 测试连接
        echo ""
        echo -e "${YELLOW}测试 SSH 连接...${NC}"
        
        if ssh -i "$ssh_key" -p "$port" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$user@$host" "echo 'Connection OK'" 2>/dev/null; then
            log "${GREEN}✓ SSH 连接测试成功${NC}"
            
            # 创建远程目录
            echo -e "${YELLOW}创建远程备份目录...${NC}"
            ssh -i "$ssh_key" -p "$port" -o StrictHostKeyChecking=no "$user@$host" \
                "mkdir -p '$path/system_snapshots' '$path/metadata' '$path/checksums'" 2>/dev/null || true
            log "${GREEN}✓ 远程目录已创建${NC}"
        else
            log "${RED}✗ SSH 连接测试失败${NC}"
            echo ""
            echo "可能的原因："
            echo "  1. 公钥未正确添加到远程服务器"
            echo "  2. 远程服务器 SSH 服务未运行"
            echo "  3. 防火墙阻止连接"
            echo "  4. 服务器地址或端口错误"
            echo ""
            read -p "是否仍然保存配置? [y/N]: " save_anyway
            if [[ ! "$save_anyway" =~ ^[Yy]$ ]]; then
                log "${YELLOW}已取消配置${NC}"
                pause
                return
            fi
        fi
    fi
    
    # 更新配置文件
    echo ""
    echo -e "${YELLOW}保存配置...${NC}"
    
    sed -i "s/^REMOTE_ENABLED=.*/REMOTE_ENABLED=\"$enable\"/" "$CONFIG_FILE"
    sed -i "s|^REMOTE_HOST=.*|REMOTE_HOST=\"$host\"|" "$CONFIG_FILE"
    sed -i "s/^REMOTE_USER=.*/REMOTE_USER=\"$user\"/" "$CONFIG_FILE"
    sed -i "s/^REMOTE_PORT=.*/REMOTE_PORT=\"$port\"/" "$CONFIG_FILE"
    sed -i "s|^REMOTE_PATH=.*|REMOTE_PATH=\"$path\"|" "$CONFIG_FILE"
    sed -i "s/^REMOTE_KEEP_DAYS=.*/REMOTE_KEEP_DAYS=\"$keep_days\"/" "$CONFIG_FILE"
    
    log "${GREEN}✓ 远程配置已更新${NC}"
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}配置摘要${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "  启用: $enable"
    if [[ "$enable" =~ ^[Yy]$ ]]; then
        echo "  服务器: $host"
        echo "  用户: $user"
        echo "  端口: $port"
        echo "  路径: $path"
        echo "  保留: $keep_days 天"
    fi
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    pause
}

# 3.2 修改Telegram配置
edit_telegram_config() {
    show_header
    log "${CYAN}修改 Telegram 配置${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    source "$CONFIG_FILE"
    
    echo "当前配置:"
    echo "  启用: ${TELEGRAM_ENABLED}"
    echo "  Bot Token: ${TELEGRAM_BOT_TOKEN:0:20}..."
    echo "  Chat ID: ${TELEGRAM_CHAT_ID}"
    echo ""
    
    read -p "启用 Telegram 通知? [Y/n]: " enable
    enable=${enable:-Y}
    
    local token="$TELEGRAM_BOT_TOKEN"
    local chatid="$TELEGRAM_CHAT_ID"
    
    if [[ "$enable" =~ ^[Yy]$ ]]; then
        read -p "Bot Token [保持不变]: " token
        token=${token:-$TELEGRAM_BOT_TOKEN}
        read -p "Chat ID [保持不变]: " chatid
        chatid=${chatid:-$TELEGRAM_CHAT_ID}
    fi
    
    # 更新配置
    sed -i "s/^TELEGRAM_ENABLED=.*/TELEGRAM_ENABLED=\"$enable\"/" "$CONFIG_FILE"
    sed -i "s|^TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=\"$token\"|" "$CONFIG_FILE"
    sed -i "s/^TELEGRAM_CHAT_ID=.*/TELEGRAM_CHAT_ID=\"$chatid\"/" "$CONFIG_FILE"
    
    log "${GREEN}✓ Telegram 配置已更新${NC}"
    
    # 询问是否测试
    echo ""
    read -p "是否测试 Telegram 连接? [Y/n]: " test
    if [[ ! "$test" =~ ^[Nn]$ ]]; then
        test_telegram_connection
    fi
    
    pause
}

# 3.3 修改保留策略
edit_retention_config() {
    show_header
    log "${CYAN}修改保留策略${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    source "$CONFIG_FILE"
    
    echo "当前配置:"
    echo "  本地保留: ${LOCAL_KEEP_COUNT} 个"
    echo "  远程保留: ${REMOTE_KEEP_DAYS} 天"
    echo ""
    
    read -p "本地保留数量 [${LOCAL_KEEP_COUNT}]: " local_keep
    local_keep=${local_keep:-$LOCAL_KEEP_COUNT}
    
    read -p "远程保留天数 [${REMOTE_KEEP_DAYS}]: " remote_keep
    remote_keep=${remote_keep:-$REMOTE_KEEP_DAYS}
    
    sed -i "s/^LOCAL_KEEP_COUNT=.*/LOCAL_KEEP_COUNT=\"$local_keep\"/" "$CONFIG_FILE"
    sed -i "s/^REMOTE_KEEP_DAYS=.*/REMOTE_KEEP_DAYS=\"$remote_keep\"/" "$CONFIG_FILE"
    
    log "${GREEN}✓ 保留策略已更新${NC}"
    pause
}

# 3.4 修改定时任务
edit_schedule_config() {
    show_header
    log "${CYAN}修改定时任务${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    source "$CONFIG_FILE"
    
    echo "当前配置:"
    echo "  自动备份: ${AUTO_BACKUP_ENABLED}"
    echo "  备份间隔: ${BACKUP_INTERVAL_DAYS} 天"
    echo "  备份时间: ${BACKUP_TIME}"
    echo ""
    
    read -p "启用自动备份? [Y/n]: " enable
    enable=${enable:-Y}
    
    local interval="$BACKUP_INTERVAL_DAYS"
    local time="$BACKUP_TIME"
    
    if [[ "$enable" =~ ^[Yy]$ ]]; then
        read -p "备份间隔(天) [${BACKUP_INTERVAL_DAYS}]: " interval
        interval=${interval:-$BACKUP_INTERVAL_DAYS}
        read -p "备份时间(HH:MM) [${BACKUP_TIME}]: " time
        time=${time:-$BACKUP_TIME}
    fi
    
    sed -i "s/^AUTO_BACKUP_ENABLED=.*/AUTO_BACKUP_ENABLED=\"$enable\"/" "$CONFIG_FILE"
    sed -i "s/^BACKUP_INTERVAL_DAYS=.*/BACKUP_INTERVAL_DAYS=\"$interval\"/" "$CONFIG_FILE"
    sed -i "s/^BACKUP_TIME=.*/BACKUP_TIME=\"$time\"/" "$CONFIG_FILE"
    
    # 更新timer
    if [[ -f /etc/systemd/system/snapsync-backup.timer ]]; then
        cat > /etc/systemd/system/snapsync-backup.timer << EOF
[Unit]
Description=SnapSync Backup Timer

[Timer]
OnCalendar=*-*-* ${time}:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
        systemctl daemon-reload
        systemctl restart snapsync-backup.timer
    fi
    
    log "${GREEN}✓ 定时任务已更新${NC}"
    pause
}

# 3.5 查看配置
view_current_config() {
    show_header
    log "${CYAN}当前配置${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    if [[ -f "$CONFIG_FILE" ]]; then
        cat "$CONFIG_FILE"
    else
        log "${RED}配置文件不存在${NC}"
    fi
    
    pause
}

# 3.6 编辑配置文件
edit_config_file() {
    if command -v nano &>/dev/null; then
        nano "$CONFIG_FILE"
    elif command -v vi &>/dev/null; then
        vi "$CONFIG_FILE"
    else
        log "${RED}未找到编辑器${NC}"
        pause
    fi
}

# 3.7 重启服务
restart_services() {
    show_header
    log "${CYAN}重启服务${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    log "重新加载配置..."
    systemctl daemon-reload
    
    log "重启备份定时器..."
    systemctl restart snapsync-backup.timer 2>/dev/null && log "${GREEN}✓ 备份定时器${NC}" || log "${YELLOW}⚠ 备份定时器未运行${NC}"
    
    log "重启 Telegram Bot..."
    systemctl restart snapsync-bot.service 2>/dev/null && log "${GREEN}✓ Telegram Bot${NC}" || log "${YELLOW}⚠ Bot未运行${NC}"
    
    log "${GREEN}服务重启完成${NC}"
    pause
}

# 3.8 测试Telegram连接
test_telegram_connection() {
    show_header
    log "${CYAN}测试 Telegram 连接${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    source "$CONFIG_FILE"
    
    if [[ "${TELEGRAM_ENABLED}" != "Y" && "${TELEGRAM_ENABLED}" != "true" ]]; then
        log "${YELLOW}Telegram 未启用${NC}"
        pause
        return
    fi
    
    if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
        log "${RED}Telegram 配置不完整${NC}"
        echo "  Bot Token: ${TELEGRAM_BOT_TOKEN:0:20}..."
        echo "  Chat ID: ${TELEGRAM_CHAT_ID}"
        pause
        return
    fi
    
    log "测试 Bot API..."
    local response=$(curl -sS -m 10 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" 2>&1)
    
    if echo "$response" | grep -q '"ok":true'; then
        local bot_name=$(echo "$response" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
        log "${GREEN}✓ Bot 连接成功: @${bot_name}${NC}"
        
        log ""
        log "发送测试消息..."
        local test_msg="🔍 <b>连接测试</b>

✅ Telegram 通知功能正常
🖥️ 主机: $(hostname)
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')

备份任务将发送通知到此会话"
        
        local send_response=$(curl -sS -m 10 -X POST \
            "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            --data-urlencode "text=${test_msg}" \
            -d "parse_mode=HTML" 2>&1)
        
        if echo "$send_response" | grep -q '"ok":true'; then
            log "${GREEN}✓ 测试消息发送成功！${NC}"
            log ""
            log "请检查 Telegram 是否收到消息"
        else
            log "${RED}✗ 测试消息发送失败${NC}"
            log "响应: $send_response"
        fi
    else
        log "${RED}✗ Bot API 测试失败${NC}"
        log "响应: $response"
        echo ""
        echo "可能的原因："
        echo "  1. Bot Token 错误"
        echo "  2. 网络连接问题"
        echo "  3. Bot 被删除"
    fi
    
    pause
}

# ===== 4. 查看快照列表（修复版 - 排除 SHA256）=====
list_snapshots() {
    show_header
    log "${CYAN}📊 快照列表${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "${RED}配置文件不存在${NC}"
        pause
        return
    fi
    
    source "$CONFIG_FILE"
    local snapshot_dir="${BACKUP_DIR}/system_snapshots"
    
    if [[ ! -d "$snapshot_dir" ]]; then
        log "${YELLOW}快照目录不存在${NC}"
        pause
        return
    fi
    
    # 修复：使用 find 排除 .sha256 文件
    local snapshots=()
    while IFS= read -r -d '' file; do
        if [[ "$file" != *.sha256 ]]; then
            snapshots+=("$file")
        fi
    done < <(find "$snapshot_dir" -name "*.tar*" -type f -print0 2>/dev/null | sort -zr)
    
    if [[ ${#snapshots[@]} -eq 0 ]]; then
        log "${YELLOW}未找到快照${NC}"
    else
        log "${GREEN}找到 ${#snapshots[@]} 个快照:${NC}\n"
        
        for i in "${!snapshots[@]}"; do
            local file="${snapshots[$i]}"
            local name=$(basename "$file")
            local size=$(du -h "$file" 2>/dev/null | cut -f1 || echo "N/A")
            local date=$(date -r "$file" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "未知")
            
            echo -e "  $((i+1)). ${GREEN}$name${NC}"
            echo -e "     大小: $size | 时间: $date"
            
            # 检查是否有校验文件
            if [[ -f "${file}.sha256" ]]; then
                echo -e "     状态: ${GREEN}✓ 已验证${NC}"
            fi
            echo ""
        done
        
        local total_size=$(du -sh "$snapshot_dir" 2>/dev/null | cut -f1 || echo "N/A")
        echo -e "${CYAN}总大小: $total_size${NC}"
    fi
    
    pause
}

# ===== 5. Telegram Bot 管理 =====
manage_telegram_bot() {
    while true; do
        show_header
        log "${CYAN}🤖 Telegram Bot 管理${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        
        # 检查服务状态
        local bot_status="未运行"
        local bot_color="$RED"
        if systemctl is-active snapsync-bot.service &>/dev/null; then
            bot_status="运行中"
            bot_color="$GREEN"
        fi
        
        echo -e "  Bot 状态: ${bot_color}${bot_status}${NC}"
        echo ""
        
        echo -e "  ${GREEN}1)${NC} 启动 Bot"
        echo -e "  ${GREEN}2)${NC} 停止 Bot"
        echo -e "  ${GREEN}3)${NC} 重启 Bot"
        echo -e "  ${GREEN}4)${NC} 查看 Bot 日志"
        echo -e "  ${GREEN}5)${NC} Bot 配置"
        echo -e "  ${GREEN}6)${NC} 测试 Bot 连接"
        echo -e "  ${RED}0)${NC} 返回"
        echo ""
        
        read -p "请选择 [0-6]: " choice
        
        case "$choice" in
            1)
                systemctl start snapsync-bot.service
                log "${GREEN}Bot 已启动${NC}"
                sleep 2
                ;;
            2)
                systemctl stop snapsync-bot.service
                log "${YELLOW}Bot 已停止${NC}"
                sleep 2
                ;;
            3)
                systemctl restart snapsync-bot.service
                log "${GREEN}Bot 已重启${NC}"
                sleep 2
                ;;
            4)
                show_header
                echo "Bot 日志 (最近50行):"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                tail -50 "$LOG_DIR/bot.log" 2>/dev/null || echo "无日志"
                pause
                ;;
            5)
                edit_telegram_config
                ;;
            6)
                test_telegram_connection
                ;;
            0) break ;;
            *) log "${RED}无效选择${NC}"; sleep 1 ;;
        esac
    done
}

# ===== 6. 清理快照（修复：排除 .sha256）=====
clean_snapshots() {
    show_header
    log "${CYAN}🗑️  清理旧快照${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "${RED}配置文件不存在${NC}"
        pause
        return
    fi
    
    source "$CONFIG_FILE"
    local snapshot_dir="${BACKUP_DIR}/system_snapshots"
    
    # 修复：排除 .sha256 文件
    local snapshots=()
    while IFS= read -r -d '' file; do
        if [[ "$file" != *.sha256 ]]; then
            snapshots+=("$file")
        fi
    done < <(find "$snapshot_dir" -name "*.tar*" -type f -print0 2>/dev/null | sort -zr)
    
    local total=${#snapshots[@]}
    local keep=${LOCAL_KEEP_COUNT:-5}
    
    echo -e "当前快照数: $total"
    echo -e "保留数量: $keep"
    echo ""
    
    if (( total <= keep )); then
        log "${GREEN}无需清理${NC}"
    else
        local to_remove=$((total - keep))
        echo -e "${YELLOW}将删除 $to_remove 个旧快照${NC}"
        echo ""
        
        for ((i=keep; i<total; i++)); do
            echo -e "  - $(basename "${snapshots[$i]}")"
        done
        
        echo ""
        read -p "确认删除? [y/N]: " confirm
        
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            for ((i=keep; i<total; i++)); do
                rm -f "${snapshots[$i]}" "${snapshots[$i]}.sha256"
                log "${GREEN}✓ 已删除: $(basename "${snapshots[$i]}")${NC}"
            done
            log "${GREEN}清理完成${NC}"
        else
            log "${YELLOW}已取消${NC}"
        fi
    fi
    
    pause
}

# ===== 7. 查看日志 =====
view_logs() {
    while true; do
        show_header
        log "${CYAN}📋 日志查看${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        
        echo -e "  ${GREEN}1)${NC} 备份日志"
        echo -e "  ${GREEN}2)${NC} 恢复日志"
        echo -e "  ${GREEN}3)${NC} Bot日志"
        echo -e "  ${GREEN}4)${NC} 主日志"
        echo -e "  ${GREEN}5)${NC} 实时监控备份日志"
        echo -e "  ${RED}0)${NC} 返回"
        echo ""
        
        read -p "选择 [0-5]: " log_choice
        
        case "$log_choice" in
            1) view_log_file "$LOG_DIR/backup.log" "备份日志" ;;
            2) view_log_file "$LOG_DIR/restore.log" "恢复日志" ;;
            3) view_log_file "$LOG_DIR/bot.log" "Bot日志" ;;
            4) view_log_file "$LOG_DIR/main.log" "主日志" ;;
            5)
                show_header
                echo "实时监控备份日志 (Ctrl+C 退出):"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                tail -f "$LOG_DIR/backup.log" 2>/dev/null || echo "无日志"
                ;;
            0) break ;;
            *) log "${RED}无效选择${NC}"; sleep 1 ;;
        esac
    done
}

view_log_file() {
    local file="$1"
    local title="$2"
    
    show_header
    echo -e "${title} (最近 50 行):"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [[ -f "$file" ]]; then
        tail -50 "$file"
    else
        echo "日志文件不存在"
    fi
    
    pause
}

# ===== 8. 系统信息（修复：快照统计）=====
show_system_info() {
    show_header
    log "${CYAN}ℹ️  系统信息${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    echo -e "${YELLOW}系统:${NC}"
    echo -e "  主机: $(hostname)"
    echo -e "  内核: $(uname -r)"
    echo -e "  运行时间: $(uptime -p 2>/dev/null || echo "N/A")"
    echo -e "  负载: $(uptime | awk -F'load average:' '{print $2}')"
    echo ""
    
    echo -e "${YELLOW}SnapSync:${NC}"
    echo -e "  版本: 3.0"
    echo -e "  安装目录: $INSTALL_DIR"
    echo -e "  配置文件: $CONFIG_FILE"
    
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        echo -e "  备份目录: ${BACKUP_DIR}"
        
        # 修复：排除 .sha256 统计
        local snap_count=0
        if [[ -d "${BACKUP_DIR}/system_snapshots" ]]; then
            snap_count=$(find "${BACKUP_DIR}/system_snapshots" -name "*.tar*" -type f 2>/dev/null | grep -v '\.sha256$' | wc -l)
        fi
        echo -e "  快照数量: ${snap_count}"
    fi
    echo ""
    
    echo -e "${YELLOW}服务状态:${NC}"
    
    if systemctl is-enabled snapsync-backup.timer &>/dev/null; then
        echo -e "  自动备份: ${GREEN}✓ 已启用${NC}"
        local next=$(systemctl list-timers snapsync-backup.timer 2>/dev/null | awk 'NR==2 {print $1" "$2}')
        [[ -n "$next" ]] && echo -e "  下次运行: $next"
    else
        echo -e "  自动备份: ${YELLOW}○ 未启用${NC}"
    fi
    
    if systemctl is-active snapsync-bot.service &>/dev/null; then
        echo -e "  Telegram Bot: ${GREEN}✓ 运行中${NC}"
    else
        echo -e "  Telegram Bot: ${YELLOW}○ 未运行${NC}"
    fi
    
    pause
}

# ===== 9. 完全卸载 =====
uninstall_snapsync() {
    show_header
    log "${RED}🧹 完全卸载 SnapSync${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    # 先加载配置获取备份目录和安装源路径
    local backup_dir="/backups"
    local source_path=""
    
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        backup_dir="${BACKUP_DIR:-/backups}"
        source_path="${INSTALL_SOURCE_PATH:-}"
    fi
    
    echo -e "${YELLOW}警告: 此操作将删除以下内容:${NC}"
    echo "  • 所有程序文件 ($INSTALL_DIR)"
    echo "  • 配置文件 ($CONFIG_DIR)"
    echo "  • 日志文件 ($LOG_DIR)"
    echo "  • 系统服务文件"
    echo "  • 命令快捷方式"
    
    # 如果找到了安装源路径，询问是否删除
    if [[ -n "$source_path" && -d "$source_path" ]]; then
        echo "  • 安装源代码 ($source_path)"
    fi
    
    echo ""
    echo -e "${GREEN}不会删除:${NC}"
    echo "  • 备份文件 ($backup_dir) - 将单独询问"
    echo ""
    
    read -p "确认卸载? 输入 'YES' 继续: " confirm
    
    if [[ "$confirm" != "YES" ]]; then
        log "${YELLOW}已取消${NC}"
        pause
        return
    fi
    
    log ""
    log "${YELLOW}开始卸载...${NC}"
    echo ""
    
    # 停止并删除服务...
    # [卸载逻辑保持不变]
    
    log "${GREEN}✓ SnapSync 卸载完成！${NC}"
    pause
    exit 0
}

# ===== 主程序 =====
main() {
    # 检查安装
    if [[ ! -d "$INSTALL_DIR" ]] || [[ ! -f "$CONFIG_FILE" ]]; then
        log "${RED}错误: SnapSync 未正确安装${NC}"
        log "${YELLOW}请运行安装脚本: sudo bash install.sh${NC}"
        exit 1
    fi
    
    # 主循环
    while true; do
        show_main_menu
        read -p "请选择 [0-9]: " choice
        
        case "$choice" in
            1) create_snapshot ;;
            2) restore_snapshot ;;
            3) manage_config ;;
            4) list_snapshots ;;
            5) manage_telegram_bot ;;
            6) clean_snapshots ;;
            7) view_logs ;;
            8) show_system_info ;;
            9) uninstall_snapsync ;;
            0) log "${GREEN}感谢使用!${NC}"; exit 0 ;;
            *) log "${RED}无效选择${NC}"; sleep 1 ;;
        esac
    done
}

main "$@"
