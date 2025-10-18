#!/bin/bash

# SnapSync v3.0 - Telegram Bot（完整功能版）
# 新增：恢复快照时支持选择本地/远程来源
# 修复：SSH 连接强制使用密钥认证

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
• ♻️ 恢复系统快照（本地/远程）
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
    local snapshot_count=0
    if [[ -d "$snapshot_dir" ]]; then
        snapshot_count=$(find "$snapshot_dir" -name "*.tar*" -type f 2>/dev/null | grep -v '\.sha256$' | wc -l)
    fi
    
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

# ===== 恢复快照（新增：选择来源）=====
handle_menu_restore() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "恢复快照"
    
    # 检查远程备份是否启用
    local remote_enabled=$(echo "${REMOTE_ENABLED:-false}" | tr '[:upper:]' '[:lower:]')
    
    local message="♻️ <b>恢复快照</b>

选择快照来源:"
    
    local keyboard
    if [[ "$remote_enabled" == "y" || "$remote_enabled" == "yes" || "$remote_enabled" == "true" ]]; then
        # 远程备份已启用，显示两个选项
        keyboard='{
  "inline_keyboard": [
    [{"text": "📁 本地快照", "callback_data": "restore_source_local"}],
    [{"text": "🌐 远程快照", "callback_data": "restore_source_remote"}],
    [{"text": "🔙 返回", "callback_data": "menu_main"}]
  ]
}'
    else
        # 远程备份未启用，只有本地选项
        keyboard='{
  "inline_keyboard": [
    [{"text": "📁 本地快照", "callback_data": "restore_source_local"}],
    [{"text": "🔙 返回", "callback_data": "menu_main"}]
  ]
}'
        message+="

<i>💡 提示: 远程备份未启用</i>"
    fi
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
}

