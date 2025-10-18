#!/bin/bash

# SnapSync v3.0 - Telegram Bot（按钮交互版）
# 支持：按钮式交互 + 多VPS管理

set -euo pipefail

# ===== 路径定义 =====
CONFIG_FILE="/etc/snapsync/config.conf"
LOG_FILE="/var/log/snapsync/bot.log"
STATE_FILE="/var/run/snapsync-bot.state"

# ===== 加载配置 =====
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "错误: 配置文件不存在"
    exit 1
fi

source "$CONFIG_FILE"

if [[ -z "$TELEGRAM_BOT_TOKEN" ]] || [[ -z "$TELEGRAM_CHAT_ID" ]]; then
    echo "错误: Telegram配置不完整"
    exit 1
fi

# ===== 全局变量 =====
API_URL="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"
LAST_UPDATE_ID=0
HOSTNAME="${HOSTNAME:-$(hostname)}"

# ===== 工具函数 =====
log_bot() {
    echo "$(date '+%F %T') [$HOSTNAME] $*" >> "$LOG_FILE"
}

# 发送消息（带VPS标识）
send_message() {
    local chat_id="$1"
    local text="$2"
    local parse_mode="${3:-HTML}"
    
    local vps_header="🖥️ <b>${HOSTNAME}</b>
━━━━━━━━━━━━━━━━━━━━━━━
"
    local full_text="${vps_header}${text}"
    
    curl -sS -X POST "${API_URL}/sendMessage" \
        -d "chat_id=${chat_id}" \
        --data-urlencode "text=${full_text}" \
        -d "parse_mode=${parse_mode}" \
        -d "disable_web_page_preview=true" &>/dev/null
    
    log_bot "消息已发送"
}

# 发送带按钮的消息
send_message_with_buttons() {
    local chat_id="$1"
    local text="$2"
    local keyboard="$3"
    
    local vps_header="🖥️ <b>${HOSTNAME}</b>
━━━━━━━━━━━━━━━━━━━━━━━
"
    local full_text="${vps_header}${text}"
    
    curl -sS -X POST "${API_URL}/sendMessage" \
        -d "chat_id=${chat_id}" \
        --data-urlencode "text=${full_text}" \
        -d "parse_mode=HTML" \
        -d "reply_markup=${keyboard}" &>/dev/null
    
    log_bot "按钮消息已发送"
}

# 编辑消息
edit_message() {
    local chat_id="$1"
    local message_id="$2"
    local text="$3"
    local keyboard="$4"
    
    local vps_header="🖥️ <b>${HOSTNAME}</b>
━━━━━━━━━━━━━━━━━━━━━━━
"
    local full_text="${vps_header}${text}"
    
    curl -sS -X POST "${API_URL}/editMessageText" \
        -d "chat_id=${chat_id}" \
        -d "message_id=${message_id}" \
        --data-urlencode "text=${full_text}" \
        -d "parse_mode=HTML" \
        -d "reply_markup=${keyboard}" &>/dev/null
}

answer_callback() {
    local callback_id="$1"
    local text="${2:-✓}"
    
    curl -sS -X POST "${API_URL}/answerCallbackQuery" \
        -d "callback_query_id=${callback_id}" \
        --data-urlencode "text=${text}" &>/dev/null
}

format_bytes() {
    local bytes="$1"
    [[ ! "$bytes" =~ ^[0-9]+$ ]] && echo "0B" && return
    if (( bytes >= 1073741824 )); then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1073741824}")GB"
    elif (( bytes >= 1048576 )); then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1048576}")MB"
    else
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1024}")KB"
    fi
}

# ===== 按钮构建函数 =====

# 主菜单按钮
get_main_menu_keyboard() {
    echo '{
  "inline_keyboard": [
    [{"text": "📊 系统状态", "callback_data": "menu_status"}],
    [{"text": "📋 快照列表", "callback_data": "menu_list"}],
    [{"text": "🔄 创建快照", "callback_data": "menu_create"}],
    [{"text": "⚙️ 配置信息", "callback_data": "menu_config"}],
    [{"text": "🗑️ 删除快照", "callback_data": "menu_delete"}],
    [{"text": "❓ 帮助", "callback_data": "menu_help"}]
  ]
}'
}

