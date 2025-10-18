#!/bin/bash

# SnapSync v3.0 - Telegram Bot 服务
# 远程管理快照、查看状态、修改配置

set -euo pipefail

# ===== 路径定义 =====
readonly CONFIG_FILE="/etc/snapsync/config.conf"
readonly LOG_FILE="/var/log/snapsync/bot.log"
readonly STATE_FILE="/var/run/snapsync-bot.state"

# ===== 加载配置 =====
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "错误: 配置文件不存在"
    exit 1
fi

source "$CONFIG_FILE"

# 检查 Telegram 配置
if [[ -z "$TELEGRAM_BOT_TOKEN" ]] || [[ -z "$TELEGRAM_CHAT_ID" ]]; then
    echo "错误: Telegram 配置不完整"
    exit 1
fi

# ===== 全局变量 =====
readonly API_URL="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"
LAST_UPDATE_ID=0

# ===== 工具函数 =====
log_bot() {
    echo "$(date '+%F %T') [BOT] $*" >> "$LOG_FILE"
}

# 发送 Telegram 消息
send_message() {
    local chat_id="$1"
    local text="$2"
    local parse_mode="${3:-HTML}"
    
    local response=$(curl -sS -X POST "${API_URL}/sendMessage" \
        -d "chat_id=${chat_id}" \
        --data-urlencode "text=${text}" \
        -d "parse_mode=${parse_mode}" \
        -d "disable_web_page_preview=true")
    
    if [[ $? -eq 0 ]]; then
        log_bot "消息已发送到 ${chat_id}"
        return 0
    else
        log_bot "发送消息失败: ${response}"
        return 1
    fi
}

# 发送带按钮的消息
send_message_with_keyboard() {
    local chat_id="$1"
    local text="$2"
    local keyboard="$3"
    
    curl -sS -X POST "${API_URL}/sendMessage" \
        -d "chat_id=${chat_id}" \
        --data-urlencode "text=${text}" \
        -d "parse_mode=HTML" \
        -d "reply_markup=${keyboard}" &>/dev/null
}

# 回答回调查询
answer_callback() {
    local callback_id="$1"
    local text="${2:-✓}"
    
    curl -sS -X POST "${API_URL}/answerCallbackQuery" \
        -d "callback_query_id=${callback_id}" \
        --data-urlencode "text=${text}" &>/dev/null
}

# 字节格式化
format_bytes() {
    local bytes="$1"
    if [[ ! "$bytes" =~ ^[0-9]+$ ]]; then echo "0B"; return; fi
    if (( bytes >= 1073741824 )); then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1073741824}")GB"
    elif (( bytes >= 1048576 )); then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1048576}")MB"
    elif (( bytes >= 1024 )); then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1024}")KB"
    else
        echo "${bytes}B"
    fi
}

# ===== Bot 命令处理 =====

# /start 命令
cmd_start() {
    local chat_id="$1"
    
    local message="👋 <b>欢迎使用 SnapSync Bot</b>

🖥️ 主机: ${HOSTNAME}
📍 版本: v3.0

<b>可用命令:</b>
/status - 查看系统状态
/list - 列出所有快照
/create - 创建新快照
/delete - 删除快照
/config - 查看配置
/setconfig - 修改配置
/help - 查看帮助

<i>提示: 点击命令或直接输入使用</i>"

    send_message "$chat_id" "$message"
}

# /help 命令
cmd_help() {
    local chat_id="$1"
    
    local message="📖 <b>命令帮助</b>

<b>📊 查询命令:</b>
/status - 显示系统和快照状态
/list - 列出所有本地快照
/config - 查看当前配置

<b>🔧 管理命令:</b>
/create - 立即创建系统快照
/delete &lt;id&gt; - 删除指定快照
  例: /delete 2

<b>⚙️ 配置命令:</b>
/setconfig &lt;key&gt; &lt;value&gt; - 修改配置
  例: /setconfig LOCAL_KEEP_COUNT 10
  
可配置项:
• LOCAL_KEEP_COUNT - 本地保留数量
• REMOTE_KEEP_DAYS - 远程保留天数
• COMPRESSION_LEVEL - 压缩级别(1-9)
• BACKUP_INTERVAL_DAYS - 备份间隔

<b>🛠️ 系统命令:</b>
/restart - 重启 Bot 服务
/logs - 查看最近日志

<i>需要帮助? 访问项目文档或联系管理员</i>"

    send_message "$chat_id" "$message"
}

