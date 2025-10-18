#!/bin/bash

# SnapSync v3.0 - 主控制脚本（完整功能版）
# 已实现所有菜单功能

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
        local snapshot_count=$(find "$backup_dir/system_snapshots" -name "*.tar*" 2>/dev/null | wc -l)
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

# ===== 1. 创建快照 =====
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
    
    # 询问上传
    local upload_remote="n"
    if [[ "${REMOTE_ENABLED}" =~ ^[Yy]|true$ ]]; then
        read -p "是否上传到远程服务器? [Y/n]: " upload_remote
        upload_remote=${upload_remote:-Y}
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

# 3.1 修改远程配置
edit_remote_config() {
    show_header
    log "${CYAN}修改远程服务器配置${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    source "$CONFIG_FILE"
    
    echo "当前配置:"
    echo "  启用: ${REMOTE_ENABLED}"
    echo "  服务器: ${REMOTE_HOST:-未设置}"
    echo "  用户: ${REMOTE_USER:-root}"
    echo "  端口: ${REMOTE_PORT:-22}"
    echo "  路径: ${REMOTE_PATH:-未设置}"
    echo ""
    
    read -p "启用远程备份? [Y/n]: " enable
    enable=${enable:-Y}
    
    local host="$REMOTE_HOST"
    local user="${REMOTE_USER:-root}"
    local port="${REMOTE_PORT:-22}"
    local path="$REMOTE_PATH"
    
    if [[ "$enable" =~ ^[Yy]$ ]]; then
        read -p "服务器地址 [${REMOTE_HOST}]: " host
        host=${host:-$REMOTE_HOST}
        read -p "用户名 [${REMOTE_USER:-root}]: " user
        user=${user:-${REMOTE_USER:-root}}
        read -p "端口 [${REMOTE_PORT:-22}]: " port
        port=${port:-${REMOTE_PORT:-22}}
        read -p "路径 [${REMOTE_PATH}]: " path
        path=${path:-$REMOTE_PATH}
    fi
    
    # 更新配置
    sed -i "s/^REMOTE_ENABLED=.*/REMOTE_ENABLED=\"$enable\"/" "$CONFIG_FILE"
    sed -i "s|^REMOTE_HOST=.*|REMOTE_HOST=\"$host\"|" "$CONFIG_FILE"
    sed -i "s/^REMOTE_USER=.*/REMOTE_USER=\"$user\"/" "$CONFIG_FILE"
    sed -i "s/^REMOTE_PORT=.*/REMOTE_PORT=\"$port\"/" "$CONFIG_FILE"
    sed -i "s|^REMOTE_PATH=.*|REMOTE_PATH=\"$path\"|" "$CONFIG_FILE"
    
    log "${GREEN}✓ 远程配置已更新${NC}"
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
    
    # 使用 ls + grep 排除 .sha256 文件
    local snapshots=()
    
    if cd "$snapshot_dir" 2>/dev/null; then
        while IFS= read -r file; do
            # 确保是文件且不是 .sha256
            if [[ -f "$file" && "$file" != *.sha256 ]]; then
                snapshots+=("$snapshot_dir/$file")
            fi
        done < <(ls -t system_snapshot_*.tar* 2>/dev/null | grep -v '\.sha256$')
        cd - >/dev/null
    fi
    
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
            
            # 检查是否有校验文件（但不显示 .sha256 文件本身）
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

# ===== 6. 清理快照 =====
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
    
    local snapshots=($(find "$snapshot_dir" -name "*.tar*" -type f 2>/dev/null | sort -r))
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

# ===== 8. 系统信息 =====
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
        
        local snap_count=$(find "${BACKUP_DIR}/system_snapshots" -name "*.tar*" 2>/dev/null | wc -l)
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
# ===== 9. 完全卸载（修复版 - 包含源代码清理） =====
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
    
    # 1. 停止服务
    log "1/9 停止服务..."
    systemctl stop snapsync-backup.timer 2>/dev/null || true
    systemctl stop snapsync-backup.service 2>/dev/null || true
    systemctl stop snapsync-bot.service 2>/dev/null || true
    log "${GREEN}✓ 服务已停止${NC}"
    sleep 1
    
    # 2. 禁用服务
    log "2/9 禁用服务..."
    systemctl disable snapsync-backup.timer 2>/dev/null || true
    systemctl disable snapsync-backup.service 2>/dev/null || true
    systemctl disable snapsync-bot.service 2>/dev/null || true
    log "${GREEN}✓ 服务已禁用${NC}"
    sleep 1
    
    # 3. 删除服务文件
    log "3/9 删除服务文件..."
    rm -f /etc/systemd/system/snapsync-backup.service 2>/dev/null || true
    rm -f /etc/systemd/system/snapsync-backup.timer 2>/dev/null || true
    rm -f /etc/systemd/system/snapsync-bot.service 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    log "${GREEN}✓ 服务文件已删除${NC}"
    sleep 1
    
    # 4. 删除命令
    log "4/9 删除命令..."
    rm -f /usr/local/bin/snapsync 2>/dev/null || true
    rm -f /usr/local/bin/snapsync-backup 2>/dev/null || true
    rm -f /usr/local/bin/snapsync-restore 2>/dev/null || true
    rm -f /usr/local/bin/telegram-test 2>/dev/null || true
    log "${GREEN}✓ 命令已删除${NC}"
    sleep 1
    
    # 5. 删除程序文件
    log "5/9 删除程序文件..."
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR" 2>/dev/null || true
        log "${GREEN}✓ 程序文件已删除 ($INSTALL_DIR)${NC}"
    else
        log "${YELLOW}⚠ 程序目录不存在${NC}"
    fi
    sleep 1
    
    # 6. 删除安装源代码
    log "6/9 处理安装源代码..."
    
    if [[ -n "$source_path" && -d "$source_path" ]]; then
        echo ""
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}发现安装源代码${NC}"
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "路径: $source_path"
        
        # 检查是否看起来像 SnapSync 目录
        if [[ -f "$source_path/install.sh" ]] || [[ -f "$source_path/snapsync.sh" ]]; then
            echo "状态: 已验证为 SnapSync 源代码"
            echo ""
            read -p "是否删除源代码目录? [y/N]: " del_source
            
            if [[ "$del_source" =~ ^[Yy]$ ]]; then
                if rm -rf "$source_path" 2>/dev/null; then
                    log "${GREEN}✓ 源代码已删除 ($source_path)${NC}"
                else
                    log "${RED}✗ 源代码删除失败${NC}"
                    echo "  可能需要手动删除: ${CYAN}sudo rm -rf $source_path${NC}"
                fi
            else
                log "${YELLOW}⊙ 源代码已保留 ($source_path)${NC}"
            fi
        else
            log "${YELLOW}⚠ 路径不像 SnapSync 目录，跳过删除${NC}"
        fi
    else
        # 如果配置文件中没有记录，询问用户
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}未找到安装源路径记录${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "如果您知道源代码位置（例如 /root/SnapSync），"
        echo "可以手动输入路径进行删除"
        echo ""
        read -p "是否删除源代码? [y/N]: " want_del_source
        
        if [[ "$want_del_source" =~ ^[Yy]$ ]]; then
            read -p "请输入完整路径（例如: /root/SnapSync）: " manual_source_path
            
            if [[ -n "$manual_source_path" && -d "$manual_source_path" ]]; then
                # 安全检查
                if [[ "$manual_source_path" == "/" ]] || [[ "$manual_source_path" == "/root" ]] || \
                   [[ "$manual_source_path" == "/home" ]] || [[ "$manual_source_path" == "/etc" ]]; then
                    log "${RED}✗ 拒绝删除系统关键目录${NC}"
                else
                    echo ""
                    echo "即将删除: $manual_source_path"
                    ls -lh "$manual_source_path" 2>/dev/null | head -5
                    echo ""
                    read -p "确认删除此目录? 输入 'YES': " confirm_del
                    
                    if [[ "$confirm_del" == "YES" ]]; then
                        if rm -rf "$manual_source_path" 2>/dev/null; then
                            log "${GREEN}✓ 源代码已删除 ($manual_source_path)${NC}"
                        else
                            log "${RED}✗ 删除失败${NC}"
                        fi
                    else
                        log "${YELLOW}⊙ 已取消删除${NC}"
                    fi
                fi
            else
                log "${YELLOW}⊙ 路径无效或不存在${NC}"
            fi
        else
            log "${YELLOW}⊙ 跳过源代码删除${NC}"
        fi
    fi
    sleep 1
    
    # 7. 配置文件
    log "7/9 处理配置文件..."
    echo ""
    read -p "是否删除配置文件? [y/N]: " del_config
    if [[ "$del_config" =~ ^[Yy]$ ]]; then
        if [[ -d "$CONFIG_DIR" ]]; then
            rm -rf "$CONFIG_DIR" 2>/dev/null || true
            log "${GREEN}✓ 配置文件已删除 ($CONFIG_DIR)${NC}"
        fi
    else
        log "${YELLOW}⊙ 配置文件已保留 ($CONFIG_DIR)${NC}"
    fi
    sleep 1
    
    # 8. 日志文件
    log "8/9 处理日志文件..."
    echo ""
    read -p "是否删除日志文件? [y/N]: " del_logs
    if [[ "$del_logs" =~ ^[Yy]$ ]]; then
        if [[ -d "$LOG_DIR" ]]; then
            rm -rf "$LOG_DIR" 2>/dev/null || true
            log "${GREEN}✓ 日志文件已删除 ($LOG_DIR)${NC}"
        fi
    else
        log "${YELLOW}⊙ 日志文件已保留 ($LOG_DIR)${NC}"
    fi
    sleep 1
    
    # 9. 备份文件
    log "9/9 处理备份文件..."
    if [[ -d "$backup_dir/system_snapshots" ]]; then
        local backup_count=$(find "$backup_dir/system_snapshots" -name "*.tar*" -type f 2>/dev/null | wc -l)
        
        if (( backup_count > 0 )); then
            echo ""
            log "${YELLOW}警告: 发现 $backup_count 个备份文件${NC}"
            echo ""
            read -p "是否删除所有备份? [y/N]: " del_backups
            
            if [[ "$del_backups" =~ ^[Yy]$ ]]; then
                rm -rf "$backup_dir/system_snapshots" 2>/dev/null || true
                rm -rf "$backup_dir/metadata" 2>/dev/null || true
                rm -rf "$backup_dir/checksums" 2>/dev/null || true
                log "${GREEN}✓ 备份文件已删除${NC}"
            else
                log "${GREEN}⊙ 备份文件已保留: $backup_dir${NC}"
            fi
        else
            log "${YELLOW}⊙ 未发现备份文件${NC}"
        fi
    else
        log "${YELLOW}⊙ 备份目录不存在${NC}"
    fi
    
    # 完成
    echo ""
    log "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${GREEN}✓ SnapSync 卸载完成！${NC}"
    log "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    log "感谢使用 SnapSync!"
    echo ""
    
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
