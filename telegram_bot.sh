#!/bin/bash

# SnapSync v3.0 - Telegram Bot（多VPS管理版）
# 支持：同一个Bot管理多个VPS

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
    echo "$(date '+%F %T') [$HOSTNAME] [BOT] $*" >> "$LOG_FILE"
}

# 发送消息（自动添加主机标识）
send_message() {
    local chat_id="$1"
    local text="$2"
    local parse_mode="${3:-HTML}"
    
    # 在消息开头添加VPS标识
    local vps_header="🖥️ <b>${HOSTNAME}</b>
━━━━━━━━━━━━━━━━━━━━━━━
"
    local full_text="${vps_header}${text}"
    
    local response=$(curl -sS -X POST "${API_URL}/sendMessage" \
        -d "chat_id=${chat_id}" \
        --data-urlencode "text=${full_text}" \
        -d "parse_mode=${parse_mode}" \
        -d "disable_web_page_preview=true")
    
    if [[ $? -eq 0 ]]; then
        log_bot "消息已发送"
        return 0
    else
        log_bot "发送失败: ${response}"
        return 1
    fi
}

# 发送带按钮的消息
send_message_with_keyboard() {
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

cmd_start() {
    local chat_id="$1"
    
    local message="👋 <b>欢迎使用 SnapSync Bot</b>

📍 当前VPS: ${HOSTNAME}
📊 版本: v3.0

<b>可用命令:</b>
/status - 系统状态
/list - 快照列表
/create - 创建快照
/delete - 删除快照
/config - 查看配置
/help - 帮助信息

<b>💡 多VPS管理:</b>
所有消息都会显示主机名
可以在多个VPS上使用同一个Bot

<i>提示: 点击命令或直接输入</i>"

    send_message "$chat_id" "$message"
}

cmd_help() {
    local chat_id="$1"
    
    local message="📖 <b>命令帮助</b>

<b>📊 查询命令:</b>
/status - 显示系统状态
/list - 列出所有快照
/config - 查看配置信息

<b>🔧 管理命令:</b>
/create - 创建系统快照
/delete &lt;id&gt; - 删除快照
  例: /delete 2

<b>⚙️ 配置命令:</b>
/setconfig &lt;key&gt; &lt;value&gt;
  例: /setconfig LOCAL_KEEP_COUNT 10

<b>🛠️ 系统命令:</b>
/restart - 重启Bot服务
/logs - 查看最近日志

<b>🖥️ 多VPS管理:</b>
每条消息开头都会显示主机名
在多个VPS上配置相同的Bot Token和Chat ID
Bot会自动区分不同的VPS

<i>需要帮助? 查看文档或联系管理员</i>"

    send_message "$chat_id" "$message"
}

cmd_status() {
    local chat_id="$1"
    
    log_bot "执行 status 命令"
    
    # 系统信息
    local uptime_info=$(uptime -p 2>/dev/null || echo "N/A")
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    local cpu_count=$(nproc)
    
    # 内存信息
    local mem_info=$(free -h | awk 'NR==2 {print $3"/"$2}')
    
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
            latest_date=$(date -r "$latest_file" "+%m-%d %H:%M" 2>/dev/null || echo "N/A")
        fi
    fi
    
    # 下次备份
    local next_backup="未启用"
    if [[ "${AUTO_BACKUP_ENABLED}" == "true" ]] || [[ "${AUTO_BACKUP_ENABLED}" == "Y" ]]; then
        next_backup=$(systemctl list-timers snapsync-backup.timer 2>/dev/null | awk 'NR==2 {print $1" "$2}' || echo "N/A")
    fi
    
    # IP地址
    local public_ip=$(curl -sS -m 5 ifconfig.me 2>/dev/null || echo "N/A")
    
    local message="📊 <b>系统状态</b>

<b>🖥️ 系统信息</b>
运行时间: ${uptime_info}
CPU负载: ${load_avg} (${cpu_count}核)
内存使用: ${mem_info}
公网IP: ${public_ip}

<b>💾 存储信息</b>
磁盘使用: ${disk_usage}
可用空间: ${disk_free}
备份目录: ${backup_dir}

<b>📸 快照信息</b>
快照总数: ${snapshot_count} 个
最新快照: ${latest_snapshot}
快照大小: ${latest_size}
创建时间: ${latest_date}

<b>⏰ 定时任务</b>
自动备份: ${AUTO_BACKUP_ENABLED}
下次运行: ${next_backup}

<b>🌐 远程备份</b>
远程上传: ${REMOTE_ENABLED}
远程主机: ${REMOTE_HOST:-未配置}

<i>更新: $(date '+%m-%d %H:%M:%S')</i>"

    send_message "$chat_id" "$message"
}

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
    
    local message="📋 <b>快照列表</b> (${#snapshots[@]}个)
"
    
    for i in "${!snapshots[@]}"; do
        local file="${snapshots[$i]}"
        local name=$(basename "$file")
        local size=$(format_bytes "$(stat -c%s "$file" 2>/dev/null || echo 0)")
        local date=$(date -r "$file" "+%m-%d %H:%M" 2>/dev/null || echo "N/A")
        
        message+="
<b>$((i+1)).</b> <code>${name}</code>
   📦 ${size} | 📅 ${date}"
    done
    
    message+="

<i>删除快照: /delete &lt;编号&gt;</i>"
    
    # 分割长消息
    if [[ ${#message} -gt 4000 ]]; then
        local part1="${message:0:4000}"
        local part2="${message:4000}"
        send_message "$chat_id" "$part1"
        sleep 1
        send_message "$chat_id" "$part2"
    else
        send_message "$chat_id" "$message"
    fi
}

cmd_create() {
    local chat_id="$1"
    
    log_bot "执行 create 命令"
    
    send_message "$chat_id" "🔄 <b>开始创建快照</b>

⏳ 备份进行中...
这可能需要几分钟

备份完成后会发送通知"
    
    # 异步执行备份
    (
        if /opt/snapsync/modules/backup.sh &>>"$LOG_FILE"; then
            send_message "$chat_id" "✅ <b>快照创建成功</b>

使用 /list 查看快照列表"
        else
            send_message "$chat_id" "❌ <b>快照创建失败</b>

请使用 /logs 查看错误日志"
        fi
    ) &
}

cmd_delete() {
    local chat_id="$1"
    local snapshot_id="$2"
    
    if [[ -z "$snapshot_id" ]]; then
        send_message "$chat_id" "❌ 用法: /delete &lt;编号&gt;

示例: /delete 2

先使用 /list 查看快照编号"
        return
    fi
    
    log_bot "执行 delete 命令: ${snapshot_id}"
    
    local snapshot_dir="${BACKUP_DIR:-/backups}/system_snapshots"
    local snapshots=($(find "$snapshot_dir" -name "*.tar*" -type f 2>/dev/null | sort -r))
    
    if [[ ! "$snapshot_id" =~ ^[0-9]+$ ]] || (( snapshot_id < 1 )) || (( snapshot_id > ${#snapshots[@]} )); then
        send_message "$chat_id" "❌ 无效的编号: ${snapshot_id}

可用范围: 1-${#snapshots[@]}
使用 /list 查看快照"
        return
    fi
    
    local file="${snapshots[$((snapshot_id-1))]}"
    local name=$(basename "$file")
    
    # 创建确认按钮
    local keyboard='{"inline_keyboard":[[{"text":"✅ 确认删除","callback_data":"confirm_delete_'${snapshot_id}'"},{"text":"❌ 取消","callback_data":"cancel_delete"}]]}'
    
    local message="🗑️ <b>删除确认</b>

快照文件:
<code>${name}</code>

<b>⚠️ 警告: 此操作不可撤销！</b>"
    
    send_message_with_keyboard "$chat_id" "$message" "$keyboard"
}

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
        send_message "$chat_id" "✅ <b>删除成功</b>

已删除: <code>${name}</code>

使用 /list 查看剩余快照"
        log_bot "快照已删除: ${name}"
    else
        answer_callback "$callback_id" "删除失败"
        send_message "$chat_id" "❌ <b>删除失败</b>

可能原因：
• 文件不存在
• 权限不足

请检查日志或手动删除"
    fi
}

cmd_config() {
    local chat_id="$1"
    
    log_bot "执行 config 命令"
    
    source "$CONFIG_FILE"
    
    local message="⚙️ <b>当前配置</b>

<b>🔔 Telegram</b>
启用: ${TELEGRAM_ENABLED}
Chat ID: ${TELEGRAM_CHAT_ID}

<b>🌐 远程备份</b>
启用: ${REMOTE_ENABLED}
服务器: ${REMOTE_HOST:-未配置}
端口: ${REMOTE_PORT:-22}
路径: ${REMOTE_PATH:-未配置}
保留: ${REMOTE_KEEP_DAYS:-30}天

<b>💾 本地备份</b>
目录: ${BACKUP_DIR}
压缩: 级别${COMPRESSION_LEVEL}
线程: ${PARALLEL_THREADS}
保留: ${LOCAL_KEEP_COUNT}个

<b>⏰ 定时任务</b>
启用: ${AUTO_BACKUP_ENABLED}
间隔: ${BACKUP_INTERVAL_DAYS}天
时间: ${BACKUP_TIME}

<i>修改: /setconfig &lt;key&gt; &lt;value&gt;</i>"

    send_message "$chat_id" "$message"
}

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
    
    log_bot "执行 setconfig: ${key}=${value}"
    
    # 验证
    case "$key" in
        LOCAL_KEEP_COUNT|REMOTE_KEEP_DAYS|BACKUP_INTERVAL_DAYS)
            if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < 1 )); then
                send_message "$chat_id" "❌ ${key} 必须是正整数"
                return
            fi
            ;;
        COMPRESSION_LEVEL)
            if [[ ! "$value" =~ ^[1-9]$ ]]; then
                send_message "$chat_id" "❌ 压缩级别必须是1-9"
                return
            fi
            ;;
        *)
            send_message "$chat_id" "❌ 未知的配置项: ${key}"
            return
            ;;
    esac
    
    # 修改
    if sed -i "s/^${key}=.*/${key}=\"${value}\"/" "$CONFIG_FILE" 2>/dev/null; then
        send_message "$chat_id" "✅ <b>配置已更新</b>

${key} = ${value}

<i>部分配置需要重启服务生效</i>
使用 /restart 重启Bot"
        log_bot "配置已更新: ${key}=${value}"
        source "$CONFIG_FILE"
    else
        send_message "$chat_id" "❌ 配置更新失败"
    fi
}

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