# ===== 恢复 - 本地快照列表 =====
handle_restore_source_local() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "本地快照"
    
    local snapshot_dir="${BACKUP_DIR}/system_snapshots"
    
    local snapshots=()
    while IFS= read -r -d '' file; do
        if [[ "$file" != *.sha256 ]]; then
            snapshots+=("$file")
        fi
    done < <(find "$snapshot_dir" -name "*.tar*" -type f -print0 2>/dev/null | sort -zr)
    
    if [[ ${#snapshots[@]} -eq 0 ]]; then
        local message="♻️ <b>本地快照</b>

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
        
        buttons+="{\"text\": \"$((i+1)). ${short_name}\", \"callback_data\": \"restore_local_${i}\"},"
        ((count++))
    done
    buttons="${buttons%,}]"
    
    local keyboard="{\"inline_keyboard\":[$buttons,[{\"text\":\"🔙 返回\",\"callback_data\":\"menu_restore\"}]]}"
    
    local message="♻️ <b>选择本地快照</b>

📁 本地备份目录
找到 ${#snapshots[@]} 个快照

<b>⚠️ 警告:</b>
恢复操作不可撤销，请谨慎选择！

<i>建议选择最新的快照</i>"
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
}

# ===== 恢复 - 远程快照列表 =====
handle_restore_source_remote() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "远程快照"
    
    # 显示加载消息
    local loading_message="♻️ <b>连接远程服务器</b>

🌐 服务器: ${REMOTE_HOST}
⏳ 正在获取快照列表...

<i>请稍候...</i>"
    
    edit_message "$chat_id" "$message_id" "$loading_message" ""
    
    # 在后台获取远程快照列表
    (
        local ssh_key="/root/.ssh/id_ed25519"
        
        local ssh_opts=(
            "-o" "StrictHostKeyChecking=no"
            "-o" "UserKnownHostsFile=/dev/null"
            "-o" "PasswordAuthentication=no"
            "-o" "PreferredAuthentications=publickey"
            "-o" "PubkeyAuthentication=yes"
            "-o" "BatchMode=yes"
            "-o" "ConnectTimeout=30"
            "-o" "LogLevel=ERROR"
        )
        
        # 测试连接
        if ! ssh -i "$ssh_key" -p "$REMOTE_PORT" "${ssh_opts[@]}" \
                "${REMOTE_USER}@${REMOTE_HOST}" "echo ok" &>/dev/null; then
            
            local error_message="❌ <b>连接失败</b>

🌐 服务器: ${REMOTE_HOST}
⚠️ 无法连接远程服务器

<b>可能的原因:</b>
• SSH 密钥未配置
• 远程服务器不可达
• 防火墙阻止

<i>请使用主控制台配置远程服务器</i>"
            
            send_message_with_buttons "$chat_id" "$error_message" "$(get_back_button)"
            return 1
        fi
        
        # 获取远程快照列表
        local remote_list=$(ssh -i "$ssh_key" -p "$REMOTE_PORT" "${ssh_opts[@]}" \
            "${REMOTE_USER}@${REMOTE_HOST}" \
            "find '${REMOTE_PATH}/system_snapshots' -name 'system_snapshot_*.tar*' -type f 2>/dev/null | grep -v '\.sha256$' | sort -r" 2>/dev/null)
        
        if [[ -z "$remote_list" ]]; then
            local no_snapshot_message="♻️ <b>远程快照</b>

🌐 服务器: ${REMOTE_HOST}
📁 未找到远程快照

<i>请先创建并上传快照</i>"
            
            send_message_with_buttons "$chat_id" "$no_snapshot_message" "$(get_back_button)"
            return 1
        fi
        
        # 转换为数组
        local snapshots=()
        while IFS= read -r file; do
            [[ -n "$file" ]] && snapshots+=("$file")
        done <<< "$remote_list"
        
        # 构建快照选择按钮（最多5个）
        local buttons="["
        local count=0
        for i in "${!snapshots[@]}"; do
            (( count >= 5 )) && break
            
            local file="${snapshots[$i]}"
            local name=$(basename "$file")
            local short_name="${name:17:14}"
            
            buttons+="{\"text\": \"$((i+1)). ${short_name}\", \"callback_data\": \"restore_remote_${i}\"},"
            ((count++))
        done
        buttons="${buttons%,}]"
        
        local keyboard="{\"inline_keyboard\":[$buttons,[{\"text\":\"🔙 返回\",\"callback_data\":\"menu_restore\"}]]}"
        
        local success_message="♻️ <b>选择远程快照</b>

🌐 服务器: ${REMOTE_HOST}
找到 ${#snapshots[@]} 个快照

<b>⚠️ 注意:</b>
• 选择后会先下载快照
• 下载需要一定时间
• 建议选择最新的快照"
        
        # 保存快照列表到临时文件，供后续使用
        printf "%s\n" "${snapshots[@]}" > "/tmp/remote_snapshots_${chat_id}.txt"
        
        # 更新消息
        curl -sS -m 10 -X POST "${API_URL}/editMessageText" \
            -d "chat_id=${chat_id}" \
            -d "message_id=${message_id}" \
            --data-urlencode "text=🖥️ <b>${HOSTNAME}</b>
━━━━━━━━━━━━━━━━━━━━━━━
${success_message}" \
            -d "parse_mode=HTML" \
            -d "reply_markup=${keyboard}" &>/dev/null
        
    ) &
}

# ===== 恢复 - 本地快照确认 =====
handle_restore_local() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local snapshot_id="$4"
    
    answer_callback "$callback_id" "准备恢复..."
    
    local snapshot_dir="${BACKUP_DIR}/system_snapshots"
    
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

📁 来源: 本地快照
📸 快照: <code>${name}</code>
📊 大小: ${size}

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
    [{\"text\": \"🛡️ 智能恢复\", \"callback_data\": \"confirm_restore_local_smart_${snapshot_id}\"}],
    [{\"text\": \"🔧 完全恢复\", \"callback_data\": \"confirm_restore_local_full_${snapshot_id}\"}],
    [{\"text\": \"❌ 取消\", \"callback_data\": \"restore_source_local\"}]
  ]
}"
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
}

# ===== 恢复 - 远程快照确认 =====
handle_restore_remote() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local snapshot_id="$4"
    
    answer_callback "$callback_id" "准备恢复..."
    
    # 从临时文件读取快照列表
    local temp_file="/tmp/remote_snapshots_${chat_id}.txt"
    
    if [[ ! -f "$temp_file" ]]; then
        answer_callback "$callback_id" "会话已过期，请重新选择"
        handle_restore_source_remote "$chat_id" "$message_id" "$callback_id"
        return
    fi
    
    local snapshots=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && snapshots+=("$line")
    done < "$temp_file"
    
    if [[ ! "$snapshot_id" =~ ^[0-9]+$ ]] || (( snapshot_id >= ${#snapshots[@]} )); then
        answer_callback "$callback_id" "无效的快照"
        return
    fi
    
    local file="${snapshots[$snapshot_id]}"
    local name=$(basename "$file")
    
    local message="♻️ <b>确认恢复</b>

🌐 来源: 远程服务器
📸 快照: <code>${name}</code>
🌐 服务器: ${REMOTE_HOST}

<b>⚠️ 注意事项:</b>
• 需要先下载快照到本地
• 下载需要几分钟时间
• 恢复操作不可撤销
• 建议选择「智能恢复」

<b>恢复模式:</b>
• 智能恢复: 保留网络/SSH配置
• 完全恢复: 恢复所有内容（谨慎）

选择恢复模式:"

    # 保存选中的远程文件路径
    echo "$file" > "/tmp/remote_snapshot_selected_${chat_id}.txt"
    
    local keyboard="{
  \"inline_keyboard\": [
    [{\"text\": \"🛡️ 智能恢复\", \"callback_data\": \"confirm_restore_remote_smart_${snapshot_id}\"}],
    [{\"text\": \"🔧 完全恢复\", \"callback_data\": \"confirm_restore_remote_full_${snapshot_id}\"}],
    [{\"text\": \"❌ 取消\", \"callback_data\": \"restore_source_remote\"}]
  ]
}"
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
}

# ===== 确认恢复（本地/远程统一处理）=====
handle_confirm_restore() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local source="$4"      # local 或 remote
    local restore_mode="$5" # smart 或 full
    local snapshot_id="$6"
    
    answer_callback "$callback_id" "准备恢复..."
    
    local mode_text="智能恢复"
    [[ "$restore_mode" == "full" ]] && mode_text="完全恢复"
    
    if [[ "$source" == "local" ]]; then
        # 本地恢复
        local snapshot_dir="${BACKUP_DIR}/system_snapshots"
        local snapshots=()
        while IFS= read -r -d '' file; do
            if [[ "$file" != *.sha256 ]]; then
                snapshots+=("$file")
            fi
        done < <(find "$snapshot_dir" -name "*.tar*" -type f -print0 2>/dev/null | sort -zr)
        
        local file="${snapshots[$snapshot_id]}"
        local name=$(basename "$file")
        
        local message="♻️ <b>恢复准备就绪</b>

📁 来源: 本地快照
📸 快照: ${name}
🔧 模式: ${mode_text}

<b>⚠️ 重要提示:</b>
为了安全，恢复操作需在服务器上手动执行

<b>执行步骤:</b>
1. SSH 登录服务器
2. 运行: <code>sudo snapsync</code>
3. 选择: 2) 恢复系统快照
4. 选择: 1) 本地恢复
5. 选择快照: ${name}
6. 选择模式: ${mode_text}"
        
        send_message_with_buttons "$chat_id" "$message" "$(get_back_button)"
        
    else
        # 远程恢复
        local temp_file="/tmp/remote_snapshot_selected_${chat_id}.txt"
        
        if [[ ! -f "$temp_file" ]]; then
            answer_callback "$callback_id" "会话已过期"
            return
        fi
        
        local remote_file=$(cat "$temp_file")
        local name=$(basename "$remote_file")
        
        local message="♻️ <b>恢复准备就绪</b>

🌐 来源: 远程服务器
📸 快照: ${name}
🔧 模式: ${mode_text}

<b>⚠️ 重要提示:</b>
为了安全，恢复操作需在服务器上手动执行

<b>执行步骤:</b>
1. SSH 登录服务器
2. 运行: <code>sudo snapsync</code>
3. 选择: 2) 恢复系统快照
4. 选择: 2) 远程恢复
5. 选择快照: ${name}
6. 选择模式: ${mode_text}

<i>系统会自动下载并恢复快照</i>"
        
        send_message_with_buttons "$chat_id" "$message" "$(get_back_button)"
        
        # 清理临时文件
        rm -f "$temp_file" "/tmp/remote_snapshots_${chat_id}.txt"
    fi
}

# ===== 删除快照 =====
handle_menu_delete() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "删除快照"
    
    local snapshot_dir="${BACKUP_DIR}/system_snapshots"
    
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
    
    local snapshots=()
    while IFS= read -r -d '' file; do
        if [[ "$file" != *.sha256 ]]; then
            snapshots+=("$file")
        fi
    done < <(find "$snapshot_dir" -name "*.tar*" -type f -print0 2>/dev/null | sort -zr)
    
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

# ===== 帮助 =====
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
• 恢复: 还原系统状态（本地/远程）
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

# ===== 回调路由 =====
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
        
        # 恢复 - 选择来源
        restore_source_local) handle_restore_source_local "$chat_id" "$message_id" "$callback_id" ;;
        restore_source_remote) handle_restore_source_remote "$chat_id" "$message_id" "$callback_id" ;;
        
        # 恢复 - 本地快照
        restore_local_*)
            local id="${data#restore_local_}"
            handle_restore_local "$chat_id" "$message_id" "$callback_id" "$id"
            ;;
        
        # 恢复 - 远程快照
        restore_remote_*)
            local id="${data#restore_remote_}"
            handle_restore_remote "$chat_id" "$message_id" "$callback_id" "$id"
            ;;
        
        # 确认恢复 - 本地智能
        confirm_restore_local_smart_*)
            local id="${data#confirm_restore_local_smart_}"
            handle_confirm_restore "$chat_id" "$message_id" "$callback_id" "local" "smart" "$id"
            ;;
        
        # 确认恢复 - 本地完全
        confirm_restore_local_full_*)
            local id="${data#confirm_restore_local_full_}"
            handle_confirm_restore "$chat_id" "$message_id" "$callback_id" "local" "full" "$id"
            ;;
        
        # 确认恢复 - 远程智能
        confirm_restore_remote_smart_*)
            local id="${data#confirm_restore_remote_smart_}"
            handle_confirm_restore "$chat_id" "$message_id" "$callback_id" "remote" "smart" "$id"
            ;;
        
        # 确认恢复 - 远程完全
        confirm_restore_remote_full_*)
            local id="${data#confirm_restore_remote_full_}"
            handle_confirm_restore "$chat_id" "$message_id" "$callback_id" "remote" "full" "$id"
            ;;
        
        # 删除快照
        delete_*)
            local id="${data#delete_}"
            handle_delete_snapshot "$chat_id" "$message_id" "$callback_id" "$id"
            ;;
        
        confirm_delete_*)
            local id="${data#confirm_delete_}"
            handle_confirm_delete "$chat_id" "$message_id" "$callback_id" "$id"
            ;;
        
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
    # 清理临时文件
    rm -f /tmp/remote_snapshots_*.txt /tmp/remote_snapshot_selected_*.txt
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