# /status 命令
cmd_status() {
    local chat_id="$1"
    
    log_bot "执行 status 命令"
    
    # 系统信息
    local hostname="${HOSTNAME}"
    local uptime_info=$(uptime -p 2>/dev/null || echo "N/A")
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    
    # 磁盘信息
    local backup_dir="${BACKUP_DIR:-/backups}"
    local disk_info=$(df -h "$backup_dir" 2>/dev/null | tail -n1)
    local disk_usage=$(echo "$disk_info" | awk '{print $5}')
    local disk_free=$(echo "$disk_info" | awk '{print $4}')
    
    # 快照信息
    local snapshot_dir="${backup_dir}/system_snapshots"
    local snapshot_count=0
    local latest_snapshot="无"
    local latest_size="N/A"
    local latest_date="N/A"
    
    if [[ -d "$snapshot_dir" ]]; then
        snapshot_count=$(find "$snapshot_dir" -name "*.tar*" -type f 2>/dev/null | wc -l)
        
        local latest_file=$(find "$snapshot_dir" -name "*.tar*" -type f 2>/dev/null | sort -r | head -1)
        if [[ -n "$latest_file" ]]; then
            latest_snapshot=$(basename "$latest_file")
            latest_size=$(format_bytes "$(stat -c%s "$latest_file" 2>/dev/null || echo 0)")
            latest_date=$(date -r "$latest_file" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "N/A")
        fi
    fi
    
    # 下次备份时间
    local next_backup="未启用"
    if [[ "${AUTO_BACKUP_ENABLED}" == "true" ]] || [[ "${AUTO_BACKUP_ENABLED}" == "Y" ]]; then
        next_backup=$(systemctl list-timers snapsync-backup.timer 2>/dev/null | awk 'NR==2 {print $1" "$2}' || echo "N/A")
    fi
    
    # 构建消息
    local message="📊 <b>系统状态</b>
━━━━━━━━━━━━━━━━━━━━━━━

<b>🖥️ 系统信息</b>
主机: ${hostname}
运行时间: ${uptime_info}
负载: ${load_avg}

<b>💾 存储信息</b>
磁盘使用: ${disk_usage}
可用空间: ${disk_free}

<b>📸 快照信息</b>
总数: ${snapshot_count} 个
最新快照: ${latest_snapshot}
大小: ${latest_size}
时间: ${latest_date}

<b>⏰ 定时任务</b>
下次备份: ${next_backup}

<i>更新时间: $(date '+%Y-%m-%d %H:%M:%S')</i>"

    send_message "$chat_id" "$message"
}