<code>${recent_logs}</code>

<i>完整日志: ${backup_log}</i>"
    
    send_message "$chat_id" "$message"
}

cmd_restart() {
    local chat_id="$1"
    
    log_bot "执行 restart 命令"
    
    send_message "$chat_id" "🔄 <b>重启Bot服务</b>

⏳ 正在重启..."
    
    (
        sleep 2
        systemctl restart snapsync-bot.service
    ) &
}

# ===== 消息路由 =====
handle_message() {
    local chat_id="$1"
    local text="$2"
    
    # 验证chat_id
    if [[ "$chat_id" != "$TELEGRAM_CHAT_ID" ]]; then
        log_bot "未授权访问: ${chat_id}"
        send_message "$chat_id" "⛔ 未授权

此Bot仅供授权用户使用"
        return
    fi
    
    log_bot "收到消息: ${text}"
    
    # 解析命令
    local cmd=$(echo "$text" | awk '{print $1}')
    local arg1=$(echo "$text" | awk '{print $2}')
    local arg2=$(echo "$text" | awk '{print $3}')
    
    case "$cmd" in
        /start) cmd_start "$chat_id" ;;
        /help) cmd_help "$chat_id" ;;
        /status) cmd_status "$chat_id" ;;
        /list) cmd_list "$chat_id" ;;
        /create) cmd_create "$chat_id" ;;
        /delete) cmd_delete "$chat_id" "$arg1" ;;
        /config) cmd_config "$chat_id" ;;
        /setconfig) cmd_setconfig "$chat_id" "$arg1" "$arg2" ;;
        /logs) cmd_logs "$chat_id" ;;
        /restart) cmd_restart "$chat_id" ;;
        *)
            send_message "$chat_id" "❓ 未知命令: ${cmd}

使用 /help 查看可用命令"
            ;;
    esac
}

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
    
    curl -sS -X POST "${API_URL}/getUpdates" \
        -d "offset=${LAST_UPDATE_ID}" \
        -d "timeout=${timeout}" \
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
            local data=$(echo "$callback" | jq -r '.data')
            local callback_id=$(echo "$callback" | jq -r '.id')
            
            handle_callback "$chat_id" "$data" "$callback_id"
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
    log_bot "Bot服务停止"
    exit 0
}

trap cleanup SIGTERM SIGINT

# ===== 主程序 =====
main() {
    log_bot "========================================"
    log_bot "SnapSync Bot v3.0 启动 (多VPS支持)"
    log_bot "主机: ${HOSTNAME}"
    log_bot "Chat ID: ${TELEGRAM_CHAT_ID}"
    log_bot "========================================"
    
    load_state
    
    # 发送启动通知
    send_message "$TELEGRAM_CHAT_ID" "🤖 <b>Bot已启动</b>

⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')

使用 /help 查看命令
使用 /status 查看状态"
    
    # 主循环
    while true; do
        if updates=$(get_updates); then
            process_updates "$updates"
        else
            log_bot "获取更新失败，等待重试..."
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
