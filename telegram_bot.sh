#!/bin/bash

# SnapSync v3.0 - Telegram Bot（完整功能版）
# 新增：创建快照、恢复快照、配置编辑

set -u

# ===== 路径定义 =====
CONFIG_FILE="/etc/snapsync/config.conf"
LOG_FILE="/var/log/snapsync/bot.log"
STATE_FILE="/var/run/snapsync-bot.state"

# ===== 加载配置 =====
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "错误: 配置文件不存在" >&2
    exit 1
fi

source "$CONFIG_FILE" || {
    echo "错误: 无法加载配置文件" >&2
    exit 1
}

if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]] || [[ -z "${TELEGRAM_CHAT_ID:-}" ]]; then
    echo "错误: Telegram配置不完整" >&2
    exit 1
fi

# ===== 全局变量 =====
API_URL="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"
LAST_UPDATE_ID=0
HOSTNAME="${HOSTNAME:-$(hostname)}"
BACKUP_DIR="${BACKUP_DIR:-/backups}"

# ===== 工具函数 =====
log_bot() {
    echo "$(date '+%F %T') [$HOSTNAME] $*" >> "$LOG_FILE"
}

send_message() {
    local chat_id="$1"
    local text="$2"
    local parse_mode="${3:-HTML}"
    
    local vps_header="🖥️ <b>${HOSTNAME}</b>
━━━━━━━━━━━━━━━━━━━━━━━
"
    local full_text="${vps_header}${text}"
    
    local retry=0
    local max_retry=3
    
    while (( retry < max_retry )); do
        if curl -sS -m 10 -X POST "${API_URL}/sendMessage" \
            -d "chat_id=${chat_id}" \
            --data-urlencode "text=${full_text}" \
            -d "parse_mode=${parse_mode}" \
            -d "disable_web_page_preview=true" &>/dev/null; then
            log_bot "消息已发送"
            return 0
        fi
        
        ((retry++))
        log_bot "发送失败，重试 ${retry}/${max_retry}"
        sleep 2
    done
    
    log_bot "发送消息失败（已重试${max_retry}次）"
    return 1
}

send_message_with_buttons() {
    local chat_id="$1"
    local text="$2"
    local keyboard="$3"
    
    local vps_header="🖥️ <b>${HOSTNAME}</b>
━━━━━━━━━━━━━━━━━━━━━━━
"
    local full_text="${vps_header}${text}"
    
    local retry=0
    local max_retry=3
    
    while (( retry < max_retry )); do
        if curl -sS -m 10 -X POST "${API_URL}/sendMessage" \
            -d "chat_id=${chat_id}" \
            --data-urlencode "text=${full_text}" \
            -d "parse_mode=HTML" \
            -d "reply_markup=${keyboard}" &>/dev/null; then
            log_bot "按钮消息已发送"
            return 0
        fi
        
        ((retry++))
        log_bot "发送失败，重试 ${retry}/${max_retry}"
        sleep 2
    done
    
    log_bot "发送按钮消息失败"
    return 1
}

edit_message() {
    local chat_id="$1"
    local message_id="$2"
    local text="$3"
    local keyboard="$4"
    
    local vps_header="🖥️ <b>${HOSTNAME}</b>
━━━━━━━━━━━━━━━━━━━━━━━
"
    local full_text="${vps_header}${text}"
    
    curl -sS -m 10 -X POST "${API_URL}/editMessageText" \
        -d "chat_id=${chat_id}" \
        -d "message_id=${message_id}" \
        --data-urlencode "text=${full_text}" \
        -d "parse_mode=HTML" \
        -d "reply_markup=${keyboard}" &>/dev/null || {
        log_bot "编辑消息失败（可能消息内容未改变）"
        return 1
    }
}

answer_callback() {
    local callback_id="$1"
    local text="${2:-✓}"
    
    curl -sS -m 5 -X POST "${API_URL}/answerCallbackQuery" \
        -d "callback_query_id=${callback_id}" \
        --data-urlencode "text=${text}" &>/dev/null || true
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

get_main_menu_keyboard() {
    echo '{
  "inline_keyboard": [
    [{"text": "📊 系统状态", "callback_data": "menu_status"}],
    [{"text": "📋 快照列表", "callback_data": "menu_list"}],
    [{"text": "🔄 创建快照", "callback_data": "menu_create"}],
    [{"text": "♻️ 恢复快照", "callback_data": "menu_restore"}],
    [{"text": "⚙️ 配置管理", "callback_data": "menu_config"}],
    [{"text": "🗑️ 删除快照", "callback_data": "menu_delete"}],
    [{"text": "❓ 帮助", "callback_data": "menu_help"}]
  ]
}'
}

get_back_button() {
    echo '{
  "inline_keyboard": [
    [{"text": "🔙 返回主菜单", "callback_data": "menu_main"}]
  ]
}'
}

# ===== Bot 命令处理 =====