# 返回主菜单按钮
get_back_button() {
    echo '{
  "inline_keyboard": [
    [{"text": "🔙 返回主菜单", "callback_data": "menu_main"}]
  ]
}'
}

# 确认/取消按钮
get_confirm_buttons() {
    local action="$1"
    echo "{
  \"inline_keyboard\": [
    [{\"text\": \"✅ 确认\", \"callback_data\": \"confirm_${action}\"}, {\"text\": \"❌ 取消\", \"callback_data\": \"cancel\"}]
  ]
}"
}

# ===== Bot 命令处理 =====

cmd_start() {
    local chat_id="$1"
    
    local message="👋 <b>欢迎使用 SnapSync Bot</b>

📍 当前VPS: ${HOSTNAME}
📊 版本: v3.0

<b>🎯 快速开始:</b>
点击下方按钮进行操作

<b>💡 多VPS管理:</b>
• 所有消息显示主机名
• 可在多个VPS使用同一Bot
• 按钮交互，操作更简单"

    send_message_with_buttons "$chat_id" "$message" "$(get_main_menu_keyboard)"
}

cmd_menu() {
    local chat_id="$1"
    
    local message="📱 <b>主菜单</b>

选择要执行的操作:"

    send_message_with_buttons "$chat_id" "$message" "$(get_main_menu_keyboard)"
}

# ===== 按钮回调处理 =====

handle_menu_main() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "主菜单"
    
    local message="📱 <b>主菜单</b>

选择要执行的操作:"

    edit_message "$chat_id" "$message_id" "$message" "$(get_main_menu_keyboard)"
}

handle_menu_status() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "加载中..."
    
    # 获取状态信息
    local uptime_info=$(uptime -p 2>/dev/null || echo "N/A")
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | xargs | cut -d',' -f1)
    local mem_info=$(free -h | awk 'NR==2 {print $3"/"$2}')
    
    local backup_dir="${BACKUP_DIR:-/backups}"
    local disk_info=$(df -h "$backup_dir" 2>/dev/null | tail -n1)
    local disk_usage=$(echo "$disk_info" | awk '{print $5}')
    local disk_free=$(echo "$disk_info" | awk '{print $4}')
    
    local snapshot_dir="${backup_dir}/system_snapshots"
    local snapshot_count=$(find "$snapshot_dir" -name "*.tar*" 2>/dev/null | wc -l)
    
    local latest="无"
    local latest_size="N/A"
    local latest_date="N/A"
    
    if (( snapshot_count > 0 )); then
        local latest_file=$(find "$snapshot_dir" -name "*.tar*" 2>/dev/null | sort -r | head -1)
        if [[ -n "$latest_file" ]]; then
            latest=$(basename "$latest_file")
            latest_size=$(format_bytes "$(stat -c%s "$latest_file" 2>/dev/null || echo 0)")
            latest_date=$(date -r "$latest_file" "+%m-%d %H:%M" 2>/dev/null)
        fi
    fi
    
    local next_backup="未启用"
    if [[ "${AUTO_BACKUP_ENABLED}" =~ ^[Yy]|true$ ]]; then
        next_backup=$(systemctl list-timers snapsync-backup.timer 2>/dev/null | awk 'NR==2 {print $1" "$2}' || echo "N/A")
    fi
    
    local message="📊 <b>系统状态</b>

<b>🖥️ 系统</b>
运行时间: ${uptime_info}
负载: ${load_avg}
内存: ${mem_info}

<b>💾 存储</b>
磁盘使用: ${disk_usage}
可用空间: ${disk_free}

<b>📸 快照</b>
快照数: ${snapshot_count}个
最新: ${latest}
大小: ${latest_size}
时间: ${latest_date}

<b>⏰ 定时</b>
自动备份: ${AUTO_BACKUP_ENABLED}
下次运行: ${next_backup}

<i>更新: $(date '+%m-%d %H:%M')</i>"

    edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
}