# /list 命令
cmd_list() {
    local chat_id="$1"
    
    log_bot "执行 list 命令"
    
    local snapshot_dir="${BACKUP_DIR:-/backups}/system_snapshots"
    
    if [[ ! -d "$snapshot_dir" ]]; then
        send_message "$chat_id" "❌ 快照目录不存在"
        return
    fi
    
    local snapshots=($(find "$snapshot_dir" -name "*.tar*" -type f 2>/dev/null | sort -r))
    
    if [[ ${#snapshots[@]} -eq 0 ]]; then
        send_message "$chat_id" "📋 暂无快照文件"
        return
    fi
    
    local message="📋 <b>快照列表</b> (共 ${#snapshots[@]} 个)
━━━━━━━━━━━━━━━━━━━━━━━
"
    
    for i in "${!snapshots[@]}"; do
        local file="${snapshots[$i]}"
        local name=$(basename "$file")
        local size=$(format_bytes "$(stat -c%s "$file" 2>/dev/null || echo 0)")
        local date=$(date -r "$file" "+%m-%d %H:%M" 2>/dev/null || echo "N/A")
        local checksum="  "
        
        [[ -f "${file}.sha256" ]] && checksum="✓"
        
        message+="
<b>$((i+1)).</b> ${name}
   📦 ${size} | 📅 ${date} | ${checksum}"
    done
    
    message+="

<i>删除快照: /delete &lt;编号&gt;</i>"
    
    # 分割长消息
    if [[ ${#message} -gt 4000 ]]; then
        local part1="${message:0:4000}"
        local part2="${message:4000}"
        send_message "$chat_id" "$part1"
        send_message "$chat_id" "$part2"
    else
        send_message "$chat_id" "$message"
    fi
}

# /create 命令
cmd_create() {
    local chat_id="$1"
    
    log_bot "执行 create 命令"
    
    send_message "$chat_id" "🔄 <b>开始创建快照...</b>

⏳ 请稍候，这可能需要几分钟时间"
    
    # 异步执行备份
    (
        if /opt/snapsync/modules/backup.sh &>>"$LOG_FILE"; then
            send_message "$chat_id" "✅ <b>快照创建成功</b>

使用 /list 查看快照列表"
        else
            send_message "$chat_id" "❌ <b>快照创建失败</b>

请检查日志: /logs"
        fi
    ) &
}

# /delete 命令
cmd_delete() {
    local chat_id="$1"
    local snapshot_id="$2"
    
    if [[ -z "$snapshot_id" ]]; then
        send_message "$chat_id" "❌ 用法: /delete &lt;编号&gt;

示例: /delete 2

使用 /list 查看可用快照"
        return
    fi
    
    log_bot "执行 delete 命令: ${snapshot_id}"
    
    local snapshot_dir="${BACKUP_DIR:-/backups}/system_snapshots"
    local snapshots=($(find "$snapshot_dir" -name "*.tar*" -type f 2>/dev/null | sort -r))
    
    if [[ ! "$snapshot_id" =~ ^[0-9]+$ ]] || (( snapshot_id < 1 )) || (( snapshot_id > ${#snapshots[@]} )); then
        send_message "$chat_id" "❌ 无效的快照编号: ${snapshot_id}

可用范围: 1-${#snapshots[@]}"
        return
    fi
    
    local file="${snapshots[$((snapshot_id-1))]}"
    local name=$(basename "$file")
    
    # 创建确认按钮
    local keyboard='{"inline_keyboard":[[{"text":"✅ 确认删除","callback_data":"confirm_delete_'${snapshot_id}'"},{"text":"❌ 取消","callback_data":"cancel_delete"}]]}'
    
    local message="🗑️ <b>删除确认</b>

即将删除快照:
📸 ${name}

<b>警告: 此操作不可撤销！</b>"
    
    send_message_with_keyboard "$chat_id" "$message" "$keyboard"
}

# 处理删除确认
handle_delete_confirm() {
    local chat_id="$1"
    local snapshot_id="$2"
    local callback_id="$3"
    
    log_bot "确认删除快照: ${snapshot_id}"
    
    local snapshot_dir="${BACKUP_DIR:-/backups}/system_snapshots"
    local snapshots=($(find "$snapshot_dir" -name "*.tar*" -type f 2>/dev/null | sort -r))
    
    local file="${snapshots[$((snapshot_id-1))]}"
    local name=$(basename "$file")
    
    if rm -f "$file" "${file}.sha256" 2>/dev/null; then
        answer_callback "$callback_id" "已删除"
        send_message "$chat_id" "✅ <b>快照已删除</b>

📸 ${name}

使用 /list 查看剩余快照"
        log_bot "快照已删除: ${name}"
    else
        answer_callback "$callback_id" "删除失败"
        send_message "$chat_id" "❌ <b>删除失败</b>

可能是权限问题或文件不存在"
    fi
}

# /config 命令
cmd_config() {
    local chat_id="$1"
    
    log_bot "执行 config 命令"
    
    source "$CONFIG_FILE"
    
    local message="⚙️ <b>当前配置</b>
━━━━━━━━━━━━━━━━━━━━━━━

<b>🔔 Telegram</b>
启用: ${TELEGRAM_ENABLED}

<b>🌐 远程备份</b>
启用: ${REMOTE_ENABLED}
服务器: ${REMOTE_HOST}
端口: ${REMOTE_PORT}
保留: ${REMOTE_KEEP_DAYS} 天

<b>💾 本地备份</b>
目录: ${BACKUP_DIR}
压缩: 级别 ${COMPRESSION_LEVEL}
保留: ${LOCAL_KEEP_COUNT} 个

<b>⏰ 定时任务</b>
启用: ${AUTO_BACKUP_ENABLED}
间隔: ${BACKUP_INTERVAL_DAYS} 天
时间: ${BACKUP_TIME}

<i>修改配置: /setconfig &lt;key&gt; &lt;value&gt;</i>"

    send_message "$chat_id" "$message"
}

# /setconfig 命令
cmd_setconfig() {
    local chat_id="$1"
    local key="$2"
    local value="$3"
    
    if [[ -z "$key" ]] || [[ -z "$value" ]]; then
        send_message "$chat_id" "❌ 用法: /setconfig &lt;key&gt; &lt;value&gt;

示例: /setconfig LOCAL_KEEP_COUNT 10

可配置项:
• LOCAL_KEEP_COUNT
• REMOTE_KEEP_DAYS
• COMPRESSION_LEVEL
• BACKUP_INTERVAL_DAYS"
        return
    fi
    
    log_bot "执行 setconfig 命令: ${key}=${value}"
    
    # 验证配置项
    case "$key" in
        LOCAL_KEEP_COUNT|REMOTE_KEEP_DAYS|BACKUP_INTERVAL_DAYS)
            if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < 1 )); then
                send_message "$chat_id" "❌ ${key} 必须是正整数"
                return
            fi
            ;;
        COMPRESSION_LEVEL)
            if [[ ! "$value" =~ ^[1-9]$ ]]; then
                send_message "$chat_id" "❌ 压缩级别必须是 1-9"
                return
            fi
            ;;
        TELEGRAM_ENABLED|REMOTE_ENABLED|AUTO_BACKUP_ENABLED)
            if [[ ! "$value" =~ ^(true|false|Y|N)$ ]]; then
                send_message "$chat_id" "❌ 值必须是 true/false 或 Y/N"
                return
            fi
            ;;
        *)
            send_message "$chat_id" "❌ 未知的配置项: ${key}"
            return
            ;;
    esac
    
    # 修改配置文件
    if sed -i "s/^${key}=.*/${key}=\"${value}\"/" "$CONFIG_FILE" 2>/dev/null; then
        send_message "$chat_id" "✅ <b>配置已更新</b>

${key} = ${value}

<i>某些配置可能需要重启服务生效</i>"
        log_bot "配置已更新: ${key}=${value}"
        
        # 重新加载配置
        source "$CONFIG_FILE"
    else
        send_message "$chat_id" "❌ 配置更新失败"
    fi
}

# /logs 命令
cmd_logs() {
    local chat_id="$1"
    
    log_bot "执行 logs 命令"
    
    local backup_log="/var/log/snapsync/backup.log"
    
    if [[ ! -f "$backup_log" ]]; then
        send_message "$chat_id" "❌ 日志文件不存在"
        return
    fi
    
    local recent_logs=$(tail -20 "$backup_log" | sed 's/</\&lt;/g; s/>/\&gt;/g')
    
    local message="📋 <b>最近日志</b> (20行)
━━━━━━━━━━━━━━━━━━━━━━━

<code>${recent_logs}</code>

<i>完整日志: ${backup_log}</i>"
    
    send_message "$chat_id" "$message"
}

# /restart 命令
cmd_restart() {
    local chat_id="$1"
    
    log_bot "执行 restart 命令"
    
    send_message "$chat_id" "🔄 <b>重启 Bot 服务...</b>

⏳ 请稍候片刻"
    
    # 延迟重启以确保消息发送
    (
        sleep 2
        systemctl restart snapsync-bot.service
    ) &
}

# ===== 消息路由 =====
handle_message() {
    local chat_id="$1"
    local text="$2"
    local message_id="$3"
    
    # 验证 chat_id
    if [[ "$chat_id" != "$TELEGRAM_CHAT_ID" ]]; then
        log_bot "未授权的访问尝试: ${chat_id}"
        send_message "$chat_id" "⛔ 未授权

此 Bot 仅供授权用户使用"
        return
    fi
    
    log_bot "收到消息: ${text}"
    
    # 解析命令和参数
    local cmd=$(echo "$text" | awk '{print $1}')
    local arg1=$(echo "$text" | awk '{print $2}')
    local arg2=$(echo "$text" | awk '{print $3}')
    
    case "$cmd" in
        /start)
            cmd_start "$chat_id"
            ;;
        /help)
            cmd_help "$chat_id"
            ;;
        /status)
            cmd_status "$chat_id"
            ;;
        /list)
            cmd_list "$chat_id"
            ;;
        /create)
            cmd_create "$chat_id"
            ;;
        /delete)
            cmd_delete "$chat_id" "$arg1"
            ;;
        /config)
            cmd_config "$chat_id"
            ;;
        /setconfig)
            cmd_setconfig "$chat_id" "$arg1" "$arg2"
            ;;
        /logs)
            cmd_logs "$chat_id"
            ;;
        /restart)
            cmd_restart "$chat_id"
            ;;
        *)
            send_message "$chat_id" "❓ 未知命令: ${cmd}