cmd_start() {
    local chat_id="$1"
    
    local message="👋 <b>欢迎使用 SnapSync Bot</b>

📍 当前VPS: ${HOSTNAME}
📊 版本: v3.0

<b>🎯 功能列表:</b>
• 📊 查看系统状态
• 📋 浏览快照列表
• 🔄 创建系统快照
• ♻️ 恢复系统快照
• ⚙️ 管理配置
• 🗑️ 删除旧快照

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
    
    local uptime_info=$(uptime -p 2>/dev/null || echo "N/A")
    local load_avg=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | xargs | cut -d',' -f1 || echo "N/A")
    local mem_info=$(free -h 2>/dev/null | awk 'NR==2 {print $3"/"$2}' || echo "N/A")
    
    local disk_info=$(df -h "$BACKUP_DIR" 2>/dev/null | tail -n1)
    local disk_usage=$(echo "$disk_info" | awk '{print $5}' || echo "N/A")
    local disk_free=$(echo "$disk_info" | awk '{print $4}' || echo "N/A")
    
    local snapshot_dir="${BACKUP_DIR}/system_snapshots"
    local snapshot_count=$(find "$snapshot_dir" -name "*.tar.gz" -o -name "*.tar.bz2" -o -name "*.tar.xz" 2>/dev/null | wc -l || echo 0)
    
    local latest="无"
    local latest_size="N/A"
    local latest_date="N/A"
    
    if (( snapshot_count > 0 )); then
        local latest_file=$(find "$snapshot_dir" -name "*.tar*" -type f 2>/dev/null | grep -v '\.sha256$' | sort -r | head -1 || echo "")
        if [[ -n "$latest_file" && -f "$latest_file" ]]; then
            latest=$(basename "$latest_file")
            latest_size=$(format_bytes "$(stat -c%s "$latest_file" 2>/dev/null || echo 0)")
            latest_date=$(date -r "$latest_file" "+%m-%d %H:%M" 2>/dev/null || echo "N/A")
        fi
    fi
    
    local next_backup="未启用"
    if [[ "${AUTO_BACKUP_ENABLED:-false}" =~ ^[Yy]|true$ ]]; then
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
自动备份: ${AUTO_BACKUP_ENABLED:-false}
下次运行: ${next_backup}

<i>更新: $(date '+%m-%d %H:%M')</i>"

    edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
}

handle_menu_list() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "加载中..."
    
    local snapshot_dir="${BACKUP_DIR}/system_snapshots"
    
    # 使用 find 排除 .sha256
    local snapshots=()
    while IFS= read -r -d '' file; do
        if [[ "$file" != *.sha256 ]]; then
            snapshots+=("$file")
        fi
    done < <(find "$snapshot_dir" -name "*.tar*" -type f -print0 2>/dev/null | sort -zr)
    
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
        local date=$(date -r "$file" "+%m-%d %H:%M" 2>/dev/null || echo "未知")
        
        message+="<b>$((i+1)).</b> <code>${name:17:14}</code>
   📦 ${size} | 📅 ${date}