handle_menu_list() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "加载中..."
    
    local snapshot_dir="${BACKUP_DIR:-/backups}/system_snapshots"
    local snapshots=($(find "$snapshot_dir" -name "*.tar*" -type f 2>/dev/null | sort -r))
    
    if [[ ${#snapshots[@]} -eq 0 ]]; then
        local message="📋 <b>快照列表</b>

暂无快照文件

<i>使用「创建快照」功能创建第一个快照</i>"
        edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
        return
    fi
    
    local message="📋 <b>快照列表</b> (${#snapshots[@]}个)

"
    
    local max_show=5
    for i in "${!snapshots[@]}"; do
        (( i >= max_show )) && break
        
        local file="${snapshots[$i]}"
        local name=$(basename "$file")
        local size=$(format_bytes "$(stat -c%s "$file" 2>/dev/null || echo 0)")
        local date=$(date -r "$file" "+%m-%d %H:%M" 2>/dev/null)
        
        message+="<b>$((i+1)).</b> <code>${name:17:14}</code>
   📦 ${size} | 📅 ${date}

"
    done
    
    if (( ${#snapshots[@]} > max_show )); then
        message+="
<i>... 还有 $((${#snapshots[@]} - max_show)) 个快照</i>"
    fi
    
    message+="

<i>删除快照请使用「删除快照」功能</i>"
    
    edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
}

handle_menu_create() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "准备创建..."
    
    local message="🔄 <b>创建快照</b>

即将创建系统快照

<b>⚠️ 注意:</b>
• 备份需要几分钟时间
• 期间请勿关闭服务器
• 完成后会发送通知

确认创建快照?"

    local keyboard='{
  "inline_keyboard": [
    [{"text": "✅ 确认创建", "callback_data": "confirm_create"}],
    [{"text": "❌ 取消", "callback_data": "menu_main"}]
  ]
}'
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
}

handle_confirm_create() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "开始备份..."
    
    local message="🔄 <b>备份进行中</b>

⏳ 正在创建快照...
这可能需要几分钟

备份完成后会自动通知"

    edit_message "$chat_id" "$message_id" "$message" "{\"inline_keyboard\":[]}"
    
    # 异步执行备份
    (
        if /opt/snapsync/modules/backup.sh &>>/var/log/snapsync/bot.log; then
            send_message_with_buttons "$chat_id" "✅ <b>快照创建成功</b>

使用「快照列表」查看" "$(get_main_menu_keyboard)"
        else
            send_message_with_buttons "$chat_id" "❌ <b>快照创建失败</b>

请查看日志获取详细信息" "$(get_main_menu_keyboard)"
        fi
    ) &
}

handle_menu_delete() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "加载快照..."
    
    local snapshot_dir="${BACKUP_DIR:-/backups}/system_snapshots"
    local snapshots=($(find "$snapshot_dir" -name "*.tar*" -type f 2>/dev/null | sort -r))
    
    if [[ ${#snapshots[@]} -eq 0 ]]; then
        local message="🗑️ <b>删除快照</b>

暂无可删除的快照"
        edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
        return
    fi
    
    # 构建快照选择按钮
    local buttons="["
    local count=0
    for i in "${!snapshots[@]}"; do
        (( count >= 5 )) && break
        
        local file="${snapshots[$i]}"
        local name=$(basename "$file")
        local short_name="${name:17:14}"
        
        buttons+="{\"text\": \"$((i+1)). ${short_name}\", \"callback_data\": \"delete_${i}\"},"
        ((count++))
    done
    buttons="${buttons%,}]"
    
    local keyboard="{\"inline_keyboard\":[$buttons,[{\"text\":\"🔙 返回\",\"callback_data\":\"menu_main\"}]]}"
    
    local message="🗑️ <b>删除快照</b>

选择要删除的快照:

<i>点击快照编号确认删除</i>"
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
}

handle_delete_snapshot() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local snapshot_id="$4"
    
    answer_callback "$callback_id" "准备删除..."
    
    local snapshot_dir="${BACKUP_DIR:-/backups}/system_snapshots"
    local snapshots=($(find "$snapshot_dir" -name "*.tar*" -type f 2>/dev/null | sort -r))
    
    if [[ ! "$snapshot_id" =~ ^[0-9]+$ ]] || (( snapshot_id >= ${#snapshots[@]} )); then
        answer_callback "$callback_id" "无效的快照"
        return
    fi
    
    local file="${snapshots[$snapshot_id]}"
    local name=$(basename "$file")
    
    local message="🗑️ <b>确认删除</b>

快照: <code>${name}</code>

<b>⚠️ 此操作不可撤销！</b>

确认删除此快照?"

    local keyboard="{
  \"inline_keyboard\": [
    [{\"text\": \"✅ 确认删除\", \"callback_data\": \"confirm_delete_${snapshot_id}\"}],
    [{\"text\": \"❌ 取消\", \"callback_data\": \"menu_delete\"}]
  ]
}"
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
}

handle_confirm_delete() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local snapshot_id="$4"
    
    answer_callback "$callback_id" "删除中..."
    
    local snapshot_dir="${BACKUP_DIR:-/backups}/system_snapshots"
    local snapshots=($(find "$snapshot_dir" -name "*.tar*" -type f 2>/dev/null | sort -r))
    
    local file="${snapshots[$snapshot_id]}"
    local name=$(basename "$file")
    
    if rm -f "$file" "${file}.sha256" 2>/dev/null; then
        log_bot "快照已删除: ${name}"
        
        local message="✅ <b>删除成功</b>

已删除: <code>${name}</code>"
        
        edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
    else
        local message="❌ <b>删除失败</b>

可能原因：
• 文件不存在
• 权限不足"
        
        edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
    fi
}

handle_menu_config() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "加载配置..."
    
    source "$CONFIG_FILE"
    
    local message="⚙️ <b>配置信息</b>

<b>🔔 Telegram</b>
启用: ${TELEGRAM_ENABLED}

<b>🌐 远程备份</b>
启用: ${REMOTE_ENABLED}
服务器: ${REMOTE_HOST:-未配置}
路径: ${REMOTE_PATH:-未配置}
保留: ${REMOTE_KEEP_DAYS:-30}天

<b>💾 本地备份</b>
目录: ${BACKUP_DIR}
压缩: 级别${COMPRESSION_LEVEL}
保留: ${LOCAL_KEEP_COUNT}个

<b>⏰ 定时任务</b>
自动备份: ${AUTO_BACKUP_ENABLED}
间隔: ${BACKUP_INTERVAL_DAYS}天
时间: ${BACKUP_TIME}

<i>修改配置请使用主控制台</i>"

    edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
}

handle_menu_help() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "帮助"
    
    local message="❓ <b>使用帮助</b>

<b>📱 按钮操作</b>
• 点击按钮进行操作
• 「🔙 返回」回到上级
• 操作有确认步骤

<b>🖥️ 多VPS管理</b>
• 每条消息显示主机名
• 同一Bot管理多个VPS
• 各VPS独立操作

<b>📸 快照管理</b>
• 创建: 系统完整备份
• 列表: 查看所有快照
• 删除: 清理旧快照

<b>⚙️ 配置</b>
• 修改配置需使用控制台
• 命令: <code>snapsync</code>

<b>💡 提示</b>
• 定期检查快照状态
• 保持足够磁盘空间
• 测试恢复流程"

    edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
}

handle_cancel() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "已取消"
    handle_menu_main "$chat_id" "$message_id" "$callback_id"
}

# ===== 消息路由 =====
handle_message() {
    local chat_id="$1"
    local text="$2"
    
    # 验证授权
    if [[ "$chat_id" != "$TELEGRAM_CHAT_ID" ]]; then
        log_bot "未授权访问: ${chat_id}"
        send_message "$chat_id" "⛔ 未授权

此Bot仅供授权用户使用"
        return
    fi
    
    log_bot "收到消息: ${text}"
    
    case "$text" in
        /start) cmd_start "$chat_id" ;;
        /menu) cmd_menu "$chat_id" ;;
        /status) handle_menu_status "$chat_id" "0" "0" ;;
        /list) handle_menu_list "$chat_id" "0" "0" ;;
        /help) handle_menu_help "$chat_id" "0" "0" ;;
        *)
            send_message_with_buttons "$chat_id" "❓ 未知命令

使用 /menu 打开菜单" "$(get_main_menu_keyboard)"
            ;;
    esac
}

handle_callback() {
    local chat_id="$1"
    local message_id="$2"
    local data="$3"
    local callback_id="$4"
    
    log_bot "收到回调: ${data}"
    
    case "$data" in
        menu_main) handle_menu_main "$chat_id" "$message_id" "$callback_id" ;;
        menu_status) handle_menu_status "$chat_id" "$message_id" "$callback_id" ;;
        menu_list) handle_menu_list "$chat_id" "$message_id" "$callback_id" ;;
        menu_create) handle_menu_create "$chat_id" "$message_id" "$callback_id" ;;
        menu_delete) handle_menu_delete "$chat_id" "$message_id" "$callback_id" ;;
        menu_config) handle_menu_config "$chat_id" "$message_id" "$callback_id" ;;
        menu_help) handle_menu_help "$chat_id" "$message_id" "$callback_id" ;;
        confirm_create) handle_confirm_create "$chat_id" "$message_id" "$callback_id" ;;
        delete_*) 
            local id="${data#delete_}"
            handle_delete_snapshot "$chat_id" "$message_id" "$callback_id" "$id"
            ;;
        confirm_delete_*)
            local id="${data#confirm_delete_}"
            handle_confirm_delete "$chat_id" "$message_id" "$callback_id" "$id"
            ;;
        cancel) handle_cancel "$chat_id" "$message_id" "$callback_id" ;;
        *) answer_callback "$callback_id" "未知操作" ;;
    esac
}