使用 /help 查看可用命令"
            ;;
    esac
}

# 处理回调查询
handle_callback() {
    local chat_id="$1"
    local data="$2"
    local callback_id="$3"
    
    log_bot "收到回调: ${data}"
    
    if [[ "$data" =~ ^confirm_delete_([0-9]+)$ ]]; then
        local snapshot_id="${BASH_REMATCH[1]}"
        handle_delete_confirm "$chat_id" "$snapshot_id" "$callback_id"
    elif [[ "$data" == "cancel_delete" ]]; then
        answer_callback "$callback_id" "已取消"
        send_message "$chat_id" "❌ 操作已取消"
    else
        answer_callback "$callback_id" "未知操作"
    fi
}

# ===== 主循环 =====
get_updates() {
    local timeout=60
    local response
    
    response=$(curl -sS -X POST "${API_URL}/getUpdates" \
        -d "offset=${LAST_UPDATE_ID}" \
        -d "timeout=${timeout}" \
        -d "allowed_updates=[\"message\",\"callback_query\"]")
    
    if [[ $? -ne 0 ]]; then
        log_bot "获取更新失败"
        return 1
    fi
    
    echo "$response"
}

process_updates() {
    local updates="$1"
    
    # 检查是否有更新
    local ok=$(echo "$updates" | jq -r '.ok')
    if [[ "$ok" != "true" ]]; then
        return
    fi
    
    local result=$(echo "$updates" | jq -c '.result[]')
    
    if [[ -z "$result" ]]; then
        return
    fi
    
    while IFS= read -r update; do
        local update_id=$(echo "$update" | jq -r '.update_id')
        
        # 更新偏移量
        LAST_UPDATE_ID=$((update_id + 1))
        
        # 处理消息
        local message=$(echo "$update" | jq -r '.message')
        if [[ "$message" != "null" ]]; then
            local chat_id=$(echo "$message" | jq -r '.chat.id')
            local text=$(echo "$message" | jq -r '.text // empty')
            local message_id=$(echo "$message" | jq -r '.message_id')
            
            if [[ -n "$text" ]]; then
                handle_message "$chat_id" "$text" "$message_id"
            fi
        fi
        
        # 处理回调查询
        local callback=$(echo "$update" | jq -r '.callback_query')
        if [[ "$callback" != "null" ]]; then
            local chat_id=$(echo "$callback" | jq -r '.message.chat.id')
            local data=$(echo "$callback" | jq -r '.data')
            local callback_id=$(echo "$callback" | jq -r '.id')
            
            handle_callback "$chat_id" "$data" "$callback_id"
        fi
    done <<< "$result"
}