"
    done
    
    if (( ${#snapshots[@]} > max_show )); then
        message+="
<i>... 还有 $((${#snapshots[@]} - max_show)) 个快照</i>"
    fi
    
    message+="

<i>恢复/删除快照请使用对应功能</i>"
    
    edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
}

# ===== 创建快照 =====
handle_menu_create() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "创建快照"
    
    local message="🔄 <b>创建快照</b>

即将创建系统完整快照

<b>⚠️ 注意事项:</b>
• 备份需要几分钟时间
• 期间请勿关闭服务器
• 会占用一定磁盘空间
• 完成后自动发送通知

<b>📦 包含内容:</b>
• 系统配置文件
• 用户数据
• 已安装软件

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
    
    answer_callback "$callback_id" "开始创建..."
    
    local message="🔄 <b>备份进行中...</b>

⏳ 正在创建快照
📊 请稍候，完成后会通知

<i>预计需要 3-10 分钟</i>"
    
    edit_message "$chat_id" "$message_id" "$message" ""
    
    # 后台执行备份
    (
        log_bot "开始创建快照（通过Bot触发）"
        /opt/snapsync/modules/backup.sh >> "$LOG_FILE" 2>&1
        local result=$?
        
        if [[ $result -eq 0 ]]; then
            log_bot "快照创建成功"
        else
            log_bot "快照创建失败: exit code $result"
            send_message "$chat_id" "❌ <b>创建失败</b>

请检查日志: /var/log/snapsync/backup.log"
        fi
    ) &
}

# ===== 恢复快照 =====
handle_menu_restore() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "恢复快照"
    
    local snapshot_dir="${BACKUP_DIR}/system_snapshots"
    
    # 获取快照列表（排除 .sha256）
    local snapshots=()
    while IFS= read -r -d '' file; do
        if [[ "$file" != *.sha256 ]]; then
            snapshots+=("$file")
        fi
    done < <(find "$snapshot_dir" -name "*.tar*" -type f -print0 2>/dev/null | sort -zr)
    
    if [[ ${#snapshots[@]} -eq 0 ]]; then
        local message="♻️ <b>恢复快照</b>

暂无可恢复的快照

<i>请先创建快照</i>"
        edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
        return
    fi
    
    # 构建快照选择按钮（最多5个）
    local buttons="["
    local count=0
    for i in "${!snapshots[@]}"; do
        (( count >= 5 )) && break
        
        local file="${snapshots[$i]}"
        local name=$(basename "$file")
        local short_name="${name:17:14}"
        
        buttons+="{\"text\": \"$((i+1)). ${short_name}\", \"callback_data\": \"restore_${i}\"},"
        ((count++))
    done
    buttons="${buttons%,}]"
    
    local keyboard="{\"inline_keyboard\":[$buttons,[{\"text\":\"🔙 返回\",\"callback_data\":\"menu_main\"}]]}"
    
    local message="♻️ <b>恢复快照</b>

选择要恢复的快照:

<b>⚠️ 警告:</b>
恢复操作不可撤销，请谨慎选择！

<i>建议选择最新的快照</i>"
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
}

handle_restore_snapshot() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local snapshot_id="$4"
    
    answer_callback "$callback_id" "准备恢复..."
    
    local snapshot_dir="${BACKUP_DIR}/system_snapshots"
    
    # 获取快照列表（使用相同的方法）
    local snapshots=()
    while IFS= read -r -d '' file; do
        if [[ "$file" != *.sha256 ]]; then
            snapshots+=("$file")
        fi
    done < <(find "$snapshot_dir" -name "*.tar*" -type f -print0 2>/dev/null | sort -zr)
    
    if [[ ! "$snapshot_id" =~ ^[0-9]+$ ]] || (( snapshot_id >= ${#snapshots[@]} )); then
        answer_callback "$callback_id" "无效的快照"
        return
    fi
    
    local file="${snapshots[$snapshot_id]}"
    local name=$(basename "$file")
    local size=$(format_bytes "$(stat -c%s "$file" 2>/dev/null || echo 0)")
    
    local message="♻️ <b>确认恢复</b>

快照: <code>${name}</code>
大小: ${size}

<b>⚠️ 最后警告:</b>
• 此操作不可撤销
• 将覆盖当前系统
• 建议选择「智能恢复」
• 恢复后需要重启

<b>恢复模式:</b>
• 智能恢复: 保留网络/SSH配置
• 完全恢复: 恢复所有内容（谨慎）

选择恢复模式:"

    local keyboard="{
  \"inline_keyboard\": [
    [{\"text\": \"🛡️ 智能恢复\", \"callback_data\": \"confirm_restore_smart_${snapshot_id}\"}],
    [{\"text\": \"🔧 完全恢复\", \"callback_data\": \"confirm_restore_full_${snapshot_id}\"}],
    [{\"text\": \"❌ 取消\", \"callback_data\": \"menu_restore\"}]
  ]
}"
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
}

handle_confirm_restore() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local restore_mode="$4"
    local snapshot_id="$5"
    
    answer_callback "$callback_id" "开始恢复..."
    
    # 获取快照文件
    local snapshot_dir="${BACKUP_DIR}/system_snapshots"
    local snapshots=()
    while IFS= read -r -d '' file; do
        if [[ "$file" != *.sha256 ]]; then
            snapshots+=("$file")
        fi
    done < <(find "$snapshot_dir" -name "*.tar*" -type f -print0 2>/dev/null | sort -zr)
    
    local file="${snapshots[$snapshot_id]}"
    local name=$(basename "$file")
    
    local mode_text="智能恢复"
    [[ "$restore_mode" == "full" ]] && mode_text="完全恢复"
    
    local message="♻️ <b>恢复进行中...</b>

📸 快照: ${name}
🔧 模式: ${mode_text}

⏳ 正在恢复系统
⚠️ 请勿关闭服务器

<i>完成后会通知，建议重启</i>"
    
    edit_message "$chat_id" "$message_id" "$message" ""
    
    # 记录到文件，用于恢复脚本读取
    echo "$file" > /tmp/snapsync_restore_target
    echo "$restore_mode" > /tmp/snapsync_restore_mode
    
    # 提示用户手动恢复（因为恢复操作危险，不自动执行）
    send_message "$chat_id" "⚠️ <b>恢复准备就绪</b>

为了安全，请手动执行恢复:

<code>sudo snapsync</code>
选择: 2) 恢复系统快照

或直接运行:
<code>sudo snapsync-restore</code>

快照: ${name}
模式: ${mode_text}"
}

# ===== 删除快照 =====
handle_menu_delete() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "删除快照"
    
    local snapshot_dir="${BACKUP_DIR}/system_snapshots"
    
    # 获取快照列表（排除 .sha256）
    local snapshots=()
    while IFS= read -r -d '' file; do
        if [[ "$file" != *.sha256 ]]; then
            snapshots+=("$file")
        fi
    done < <(find "$snapshot_dir" -name "*.tar*" -type f -print0 2>/dev/null | sort -zr)
    
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
    
    local snapshot_dir="${BACKUP_DIR}/system_snapshots"
    
    # 获取快照列表（排除 .sha256）
    local snapshots=()
    while IFS= read -r -d '' file; do
        if [[ "$file" != *.sha256 ]]; then
            snapshots+=("$file")
        fi
    done < <(find "$snapshot_dir" -name "*.tar*" -type f -print0 2>/dev/null | sort -zr)
    
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
    
    local snapshot_dir="${BACKUP_DIR}/system_snapshots"
    
    # 获取快照列表（排除 .sha256）
    local snapshots=()
    while IFS= read -r -d '' file; do
        if [[ "$file" != *.sha256 ]]; then
            snapshots+=("$file")
        fi
    done < <(find "$snapshot_dir" -name "*.tar*" -type f -print0 2>/dev/null | sort -zr)
    
    local file="${snapshots[$snapshot_id]}"
    local name=$(basename "$file")
    
    # 删除快照及其 .sha256 文件
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

# ===== 配置管理 =====
handle_menu_config() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "配置管理"
    
    local message="⚙️ <b>配置管理</b>

选择要管理的配置项:"

    local keyboard='{
  "inline_keyboard": [
    [{"text": "📡 Telegram配置", "callback_data": "config_telegram"}],
    [{"text": "🌐 远程备份配置", "callback_data": "config_remote"}],
    [{"text": "💾 本地备份配置", "callback_data": "config_local"}],
    [{"text": "⏰ 定时任务配置", "callback_data": "config_schedule"}],
    [{"text": "📄 查看完整配置", "callback_data": "config_view"}],
    [{"text": "🔙 返回", "callback_data": "menu_main"}]
  ]
}'
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
}

handle_config_view() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "查看配置"
    
    source "$CONFIG_FILE"
    
    local message="📄 <b>完整配置</b>

<b>🔔 Telegram</b>
启用: ${TELEGRAM_ENABLED:-false}

<b>🌐 远程备份</b>
启用: ${REMOTE_ENABLED:-false}
服务器: ${REMOTE_HOST:-未配置}
用户: ${REMOTE_USER:-root}
端口: ${REMOTE_PORT:-22}
路径: ${REMOTE_PATH:-未配置}
保留: ${REMOTE_KEEP_DAYS:-30}天

<b>💾 本地备份</b>
目录: ${BACKUP_DIR:-/backups}
压缩: 级别${COMPRESSION_LEVEL:-6}
线程: ${PARALLEL_THREADS:-auto}
保留: ${LOCAL_KEEP_COUNT:-5}个

<b>⏰ 定时任务</b>
自动备份: ${AUTO_BACKUP_ENABLED:-false}
间隔: ${BACKUP_INTERVAL_DAYS:-7}天
时间: ${BACKUP_TIME:-03:00}

<i>修改配置请使用配置管理按钮</i>"

    edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
}

# ===== Telegram 配置 =====
handle_config_telegram() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "Telegram配置"
    
    source "$CONFIG_FILE"
    
    local tg_status="🔴 未启用"
    local tg_action="enable"
    local tg_action_text="✅ 启用通知"
    
    local tg_enabled=$(echo "${TELEGRAM_ENABLED:-false}" | tr '[:upper:]' '[:lower:]')
    if [[ "$tg_enabled" == "y" || "$tg_enabled" == "yes" || "$tg_enabled" == "true" ]]; then
        tg_status="🟢 已启用"
        tg_action="disable"
        tg_action_text="❌ 禁用通知"
    fi
    
    local message="📡 <b>Telegram 配置</b>

<b>当前状态:</b> ${tg_status}

<b>Bot Token:</b>
<code>${TELEGRAM_BOT_TOKEN:0:20}...</code>

<b>Chat ID:</b>
<code>${TELEGRAM_CHAT_ID:-未设置}</code>

<b>💡 提示:</b>
• Token/Chat ID 需在服务器修改
• 使用主控制台: <code>sudo snapsync</code>
• 或编辑配置: <code>sudo nano /etc/snapsync/config.conf</code>

<i>Bot重启后生效</i>"

    local keyboard="{
  \"inline_keyboard\": [
    [{\"text\": \"${tg_action_text}\", \"callback_data\": \"toggle_telegram_${tg_action}\"}],
    [{\"text\": \"🔙 返回配置菜单\", \"callback_data\": \"menu_config\"}]
  ]
}"
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
}

handle_toggle_telegram() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local action="$4"
    
    answer_callback "$callback_id" "切换中..."
    
    local new_value="false"
    [[ "$action" == "enable" ]] && new_value="true"
    
    # 更新配置文件
    sed -i "s/^TELEGRAM_ENABLED=.*/TELEGRAM_ENABLED=\"$new_value\"/" "$CONFIG_FILE"
    
    # 重新加载配置
    source "$CONFIG_FILE"
    
    local status_text="🔴 已禁用"
    [[ "$new_value" == "true" ]] && status_text="🟢 已启用"
    
    local message="✅ <b>配置已更新</b>

Telegram 通知: ${status_text}

<i>返回配置菜单查看更新</i>"
    
    edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
}

# ===== 远程备份配置 =====
handle_config_remote() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "远程备份配置"
    
    source "$CONFIG_FILE"
    
    local remote_status="🔴 未启用"
    local remote_action="enable"
    local remote_action_text="✅ 启用远程备份"
    
    local remote_enabled=$(echo "${REMOTE_ENABLED:-false}" | tr '[:upper:]' '[:lower:]')
    if [[ "$remote_enabled" == "y" || "$remote_enabled" == "yes" || "$remote_enabled" == "true" ]]; then
        remote_status="🟢 已启用"
        remote_action="disable"
        remote_action_text="❌ 禁用远程备份"
    fi
    
    local message="🌐 <b>远程备份配置</b>

<b>当前状态:</b> ${remote_status}

<b>服务器:</b> ${REMOTE_HOST:-未配置}
<b>用户:</b> ${REMOTE_USER:-root}
<b>端口:</b> ${REMOTE_PORT:-22}
<b>路径:</b> ${REMOTE_PATH:-未配置}
<b>保留:</b> ${REMOTE_KEEP_DAYS:-30}天

<b>💡 提示:</b>
• 详细配置需在服务器修改
• 使用主控制台: <code>sudo snapsync</code>
• 或编辑配置: <code>sudo nano /etc/snapsync/config.conf</code>

<i>需要配置 SSH 密钥</i>"

    local keyboard="{
  \"inline_keyboard\": [
    [{\"text\": \"${remote_action_text}\", \"callback_data\": \"toggle_remote_${remote_action}\"}],
    [{\"text\": \"🔙 返回配置菜单\", \"callback_data\": \"menu_config\"}]
  ]
}"
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
}

handle_toggle_remote() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local action="$4"
    
    answer_callback "$callback_id" "切换中..."
    
    local new_value="false"
    [[ "$action" == "enable" ]] && new_value="true"
    
    sed -i "s/^REMOTE_ENABLED=.*/REMOTE_ENABLED=\"$new_value\"/" "$CONFIG_FILE"
    source "$CONFIG_FILE"
    
    local status_text="🔴 已禁用"
    [[ "$new_value" == "true" ]] && status_text="🟢 已启用"
    
    local message="✅ <b>配置已更新</b>

远程备份: ${status_text}

<i>返回配置菜单查看更新</i>"
    
    edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
}

# ===== 本地备份配置 =====
handle_config_local() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "本地备份配置"
    
    source "$CONFIG_FILE"
    
    local message="💾 <b>本地备份配置</b>

<b>备份目录:</b> ${BACKUP_DIR:-/backups}
<b>压缩级别:</b> ${COMPRESSION_LEVEL:-6} (1-9)
<b>并行线程:</b> ${PARALLEL_THREADS:-auto}
<b>保留数量:</b> ${LOCAL_KEEP_COUNT:-5}个

<b>🎛️ 快速调整:</b>
• 压缩级别: 1=快速 9=高压缩
• 保留数量: 本地保留的快照数

<b>💡 提示:</b>
• 详细配置需在服务器修改
• 使用主控制台: <code>sudo snapsync</code>
• 或编辑配置: <code>sudo nano /etc/snapsync/config.conf</code>"

    local keyboard="{
  \"inline_keyboard\": [
    [{\"text\": \"🗜️ 压缩:快速(3)\", \"callback_data\": \"set_compression_3\"}],
    [{\"text\": \"🗜️ 压缩:平衡(6)\", \"callback_data\": \"set_compression_6\"}],
    [{\"text\": \"🗜️ 压缩:高(9)\", \"callback_data\": \"set_compression_9\"}],
    [{\"text\": \"📦 保留:3个\", \"callback_data\": \"set_keep_3\"}, {\"text\": \"📦 保留:5个\", \"callback_data\": \"set_keep_5\"}, {\"text\": \"📦 保留:10个\", \"callback_data\": \"set_keep_10\"}],
    [{\"text\": \"🔙 返回配置菜单\", \"callback_data\": \"menu_config\"}]
  ]
}"
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
}

handle_set_compression() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local level="$4"
    
    answer_callback "$callback_id" "设置压缩级别..."
    
    sed -i "s/^COMPRESSION_LEVEL=.*/COMPRESSION_LEVEL=\"$level\"/" "$CONFIG_FILE"
    
    local message="✅ <b>配置已更新</b>

压缩级别: $level

<i>下次备份生效</i>"
    
    edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
}

handle_set_keep() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local count="$4"
    
    answer_callback "$callback_id" "设置保留数量..."
    
    sed -i "s/^LOCAL_KEEP_COUNT=.*/LOCAL_KEEP_COUNT=\"$count\"/" "$CONFIG_FILE"
    
    local message="✅ <b>配置已更新</b>

本地保留: $count 个快照

<i>下次清理时生效</i>"
    
    edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
}

# ===== 定时任务配置 =====
handle_config_schedule() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "定时任务配置"
    
    source "$CONFIG_FILE"
    
    local auto_status="🔴 未启用"
    local auto_action="enable"
    local auto_action_text="✅ 启用自动备份"
    
    local auto_enabled=$(echo "${AUTO_BACKUP_ENABLED:-false}" | tr '[:upper:]' '[:lower:]')
    if [[ "$auto_enabled" == "y" || "$auto_enabled" == "yes" || "$auto_enabled" == "true" ]]; then
        auto_status="🟢 已启用"
        auto_action="disable"
        auto_action_text="❌ 禁用自动备份"
    fi
    
    local next_run="未启用"
    if [[ "$auto_status" == "🟢 已启用" ]]; then
        next_run=$(systemctl list-timers snapsync-backup.timer 2>/dev/null | awk 'NR==2 {print $1" "$2}' || echo "N/A")
    fi
    
    local message="⏰ <b>定时任务配置</b>

<b>当前状态:</b> ${auto_status}

<b>📅 备份间隔:</b> ${BACKUP_INTERVAL_DAYS:-7}天
<b>🕐 备份时间:</b> ${BACKUP_TIME:-03:00}

<b>⏭️ 下次运行:</b> ${next_run}

<b>🎛️ 快速调整:</b>
使用下方按钮直接修改间隔和时间

<i>修改后会自动重启定时器</i>"

    local keyboard="{
  \"inline_keyboard\": [
    [{\"text\": \"${auto_action_text}\", \"callback_data\": \"toggle_auto_${auto_action}\"}],
    [{\"text\": \"📅 调整间隔\", \"callback_data\": \"adjust_interval\"}],
    [{\"text\": \"🕐 调整时间\", \"callback_data\": \"adjust_time\"}],
    [{\"text\": \"🔄 重启定时器\", \"callback_data\": \"restart_timer\"}],
    [{\"text\": \"🔙 返回配置菜单\", \"callback_data\": \"menu_config\"}]
  ]
}"
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
}

# ===== 调整备份间隔 =====
handle_adjust_interval() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "调整间隔"
    
    source "$CONFIG_FILE"
    
    local current_interval="${BACKUP_INTERVAL_DAYS:-7}"
    
    local message="📅 <b>调整备份间隔</b>

<b>当前设置:</b> ${current_interval}天

选择新的备份间隔:

<b>💡 建议:</b>
• 重要系统: 1-3天
• 一般系统: 7天
• 稳定系统: 14-30天"

    local keyboard='{
  "inline_keyboard": [
    [{"text": "1天", "callback_data": "set_interval_1"}, {"text": "3天", "callback_data": "set_interval_3"}, {"text": "7天", "callback_data": "set_interval_7"}],
    [{"text": "14天", "callback_data": "set_interval_14"}, {"text": "30天", "callback_data": "set_interval_30"}],
    [{"text": "🔙 返回", "callback_data": "config_schedule"}]
  ]
}'
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
}

handle_set_interval() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local days="$4"
    
    answer_callback "$callback_id" "设置间隔..."
    
    # 更新配置文件
    sed -i "s/^BACKUP_INTERVAL_DAYS=.*/BACKUP_INTERVAL_DAYS=\"$days\"/" "$CONFIG_FILE"
    
    # 重启定时器使配置生效
    systemctl daemon-reload 2>/dev/null
    systemctl restart snapsync-backup.timer 2>/dev/null
    
    local message="✅ <b>间隔已更新</b>

备份间隔: ${days}天

<b>⏭️ 下次运行:</b>
$(systemctl list-timers snapsync-backup.timer 2>/dev/null | awk 'NR==2 {print $1" "$2}' || echo "N/A")

<i>定时器已自动重启</i>"
    
    local keyboard='{
  "inline_keyboard": [
    [{"text": "🔙 返回定时任务配置", "callback_data": "config_schedule"}]
  ]
}'
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
}

# ===== 调整备份时间 =====
handle_adjust_time() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "调整时间"
    
    source "$CONFIG_FILE"
    
    local current_time="${BACKUP_TIME:-03:00}"
    
    local message="🕐 <b>调整备份时间</b>

<b>当前设置:</b> ${current_time}

选择新的备份时间:

<b>💡 建议:</b>
• 凌晨时段: 服务器负载低
• 避开业务高峰时段"

    local keyboard='{
  "inline_keyboard": [
    [{"text": "00:00", "callback_data": "set_time_00:00"}, {"text": "01:00", "callback_data": "set_time_01:00"}, {"text": "02:00", "callback_data": "set_time_02:00"}],
    [{"text": "03:00", "callback_data": "set_time_03:00"}, {"text": "04:00", "callback_data": "set_time_04:00"}, {"text": "05:00", "callback_data": "set_time_05:00"}],
    [{"text": "06:00", "callback_data": "set_time_06:00"}, {"text": "12:00", "callback_data": "set_time_12:00"}, {"text": "18:00", "callback_data": "set_time_18:00"}],
    [{"text": "🔙 返回", "callback_data": "config_schedule"}]
  ]
}'
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
}

handle_set_time() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local time="$4"
    
    answer_callback "$callback_id" "设置时间..."
    
    # 更新配置文件
    sed -i "s/^BACKUP_TIME=.*/BACKUP_TIME=\"$time\"/" "$CONFIG_FILE"
    
    # 更新 systemd timer 文件
    cat > /etc/systemd/system/snapsync-backup.timer << EOF
[Unit]
Description=SnapSync Backup Timer

[Timer]
OnCalendar=*-*-* ${time}:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # 重启定时器
    systemctl daemon-reload 2>/dev/null
    systemctl restart snapsync-backup.timer 2>/dev/null
    
    local message="✅ <b>时间已更新</b>

备份时间: ${time}

<b>⏭️ 下次运行:</b>
$(systemctl list-timers snapsync-backup.timer 2>/dev/null | awk 'NR==2 {print $1" "$2}' || echo "N/A")

<i>定时器已自动重启</i>"
    
    local keyboard='{
  "inline_keyboard": [
    [{"text": "🔙 返回定时任务配置", "callback_data": "config_schedule"}]
  ]
}'
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
}

handle_toggle_auto() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local action="$4"
    
    answer_callback "$callback_id" "切换中..."
    
    local new_value="false"
    [[ "$action" == "enable" ]] && new_value="true"
    
    sed -i "s/^AUTO_BACKUP_ENABLED=.*/AUTO_BACKUP_ENABLED=\"$new_value\"/" "$CONFIG_FILE"
    
    # 启用/禁用定时器
    if [[ "$new_value" == "true" ]]; then
        systemctl enable snapsync-backup.timer 2>/dev/null
        systemctl start snapsync-backup.timer 2>/dev/null
    else
        systemctl disable snapsync-backup.timer 2>/dev/null
        systemctl stop snapsync-backup.timer 2>/dev/null
    fi
    
    source "$CONFIG_FILE"
    
    local status_text="🔴 已禁用"
    [[ "$new_value" == "true" ]] && status_text="🟢 已启用"
    
    local message="✅ <b>配置已更新</b>

自动备份: ${status_text}

<i>定时器已${new_value}}</i>"
    
    edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
}

handle_restart_timer() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "重启中..."
    
    systemctl daemon-reload 2>/dev/null
    systemctl restart snapsync-backup.timer 2>/dev/null
    
    local message="✅ <b>定时器已重启</b>

<i>返回配置菜单查看状态</i>"
    
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
• 恢复: 还原系统状态
• 删除: 清理旧快照

<b>⚙️ 配置管理</b>
• 分类管理配置项
• 按钮式交互修改
• 实时生效

<b>💡 提示</b>
• 定期检查快照状态
• 保持足够磁盘空间
• 测试恢复流程
• 重要操作前先备份"

    edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
}

# ===== 消息路由 =====
handle_message() {
    local chat_id="$1"
    local text="$2"
    
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
        menu_restore) handle_menu_restore "$chat_id" "$message_id" "$callback_id" ;;
        menu_delete) handle_menu_delete "$chat_id" "$message_id" "$callback_id" ;;
        menu_config) handle_menu_config "$chat_id" "$message_id" "$callback_id" ;;
        menu_help) handle_menu_help "$chat_id" "$message_id" "$callback_id" ;;
        confirm_create) handle_confirm_create "$chat_id" "$message_id" "$callback_id" ;;
        config_view) handle_config_view "$chat_id" "$message_id" "$callback_id" ;;
        restore_*)
            local id="${data#restore_}"
            handle_restore_snapshot "$chat_id" "$message_id" "$callback_id" "$id"
            ;;
        confirm_restore_smart_*)
            local id="${data#confirm_restore_smart_}"
            handle_confirm_restore "$chat_id" "$message_id" "$callback_id" "smart" "$id"
            ;;
        confirm_restore_full_*)
            local id="${data#confirm_restore_full_}"
            handle_confirm_restore "$chat_id" "$message_id" "$callback_id" "full" "$id"
            ;;
        delete_*)
            local id="${data#delete_}"
            handle_delete_snapshot "$chat_id" "$message_id" "$callback_id" "$id"
            ;;
        confirm_delete_*)
            local id="${data#confirm_delete_}"
            handle_confirm_delete "$chat_id" "$message_id" "$callback_id" "$id"
            ;;
        config_telegram) handle_config_telegram "$chat_id" "$message_id" "$callback_id" ;;
        config_remote) handle_config_remote "$chat_id" "$message_id" "$callback_id" ;;
        config_local) handle_config_local "$chat_id" "$message_id" "$callback_id" ;;
        config_schedule) handle_config_schedule "$chat_id" "$message_id" "$callback_id" ;;
        config_view) handle_config_view "$chat_id" "$message_id" "$callback_id" ;;
        toggle_telegram_*)
            local action="${data#toggle_telegram_}"
            handle_toggle_telegram "$chat_id" "$message_id" "$callback_id" "$action"
            ;;
        toggle_remote_*)
            local action="${data#toggle_remote_}"
            handle_toggle_remote "$chat_id" "$message_id" "$callback_id" "$action"
            ;;
        toggle_auto_*)
            local action="${data#toggle_auto_}"
            handle_toggle_auto "$chat_id" "$message_id" "$callback_id" "$action"
            ;;
        adjust_interval) handle_adjust_interval "$chat_id" "$message_id" "$callback_id" ;;
        set_interval_*)
            local days="${data#set_interval_}"
            handle_set_interval "$chat_id" "$message_id" "$callback_id" "$days"
            ;;
        adjust_time) handle_adjust_time "$chat_id" "$message_id" "$callback_id" ;;
        set_time_*)
            local time="${data#set_time_}"
            handle_set_time "$chat_id" "$message_id" "$callback_id" "$time"
            ;;
        set_compression_*)
            local level="${data#set_compression_}"
            handle_set_compression "$chat_id" "$message_id" "$callback_id" "$level"
            ;;
        set_keep_*)
            local count="${data#set_keep_}"
            handle_set_keep "$chat_id" "$message_id" "$callback_id" "$count"
            ;;
        restart_timer) handle_restart_timer "$chat_id" "$message_id" "$callback_id" ;;
        *) answer_callback "$callback_id" "未知操作" ;;
    esac
}