# ===== 主循环 =====
get_updates() {
    curl -sS -X POST "${API_URL}/getUpdates" \
        -d "offset=${LAST_UPDATE_ID}" \
        -d "timeout=60" \
        -d "allowed_updates=[\"message\",\"callback_query\"]"
}

process_updates() {
    local updates="$1"
    
    local ok=$(echo "$updates" | jq -r '.ok')
    [[ "$ok" != "true" ]] && return
    
    local result=$(echo "$updates" | jq -c '.result[]')
    [[ -z "$result" ]] && return
    
    while IFS= read -r update; do
        local update_id=$(echo "$update" | jq -r '.update_id')
        LAST_UPDATE_ID=$((update_id + 1))
        
        # 处理消息
        local message=$(echo "$update" | jq -r '.message')
        if [[ "$message" != "null" ]]; then
            local chat_id=$(echo "$message" | jq -r '.chat.id')
            local text=$(echo "$message" | jq -r '.text // empty')
            [[ -n "$text" ]] && handle_message "$chat_id" "$text"
        fi
        
        # 处理回调
        local callback=$(echo "$update" | jq -r '.callback_query')
        if [[ "$callback" != "null" ]]; then
            local chat_id=$(echo "$callback" | jq -r '.message.chat.id')
            local message_id=$(echo "$callback" | jq -r '.message.message_id')
            local data=$(echo "$callback" | jq -r '.data')
            local callback_id=$(echo "$callback" | jq -r '.id')
            handle_callback "$chat_id" "$message_id" "$data" "$callback_id"
        fi
    done <<< "$result"
}

save_state() {
    echo "LAST_UPDATE_ID=${LAST_UPDATE_ID}" > "$STATE_FILE"
}

load_state() {
    [[ -f "$STATE_FILE" ]] && source "$STATE_FILE"
}

cleanup() {
    save_state
    log_bot "Bot停止"
    exit 0
}

trap cleanup SIGTERM SIGINT

# ===== 主程序 =====
main() {
    log_bot "========================================"
    log_bot "SnapSync Bot v3.0 启动 (按钮交互版)"
    log_bot "主机: ${HOSTNAME}"
    log_bot "========================================"
    
    load_state
    
    # 发送启动通知
    send_message_with_buttons "$TELEGRAM_CHAT_ID" "🤖 <b>Bot已启动</b>

⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')

点击下方按钮开始操作" "$(get_main_menu_keyboard)"
    
    # 主循环
    while true; do
        if updates=$(get_updates); then
            process_updates "$updates"
        else
            log_bot "获取更新失败"
            sleep 5
        fi
        save_state
    done
}

# 检查依赖
if ! command -v jq &>/dev/null; then
    echo "错误: 需要安装 jq"
    exit 1
fi

main "$@"