# 保存状态
save_state() {
    echo "LAST_UPDATE_ID=${LAST_UPDATE_ID}" > "$STATE_FILE"
}

# 加载状态
load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE"
        log_bot "状态已加载: update_id=${LAST_UPDATE_ID}"
    fi
}

# 清理函数
cleanup() {
    save_state
    log_bot "Bot 服务停止"
    exit 0
}

trap cleanup SIGTERM SIGINT

# ===== 主程序 =====
main() {
    log_bot "========================================="
    log_bot "SnapSync Telegram Bot v3.0 启动"
    log_bot "主机: ${HOSTNAME}"
    log_bot "Chat ID: ${TELEGRAM_CHAT_ID}"
    log_bot "========================================="
    
    # 加载状态
    load_state
    
    # 发送启动通知
    send_message "$TELEGRAM_CHAT_ID" "🤖 <b>Bot 已启动</b>

🖥️ 主机: ${HOSTNAME}
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')

使用 /help 查看可用命令"
    
    # 主循环
    while true; do
        local updates
        
        if updates=$(get_updates); then
            process_updates "$updates"
        else
            log_bot "获取更新失败，等待重试..."
            sleep 5
        fi
        
        # 定期保存状态
        save_state
    done
}

# 检查依赖
if ! command -v jq &>/dev/null; then
    echo "错误: 需要安装 jq"
    echo "安装: apt-get install jq 或 yum install jq"
    exit 1
fi

# 运行主程序
main "$@"