# ===== 主循环 =====
get_updates() {
    curl -sS -m 65 -X POST "${API_URL}/getUpdates" \
        -d "offset=${LAST_UPDATE_ID}" \
        -d "timeout=60" \
        -d "allowed_updates=[\"message\",\"callback_query\"]" 2>&1
}

process_updates() {
    local updates="$1"
    
    if ! echo "$updates" | jq -e . >/dev/null 2>&1; then
        log_bot "无效的JSON响应"
        return
    fi
    
    local ok=$(echo "$updates" | jq -r '.ok // false')
    [[ "$ok" != "true" ]] && return
    
    local result=$(echo "$updates" | jq -c '.result[]' 2>/dev/null)
    [[ -z "$result" ]] && return
    
    while IFS= read -r update; do
        local update_id=$(echo "$update" | jq -r '.update_id // 0')
        [[ "$update_id" == "0" ]] && continue
        
        LAST_UPDATE_ID=$((update_id + 1))
        
        local message=$(echo "$update" | jq -r '.message // null')
        if [[ "$message" != "null" ]]; then
            local chat_id=$(echo "$message" | jq -r '.chat.id // ""')
            local text=$(echo "$message" | jq -r '.text // ""')
            [[ -n "$chat_id" && -n "$text" ]] && handle_message "$chat_id" "$text"
        fi
        
        local callback=$(echo "$update" | jq -r '.callback_query // null')
        if [[ "$callback" != "null" ]]; then
            local chat_id=$(echo "$callback" | jq -r '.message.chat.id // ""')
            local message_id=$(echo "$callback" | jq -r '.message.message_id // ""')
            local data=$(echo "$callback" | jq -r '.data // ""')
            local callback_id=$(echo "$callback" | jq -r '.id // ""')
            [[ -n "$chat_id" && -n "$message_id" && -n "$data" && -n "$callback_id" ]] && \
                handle_callback "$chat_id" "$message_id" "$data" "$callback_id"
        fi
    done <<< "$result"
}

save_state() {
    echo "LAST_UPDATE_ID=${LAST_UPDATE_ID}" > "$STATE_FILE" 2>/dev/null || true
}

load_state() {
    [[ -f "$STATE_FILE" ]] && source "$STATE_FILE" 2>/dev/null || true
}

cleanup() {
    log_bot "收到停止信号，保存状态..."
    save_state
    log_bot "Bot停止"
    exit 0
}

trap cleanup SIGTERM SIGINT

# ===== 主程序 =====
main() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    
    log_bot "========================================"
    log_bot "SnapSync Bot v3.0 启动"
    log_bot "主机: ${HOSTNAME}"
    log_bot "========================================"
    
    load_state
    
    send_message_with_buttons "$TELEGRAM_CHAT_ID" "🤖 <b>Bot已启动</b>

⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')

点击下方按钮开始操作" "$(get_main_menu_keyboard)" || {
        log_bot "启动通知发送失败，但继续运行"
    }
    
    log_bot "进入主循环..."
    
    local error_count=0
    local max_errors=10
    
    while true; do
        if updates=$(get_updates); then
            process_updates "$updates"
            error_count=0
        else
            ((error_count++))
            log_bot "获取更新失败（${error_count}/${max_errors}）"
            
            if (( error_count >= max_errors )); then
                log_bot "连续失败次数过多，等待30秒后继续..."
                sleep 30
                error_count=0
            else
                sleep 5
            fi
        fi
        
        save_state
    done
}

if ! command -v jq &>/dev/null; then
    echo "错误: 需要安装 jq" >&2
    exit 1
fi

main "$@"
