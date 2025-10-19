#!/bin/bash

# SnapSync v3.0 - Telegram Bot（完整修复版 Part 1）
# 重点修复：远程恢复快照的数组读取和索引逻辑

set -euo pipefail

# ===== 配置加载 =====
CONFIG_FILE="/etc/snapsync/config.conf"
LOG_FILE="/var/log/snapsync/bot.log"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "配置文件不存在: $CONFIG_FILE" >> "$LOG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

# ===== 全局变量 =====
API_URL="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"
LAST_UPDATE_ID=0
HOSTNAME="${HOSTNAME:-$(hostname)}"

mkdir -p "$(dirname "$LOG_FILE")"

# ===== 日志函数 =====
log_bot() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# ===== API 函数 =====
send_message() {
    local chat_id="$1"
    local text="$2"
    local vps_tag="🖥️ <b>${HOSTNAME}</b>"
    local full_text="${vps_tag}
━━━━━━━━━━━━━━━━━━━━━━━
${text}"
    
    curl -sS -m 10 -X POST "${API_URL}/sendMessage" \
        -d "chat_id=${chat_id}" \
        --data-urlencode "text=${full_text}" \
        -d "parse_mode=HTML" &>/dev/null
}

send_message_with_buttons() {
    local chat_id="$1"
    local text="$2"
    local keyboard="$3"
    local vps_tag="🖥️ <b>${HOSTNAME}</b>"
    local full_text="${vps_tag}
━━━━━━━━━━━━━━━━━━━━━━━
${text}"
    
    curl -sS -m 10 -X POST "${API_URL}/sendMessage" \
        -d "chat_id=${chat_id}" \
        --data-urlencode "text=${full_text}" \
        -d "parse_mode=HTML" \
        -d "reply_markup=${keyboard}" &>/dev/null
}

edit_message() {
    local chat_id="$1"
    local message_id="$2"
    local text="$3"
    local keyboard="${4:-}"
    local vps_tag="🖥️ <b>${HOSTNAME}</b>"
    local full_text="${vps_tag}
━━━━━━━━━━━━━━━━━━━━━━━
${text}"
    
    if [[ -n "$keyboard" ]]; then
        curl -sS -m 10 -X POST "${API_URL}/editMessageText" \
            -d "chat_id=${chat_id}" \
            -d "message_id=${message_id}" \
            --data-urlencode "text=${full_text}" \
            -d "parse_mode=HTML" \
            -d "reply_markup=${keyboard}" &>/dev/null
    else
        curl -sS -m 10 -X POST "${API_URL}/editMessageText" \
            -d "chat_id=${chat_id}" \
            -d "message_id=${message_id}" \
            --data-urlencode "text=${full_text}" \
            -d "parse_mode=HTML" &>/dev/null
    fi
}

answer_callback() {
    local callback_id="$1"
    local text="${2:-已处理}"
    
    curl -sS -m 10 -X POST "${API_URL}/answerCallbackQuery" \
        -d "callback_query_id=${callback_id}" \
        --data-urlencode "text=${text}" &>/dev/null
}

# ===== 按钮布局 =====
get_main_menu() {
    cat << 'EOF'
{
  "inline_keyboard": [
    [{"text": "📊 系统状态", "callback_data": "menu_status"}],
    [{"text": "📋 快照列表", "callback_data": "menu_snapshots"}],
    [{"text": "🔄 创建快照", "callback_data": "menu_backup"}],
    [{"text": "♻️ 恢复快照", "callback_data": "menu_restore"}],
    [{"text": "🗑️ 删除快照", "callback_data": "menu_delete"}],
    [{"text": "⚙️ 配置信息", "callback_data": "menu_config"}],
    [{"text": "❓ 帮助", "callback_data": "menu_help"}]
  ]
}
EOF
}

get_back_button() {
    echo '{"inline_keyboard":[[{"text":"🔙 返回主菜单","callback_data":"menu_main"}]]}'
}

# ===== 主菜单处理 =====
handle_start() {
    local chat_id="$1"
    
    local welcome="👋 <b>欢迎使用 SnapSync Bot</b>

🖥️ 主机: ${HOSTNAME}
📦 版本: v3.0

使用下方按钮操作快照备份和恢复"
    
    send_message_with_buttons "$chat_id" "$welcome" "$(get_main_menu)"
}

handle_menu_main() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "主菜单"
    
    local message="📱 <b>主菜单</b>

🖥️ 主机: ${HOSTNAME}

选择操作:"
    
    edit_message "$chat_id" "$message_id" "$message" "$(get_main_menu)"
}

# ===== 系统状态 =====
handle_menu_status() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "系统状态"
    
    local uptime=$(uptime -p 2>/dev/null || echo "未知")
    local load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    local snapshot_count=$(find "${BACKUP_DIR}/system_snapshots" -maxdepth 1 -name "*.tar*" -type f 2>/dev/null | grep -cv '\.sha256$' || echo "0")
    local disk_usage=$(df -h "${BACKUP_DIR}" 2>/dev/null | awk 'NR==2 {print $5}')
    
    local message="📊 <b>系统状态</b>

🖥️ 主机: ${HOSTNAME}
⏱️ 运行时间: ${uptime}
📈 系统负载: ${load}
💾 磁盘使用: ${disk_usage}
📦 快照数量: ${snapshot_count}个"
    
    edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
}

# ===== 快照列表 =====
handle_menu_snapshots() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "快照列表"
    
    local snapshots=()
    while IFS= read -r -d '' file; do
        if [[ "$file" != *.sha256 ]]; then
            snapshots+=("$file")
        fi
    done < <(find "${BACKUP_DIR}/system_snapshots" -maxdepth 1 -name "system_snapshot_*.tar*" -type f -print0 2>/dev/null | sort -zr)
    
    if [[ ${#snapshots[@]} -eq 0 ]]; then
        local message="📋 <b>快照列表</b>

暂无快照

<i>创建第一个快照吧！</i>"
        edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
        return
    fi
    
    local list=""
    local idx=1
    for file in "${snapshots[@]}"; do
        local name=$(basename "$file")
        local size=$(stat -c%s "$file" 2>/dev/null || echo 0)
        local size_human=""
        
        if (( size >= 1073741824 )); then
            size_human="$(awk "BEGIN {printf \"%.2f\", $size/1073741824}")GB"
        elif (( size >= 1048576 )); then
            size_human="$(awk "BEGIN {printf \"%.2f\", $size/1048576}")MB"
        else
            size_human="$(awk "BEGIN {printf \"%.2f\", $size/1024}")KB"
        fi
        
        local date=$(date -r "$file" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "未知")
        
        list+="
${idx}. <code>${name}</code>
   大小: ${size_human} | 时间: ${date}
"
        ((idx++))
        
        [[ $idx -gt 5 ]] && break
    done
    
    local message="📋 <b>快照列表</b>

共 ${#snapshots[@]} 个快照
${list}

<i>显示最近5个</i>"
    
    edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
}

# ===== 创建快照 =====
handle_menu_backup() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "创建快照"
    
    local message="🔄 <b>创建快照</b>

即将创建系统快照

<b>⚠️ 注意:</b>
• 备份需要几分钟
• 期间勿关闭服务器
• 会自动保留最新 ${LOCAL_KEEP_COUNT:-5} 个快照

是否继续?"
    
    local keyboard='{
  "inline_keyboard": [
    [{"text": "✅ 确认创建", "callback_data": "confirm_backup"}],
    [{"text": "❌ 取消", "callback_data": "menu_main"}]
  ]
}'
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
}

handle_confirm_backup() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "开始备份..."
    
    local message="🔄 <b>备份进行中...</b>

⏳ 正在创建快照
📦 这需要几分钟

<i>请稍候，完成后会通知您</i>"
    
    edit_message "$chat_id" "$message_id" "$message" ""
    
    # 后台执行备份
    (bash /opt/snapsync/modules/backup.sh &>/dev/null || log_bot "备份失败") &
}

# ===== 恢复快照 =====
handle_menu_restore() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "恢复快照"
    
    local message="♻️ <b>恢复快照</b>

选择恢复来源:

<b>本地恢复:</b>
从本地备份目录恢复

<b>远程恢复:</b>
从远程服务器下载并恢复"
    
    local keyboard='{
  "inline_keyboard": [
    [{"text": "📁 本地恢复", "callback_data": "restore_source_local"}],
    [{"text": "🌐 远程恢复", "callback_data": "restore_source_remote"}],
    [{"text": "🔙 返回", "callback_data": "menu_main"}]
  ]
}'
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
}

# ===== 本地恢复快照列表 =====
handle_restore_source_local() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "本地快照"
    
    local snapshots=()
    while IFS= read -r -d '' file; do
        if [[ "$file" != *.sha256 ]]; then
            snapshots+=("$file")
        fi
    done < <(find "${BACKUP_DIR}/system_snapshots" -maxdepth 1 -name "system_snapshot_*.tar*" -type f -print0 2>/dev/null | sort -zr)
    
    if [[ ${#snapshots[@]} -eq 0 ]]; then
        local message="♻️ <b>本地快照</b>

未找到本地快照

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

找到 ${#snapshots[@]} 个快照

<b>⚠️ 注意:</b>
• 选择智能恢复（推荐）
• 恢复操作不可撤销"
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
    
    # 保存快照列表到临时文件
    local temp_file="/tmp/local_snapshots_${chat_id}.txt"
    rm -f "$temp_file"
    for snap in "${snapshots[@]}"; do
        echo "$snap" >> "$temp_file"
    done
    
    log_bot "本地快照列表已保存: $temp_file (${#snapshots[@]} 个)"
}

# ===== 远程恢复快照列表（修复版）=====
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
        
        log_bot "SSH 连接成功，获取快照列表..."
        
        # 获取远程快照列表
        local remote_list=$(ssh -i "$ssh_key" -p "$REMOTE_PORT" "${ssh_opts[@]}" \
            "${REMOTE_USER}@${REMOTE_HOST}" \
            "find '${REMOTE_PATH}/system_snapshots' -name 'system_snapshot_*.tar*' -type f 2>/dev/null | grep -v '\.sha256$' | sort -r" 2>/dev/null)
        
        if [[ -z "$remote_list" ]]; then
            log_bot "未找到远程快照"
            
            local no_snapshot_message="♻️ <b>远程快照</b>

🌐 服务器: ${REMOTE_HOST}
📁 未找到远程快照

<i>请先创建并上传快照</i>"
            
            send_message_with_buttons "$chat_id" "$no_snapshot_message" "$(get_back_button)"
            return 1
        fi
        
        # 修复：转换为数组（逐行读取）
        local snapshots=()
        local idx=0
        while IFS= read -r file; do
            if [[ -n "$file" ]]; then
                snapshots[$idx]="$file"
                ((idx++))
            fi
        done <<< "$remote_list"
        
        log_bot "找到 ${#snapshots[@]} 个远程快照"
        
        # 保存快照列表到临时文件（修复：每行一个路径）
        local temp_file="/tmp/remote_snapshots_${chat_id}.txt"
        rm -f "$temp_file"
        for snap in "${snapshots[@]}"; do
            echo "$snap" >> "$temp_file"
        done
        
        log_bot "快照列表已保存到: $temp_file"
        
        # 构建快照选择按钮（最多5个）
        local buttons="["
        local count=0
        for i in "${!snapshots[@]}"; do
            (( count >= 5 )) && break
            
            local file="${snapshots[$i]}"
            local name=$(basename "$file")
            local short_name="${name:17:14}"
            
            # 修复：使用数组索引 i 作为 callback_data
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
        
        # 更新消息
        curl -sS -m 10 -X POST "${API_URL}/editMessageText" \
            -d "chat_id=${chat_id}" \
            -d "message_id=${message_id}" \
            --data-urlencode "text=🖥️ <b>${HOSTNAME}</b>
━━━━━━━━━━━━━━━━━━━━━━━
${success_message}" \
            -d "parse_mode=HTML" \
            -d "reply_markup=${keyboard}" &>/dev/null
        
        log_bot "远程快照列表已发送"
        
    ) &
}

# ===== 本地恢复确认 =====
handle_restore_local() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local snapshot_id="$4"
    
    answer_callback "$callback_id" "准备恢复..."
    
    # 从临时文件读取快照列表
    local temp_file="/tmp/local_snapshots_${chat_id}.txt"
    
    if [[ ! -f "$temp_file" ]]; then
        log_bot "临时文件不存在"
        answer_callback "$callback_id" "会话已过期，请重新选择"
        handle_restore_source_local "$chat_id" "$message_id" "$callback_id"
        return
    fi
    
    local snapshots=()
    local line_num=0
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            snapshots[$line_num]="$line"
            ((line_num++))
        fi
    done < "$temp_file"
    
    if [[ ! "$snapshot_id" =~ ^[0-9]+$ ]] || (( snapshot_id < 0 || snapshot_id >= ${#snapshots[@]} )); then
        log_bot "无效的快照ID: $snapshot_id"
        answer_callback "$callback_id" "无效的快照ID"
        return
    fi
    
    local file="${snapshots[$snapshot_id]}"
    local name=$(basename "$file")
    
    local message="♻️ <b>确认恢复</b>

📁 来源: 本地备份
📸 快照: <code>${name}</code>

<b>⚠️ 注意事项:</b>
• 恢复操作不可撤销
• 建议选择「智能恢复」
• 智能恢复会保留网络配置

<b>恢复模式:</b>
• 智能恢复: 保留网络/SSH配置
• 完全恢复: 恢复所有内容（谨慎）

选择恢复模式:"
    
    # 保存选中的文件路径
    echo "$file" > "/tmp/local_snapshot_selected_${chat_id}.txt"
    
    local keyboard="{
  \"inline_keyboard\": [
    [{\"text\": \"🛡️ 智能恢复\", \"callback_data\": \"confirm_restore_local_smart_${snapshot_id}\"}],
    [{\"text\": \"🔧 完全恢复\", \"callback_data\": \"confirm_restore_local_full_${snapshot_id}\"}],
    [{\"text\": \"❌ 取消\", \"callback_data\": \"restore_source_local\"}]
  ]
}"
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
}

# ===== 远程恢复确认（修复版）=====
handle_restore_remote() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local snapshot_id="$4"
    
    answer_callback "$callback_id" "准备恢复..."
    
    # 从临时文件读取快照列表
    local temp_file="/tmp/remote_snapshots_${chat_id}.txt"
    
    if [[ ! -f "$temp_file" ]]; then
        log_bot "临时文件不存在，重新获取列表"
        answer_callback "$callback_id" "会话已过期，请重新选择"
        handle_restore_source_remote "$chat_id" "$message_id" "$callback_id"
        return
    fi
    
    # 修复：正确读取数组
    local snapshots=()
    local line_num=0
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            snapshots[$line_num]="$line"
            ((line_num++))
        fi
    done < "$temp_file"
    
    log_bot "读取到 ${#snapshots[@]} 个快照，选择第 $snapshot_id 个"
    
    # 修复：检查索引是否有效
    if [[ ! "$snapshot_id" =~ ^[0-9]+$ ]]; then
        log_bot "无效的快照ID: $snapshot_id（非数字）"
        answer_callback "$callback_id" "无效的快照ID"
        return
    fi
    
    if (( snapshot_id < 0 || snapshot_id >= ${#snapshots[@]} )); then
        log_bot "快照ID超出范围: $snapshot_id（范围: 0-$((${#snapshots[@]}-1))）"
        answer_callback "$callback_id" "快照ID超出范围"
        
        # 显示调试信息
        local debug_msg="❌ <b>选择失败</b>

快照ID: ${snapshot_id}
可用范围: 0-$((${#snapshots[@]}-1))
总数: ${#snapshots[@]}

<i>请重新选择</i>"
        
        send_message_with_buttons "$chat_id" "$debug_msg" "$(get_back_button)"
        return
    fi
    
    # 修复：使用正确的索引获取文件
    local file="${snapshots[$snapshot_id]}"
    
    if [[ -z "$file" ]]; then
        log_bot "快照文件路径为空"
        answer_callback "$callback_id" "快照路径无效"
        return
    fi
    
    log_bot "选择的快照: $file"
    
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
    log_bot "已保存选择到临时文件"
    
    local keyboard="{
  \"inline_keyboard\": [
    [{\"text\": \"🛡️ 智能恢复\", \"callback_data\": \"confirm_restore_remote_smart_${snapshot_id}\"}],
    [{\"text\": \"🔧 完全恢复\", \"callback_data\": \"confirm_restore_remote_full_${snapshot_id}\"}],
    [{\"text\": \"❌ 取消\", \"callback_data\": \"restore_source_remote\"}]
  ]
}"
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
}

#!/bin/bash

# SnapSync v3.0 - Telegram Bot Part 2
# 恢复确认、删除、配置、帮助等功能

# 接续 Part 1...

# ===== 确认本地恢复（智能/完全）=====
handle_confirm_restore_local_smart() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local snapshot_id="$4"
    
    answer_callback "$callback_id" "开始恢复..."
    
    local file=$(cat "/tmp/local_snapshot_selected_${chat_id}.txt" 2>/dev/null)
    
    if [[ ! -f "$file" ]]; then
        log_bot "快照文件不存在: $file"
        send_message "$chat_id" "❌ 快照文件不存在，恢复失败"
        return
    fi
    
    local name=$(basename "$file")
    
    local message="🔄 <b>恢复进行中...</b>

📸 快照: ${name}
🛡️ 模式: 智能恢复

⏳ 正在恢复系统...
<i>这需要几分钟，请勿关闭服务器</i>"
    
    edit_message "$chat_id" "$message_id" "$message" ""
    
    # 后台执行恢复（智能模式）
    (
        log_bot "开始智能恢复: $file"
        
        # 创建恢复脚本
        cat > /tmp/restore_smart_${chat_id}.sh << EOFSCRIPT
#!/bin/bash
set -euo pipefail

# 加载配置
source /etc/snapsync/config.conf

# 备份关键配置
BACKUP_TMP="/tmp/snapsync_config_\$\$"
mkdir -p "\$BACKUP_TMP"
[[ -d /etc/network ]] && cp -r /etc/network "\$BACKUP_TMP/" 2>/dev/null || true
[[ -d /etc/netplan ]] && cp -r /etc/netplan "\$BACKUP_TMP/" 2>/dev/null || true
[[ -d /etc/ssh ]] && cp -r /etc/ssh "\$BACKUP_TMP/" 2>/dev/null || true
[[ -d /root/.ssh ]] && cp -r /root/.ssh "\$BACKUP_TMP/root_ssh" 2>/dev/null || true

# 解压
cd /
if [[ "$file" =~ \.gz$ ]]; then
    gunzip -c "$file" | tar -xf - --preserve-permissions --same-owner --numeric-owner
elif [[ "$file" =~ \.bz2$ ]]; then
    bunzip2 -c "$file" | tar -xf - --preserve-permissions --same-owner --numeric-owner
else
    tar -xf "$file" --preserve-permissions --same-owner --numeric-owner
fi

# 恢复关键配置
[[ -d "\$BACKUP_TMP/network" ]] && cp -r "\$BACKUP_TMP/network" /etc/ 2>/dev/null || true
[[ -d "\$BACKUP_TMP/netplan" ]] && cp -r "\$BACKUP_TMP/netplan" /etc/ 2>/dev/null || true
[[ -d "\$BACKUP_TMP/ssh" ]] && cp -r "\$BACKUP_TMP/ssh" /etc/ 2>/dev/null || true
[[ -d "\$BACKUP_TMP/root_ssh" ]] && cp -r "\$BACKUP_TMP/root_ssh" /root/.ssh 2>/dev/null || true
chmod 700 /root/.ssh 2>/dev/null || true
chmod 600 /root/.ssh/* 2>/dev/null || true

rm -rf "\$BACKUP_TMP"

# 发送TG通知
if [[ -n "\${TELEGRAM_BOT_TOKEN}" && -n "\${TELEGRAM_CHAT_ID}" ]]; then
    curl -sS -m 15 -X POST "https://api.telegram.org/bot\${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=\${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=🖥️ <b>\${HOSTNAME}</b>
━━━━━━━━━━━━━━━━━━━━━━━
✅ <b>恢复完成</b>

📸 快照: ${name}
🛡️ 模式: 智能恢复

⚠️ 建议重启系统使配置生效" \
        -d "parse_mode=HTML" &>/dev/null || true
fi
EOFSCRIPT
        
        chmod +x /tmp/restore_smart_${chat_id}.sh
        bash /tmp/restore_smart_${chat_id}.sh &>> "$LOG_FILE" || {
            log_bot "恢复失败"
            send_message "$chat_id" "❌ 恢复失败，请检查日志"
        }
        rm -f /tmp/restore_smart_${chat_id}.sh
        
    ) &
}

handle_confirm_restore_local_full() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local snapshot_id="$4"
    
    answer_callback "$callback_id" "开始完全恢复..."
    
    local file=$(cat "/tmp/local_snapshot_selected_${chat_id}.txt" 2>/dev/null)
    
    if [[ ! -f "$file" ]]; then
        log_bot "快照文件不存在: $file"
        send_message "$chat_id" "❌ 快照文件不存在，恢复失败"
        return
    fi
    
    local name=$(basename "$file")
    
    local message="🔄 <b>完全恢复进行中...</b>

📸 快照: ${name}
🔧 模式: 完全恢复

⏳ 正在恢复所有内容...
⚠️ 可能会导致网络断开

<i>这需要几分钟</i>"
    
    edit_message "$chat_id" "$message_id" "$message" ""
    
    # 后台执行完全恢复
    (
        log_bot "开始完全恢复: $file"
        
        cd /
        if [[ "$file" =~ \.gz$ ]]; then
            gunzip -c "$file" | tar -xf - --preserve-permissions --same-owner --numeric-owner 2>&1 | tee -a "$LOG_FILE"
        elif [[ "$file" =~ \.bz2$ ]]; then
            bunzip2 -c "$file" | tar -xf - --preserve-permissions --same-owner --numeric-owner 2>&1 | tee -a "$LOG_FILE"
        else
            tar -xf "$file" --preserve-permissions --same-owner --numeric-owner 2>&1 | tee -a "$LOG_FILE"
        fi
        
        if [[ $? -eq 0 ]]; then
            log_bot "完全恢复完成"
            send_message "$chat_id" "✅ <b>完全恢复完成</b>

⚠️ 建议重启系统"
        else
            log_bot "完全恢复失败"
            send_message "$chat_id" "❌ 恢复失败，请检查日志"
        fi
        
    ) &
}

# ===== 确认远程恢复（修复版）=====
handle_confirm_restore_remote_smart() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local snapshot_id="$4"
    
    answer_callback "$callback_id" "开始下载..."
    
    local remote_file=$(cat "/tmp/remote_snapshot_selected_${chat_id}.txt" 2>/dev/null)
    
    if [[ -z "$remote_file" ]]; then
        log_bot "未找到选中的远程文件"
        send_message "$chat_id" "❌ 会话已过期，请重新选择"
        return
    fi
    
    local name=$(basename "$remote_file")
    
    local message="⬇️ <b>下载中...</b>

📦 文件: ${name}
🌐 服务器: ${REMOTE_HOST}

⏳ 正在下载快照...
<i>下载完成后将自动开始恢复</i>"
    
    edit_message "$chat_id" "$message_id" "$message" ""
    
    # 后台下载并恢复
    (
        log_bot "开始下载远程快照: $remote_file"
        
        local local_dir="${BACKUP_DIR}/system_snapshots"
        mkdir -p "$local_dir"
        
        local local_file="${local_dir}/${name}"
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
        
        local rsync_ssh_cmd="ssh -i $ssh_key -p $REMOTE_PORT"
        for opt in "${ssh_opts[@]}"; do
            rsync_ssh_cmd="$rsync_ssh_cmd $opt"
        done
        
        # 下载
        if rsync -az --partial \
                -e "$rsync_ssh_cmd" \
                "${REMOTE_USER}@${REMOTE_HOST}:${remote_file}" \
                "$local_file" 2>&1 | tee -a "$LOG_FILE"; then
            
            log_bot "下载完成，开始智能恢复"
            send_message "$chat_id" "✅ 下载完成

🔄 开始智能恢复..."
            
            # 执行智能恢复（与本地相同的逻辑）
            BACKUP_TMP="/tmp/snapsync_config_$$"
            mkdir -p "$BACKUP_TMP"
            [[ -d /etc/network ]] && cp -r /etc/network "$BACKUP_TMP/" 2>/dev/null || true
            [[ -d /etc/netplan ]] && cp -r /etc/netplan "$BACKUP_TMP/" 2>/dev/null || true
            [[ -d /etc/ssh ]] && cp -r /etc/ssh "$BACKUP_TMP/" 2>/dev/null || true
            [[ -d /root/.ssh ]] && cp -r /root/.ssh "$BACKUP_TMP/root_ssh" 2>/dev/null || true
            
            cd /
            if [[ "$local_file" =~ \.gz$ ]]; then
                gunzip -c "$local_file" | tar -xf - --preserve-permissions --same-owner --numeric-owner 2>&1 | tee -a "$LOG_FILE"
            else
                tar -xf "$local_file" --preserve-permissions --same-owner --numeric-owner 2>&1 | tee -a "$LOG_FILE"
            fi
            
            # 恢复配置
            [[ -d "$BACKUP_TMP/network" ]] && cp -r "$BACKUP_TMP/network" /etc/ 2>/dev/null || true
            [[ -d "$BACKUP_TMP/netplan" ]] && cp -r "$BACKUP_TMP/netplan" /etc/ 2>/dev/null || true
            [[ -d "$BACKUP_TMP/ssh" ]] && cp -r "$BACKUP_TMP/ssh" /etc/ 2>/dev/null || true
            [[ -d "$BACKUP_TMP/root_ssh" ]] && cp -r "$BACKUP_TMP/root_ssh" /root/.ssh 2>/dev/null || true
            chmod 700 /root/.ssh 2>/dev/null || true
            chmod 600 /root/.ssh/* 2>/dev/null || true
            rm -rf "$BACKUP_TMP"
            
            log_bot "智能恢复完成"
            send_message "$chat_id" "✅ <b>恢复完成</b>

📸 快照: ${name}
🛡️ 模式: 智能恢复

⚠️ 建议重启系统"
            
        else
            log_bot "下载失败"
            send_message "$chat_id" "❌ 下载失败

请检查网络连接和远程服务器"
        fi
        
    ) &
}

handle_confirm_restore_remote_full() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local snapshot_id="$4"
    
    answer_callback "$callback_id" "开始下载..."
    
    local remote_file=$(cat "/tmp/remote_snapshot_selected_${chat_id}.txt" 2>/dev/null)
    
    if [[ -z "$remote_file" ]]; then
        log_bot "未找到选中的远程文件"
        send_message "$chat_id" "❌ 会话已过期，请重新选择"
        return
    fi
    
    local name=$(basename "$remote_file")
    
    local message="⬇️ <b>下载中...</b>

📦 文件: ${name}
🌐 服务器: ${REMOTE_HOST}

⏳ 正在下载快照...
<i>下载完成后将自动开始完全恢复</i>"
    
    edit_message "$chat_id" "$message_id" "$message" ""
    
    # 后台下载并完全恢复
    (
        log_bot "开始下载远程快照（完全恢复）: $remote_file"
        
        local local_dir="${BACKUP_DIR}/system_snapshots"
        mkdir -p "$local_dir"
        
        local local_file="${local_dir}/${name}"
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
        
        local rsync_ssh_cmd="ssh -i $ssh_key -p $REMOTE_PORT"
        for opt in "${ssh_opts[@]}"; do
            rsync_ssh_cmd="$rsync_ssh_cmd $opt"
        done
        
        # 下载
        if rsync -az --partial \
                -e "$rsync_ssh_cmd" \
                "${REMOTE_USER}@${REMOTE_HOST}:${remote_file}" \
                "$local_file" 2>&1 | tee -a "$LOG_FILE"; then
            
            log_bot "下载完成，开始完全恢复"
            send_message "$chat_id" "✅ 下载完成

🔄 开始完全恢复...
⚠️ 可能会导致网络断开"
            
            cd /
            if [[ "$local_file" =~ \.gz$ ]]; then
                gunzip -c "$local_file" | tar -xf - --preserve-permissions --same-owner --numeric-owner 2>&1 | tee -a "$LOG_FILE"
            else
                tar -xf "$local_file" --preserve-permissions --same-owner --numeric-owner 2>&1 | tee -a "$LOG_FILE"
            fi
            
            log_bot "完全恢复完成"
            send_message "$chat_id" "✅ <b>完全恢复完成</b>

⚠️ 建议重启系统"
            
        else
            log_bot "下载失败"
            send_message "$chat_id" "❌ 下载失败

请检查网络连接和远程服务器"
        fi
        
    ) &
}

# ===== 删除快照 =====
handle_menu_delete() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "删除快照"
    
    local snapshots=()
    while IFS= read -r -d '' file; do
        if [[ "$file" != *.sha256 ]]; then
            snapshots+=("$file")
        fi
    done < <(find "${BACKUP_DIR}/system_snapshots" -maxdepth 1 -name "system_snapshot_*.tar*" -type f -print0 2>/dev/null | sort -zr)
    
    if [[ ${#snapshots[@]} -eq 0 ]]; then
        local message="🗑️ <b>删除快照</b>

暂无快照可删除"
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
        
        buttons+="{\"text\": \"$((i+1)). ${short_name}\", \"callback_data\": \"delete_confirm_${i}\"},"
        ((count++))
    done
    buttons="${buttons%,}]"
    
    local keyboard="{\"inline_keyboard\":[$buttons,[{\"text\":\"🔙 返回\",\"callback_data\":\"menu_main\"}]]}"
    
    local message="🗑️ <b>删除快照</b>

找到 ${#snapshots[@]} 个快照

<b>⚠️ 警告:</b>
删除操作不可撤销！

选择要删除的快照:"
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
    
    # 保存快照列表
    local temp_file="/tmp/delete_snapshots_${chat_id}.txt"
    rm -f "$temp_file"
    for snap in "${snapshots[@]}"; do
        echo "$snap" >> "$temp_file"
    done
}

handle_delete_confirm() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local snapshot_id="$4"
    
    answer_callback "$callback_id" "确认删除"
    
    local temp_file="/tmp/delete_snapshots_${chat_id}.txt"
    
    if [[ ! -f "$temp_file" ]]; then
        log_bot "临时文件不存在"
        send_message "$chat_id" "会话已过期，请重新选择"
        return
    fi
    
    local snapshots=()
    local line_num=0
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            snapshots[$line_num]="$line"
            ((line_num++))
        fi
    done < "$temp_file"
    
    if [[ ! "$snapshot_id" =~ ^[0-9]+$ ]] || (( snapshot_id < 0 || snapshot_id >= ${#snapshots[@]} )); then
        log_bot "无效的快照ID"
        send_message "$chat_id" "无效的快照ID"
        return
    fi
    
    local file="${snapshots[$snapshot_id]}"
    local name=$(basename "$file")
    
    local message="🗑️ <b>确认删除</b>

📸 快照: <code>${name}</code>

<b>⚠️ 此操作不可撤销！</b>

确认删除此快照?"
    
    local keyboard="{
  \"inline_keyboard\": [
    [{\"text\": \"✅ 确认删除\", \"callback_data\": \"delete_execute_${snapshot_id}\"}],
    [{\"text\": \"❌ 取消\", \"callback_data\": \"menu_delete\"}]
  ]
}"
    
    edit_message "$chat_id" "$message_id" "$message" "$keyboard"
}

handle_delete_execute() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local snapshot_id="$4"
    
    answer_callback "$callback_id" "删除中..."
    
    local temp_file="/tmp/delete_snapshots_${chat_id}.txt"
    
    if [[ ! -f "$temp_file" ]]; then
        log_bot "临时文件不存在"
        send_message "$chat_id" "会话已过期"
        return
    fi
    
    local snapshots=()
    local line_num=0
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            snapshots[$line_num]="$line"
            ((line_num++))
        fi
    done < "$temp_file"
    
    if [[ ! "$snapshot_id" =~ ^[0-9]+$ ]] || (( snapshot_id < 0 || snapshot_id >= ${#snapshots[@]} )); then
        log_bot "无效的快照ID"
        send_message "$chat_id" "无效的快照ID"
        return
    fi
    
    local file="${snapshots[$snapshot_id]}"
    local name=$(basename "$file")
    
    log_bot "删除快照: $file"
    
    if rm -f "$file" "${file}.sha256" 2>/dev/null; then
        log_bot "删除成功"
        
        local message="✅ <b>删除成功</b>

📸 快照: ${name}

已从本地删除"
        
        edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
    else
        log_bot "删除失败"
        
        local message="❌ <b>删除失败</b>

📸 快照: ${name}

请检查文件权限"
        
        edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
    fi
}

# ===== 配置信息 =====
handle_menu_config() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "配置信息"
    
    local tg_status="❌ 未启用"
    local tg_enabled=$(echo "${TELEGRAM_ENABLED:-false}" | tr '[:upper:]' '[:lower:]')
    if [[ "$tg_enabled" == "y" || "$tg_enabled" == "yes" || "$tg_enabled" == "true" ]]; then
        tg_status="✅ 已启用"
    fi
    
    local remote_status="❌ 未启用"
    local remote_enabled=$(echo "${REMOTE_ENABLED:-false}" | tr '[:upper:]' '[:lower:]')
    if [[ "$remote_enabled" == "y" || "$remote_enabled" == "yes" || "$remote_enabled" == "true" ]]; then
        remote_status="✅ 已启用"
    fi
    
    local message="⚙️ <b>配置信息</b>

<b>本地备份:</b>
📂 目录: <code>${BACKUP_DIR}</code>
🗜️ 压缩级别: ${COMPRESSION_LEVEL}
💾 保留数量: ${LOCAL_KEEP_COUNT} 个

<b>远程备份:</b>
${remote_status}
🌐 服务器: ${REMOTE_HOST:-未配置}
👤 用户: ${REMOTE_USER:-root}
🔌 端口: ${REMOTE_PORT:-22}

<b>Telegram:</b>
${tg_status}

<b>主机信息:</b>
🖥️ 主机名: ${HOSTNAME}

<i>修改配置请使用主控制台</i>"
    
    edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
}

# ===== 帮助信息 =====
handle_menu_help() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "帮助"
    
    local message="❓ <b>使用帮助</b>

<b>功能说明:</b>

📊 <b>系统状态</b>
查看主机运行状态和快照统计

📋 <b>快照列表</b>
查看所有本地快照

🔄 <b>创建快照</b>
创建系统完整备份

♻️ <b>恢复快照</b>
从本地或远程恢复系统

🗑️ <b>删除快照</b>
删除指定快照释放空间

⚙️ <b>配置信息</b>
查看当前配置

<b>恢复模式:</b>
• 智能恢复: 保留网络/SSH（推荐）
• 完全恢复: 恢复所有内容（谨慎）

<b>主控制台:</b>
运行 <code>sudo snapsync</code>

<b>完整文档:</b>
https://github.com/kelenetwork/SnapSync"
    
    edit_message "$chat_id" "$message_id" "$message" "$(get_back_button)"
}

# ===== 回调路由 =====
handle_callback() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local data="$4"
    
    log_bot "收到回调: $data"
    
    case "$data" in
        menu_main)
            handle_menu_main "$chat_id" "$message_id" "$callback_id"
            ;;
        menu_status)
            handle_menu_status "$chat_id" "$message_id" "$callback_id"
            ;;
        menu_snapshots)
            handle_menu_snapshots "$chat_id" "$message_id" "$callback_id"
            ;;
        menu_backup)
            handle_menu_backup "$chat_id" "$message_id" "$callback_id"
            ;;
        confirm_backup)
            handle_confirm_backup "$chat_id" "$message_id" "$callback_id"
            ;;
        menu_restore)
            handle_menu_restore "$chat_id" "$message_id" "$callback_id"
            ;;
        restore_source_local)
            handle_restore_source_local "$chat_id" "$message_id" "$callback_id"
            ;;
        restore_source_remote)
            handle_restore_source_remote "$chat_id" "$message_id" "$callback_id"
            ;;
        restore_local_*)
            local snapshot_id="${data#restore_local_}"
            handle_restore_local "$chat_id" "$message_id" "$callback_id" "$snapshot_id"
            ;;
        restore_remote_*)
            local snapshot_id="${data#restore_remote_}"
            handle_restore_remote "$chat_id" "$message_id" "$callback_id" "$snapshot_id"
            ;;
        confirm_restore_local_smart_*)
            local snapshot_id="${data#confirm_restore_local_smart_}"
            handle_confirm_restore_local_smart "$chat_id" "$message_id" "$callback_id" "$snapshot_id"
            ;;
        confirm_restore_local_full_*)
            local snapshot_id="${data#confirm_restore_local_full_}"
            handle_confirm_restore_local_full "$chat_id" "$message_id" "$callback_id" "$snapshot_id"
            ;;
        confirm_restore_remote_smart_*)
            local snapshot_id="${data#confirm_restore_remote_smart_}"
            handle_confirm_restore_remote_smart "$chat_id" "$message_id" "$callback_id" "$snapshot_id"
            ;;
        confirm_restore_remote_full_*)
            local snapshot_id="${data#confirm_restore_remote_full_}"
            handle_confirm_restore_remote_full "$chat_id" "$message_id" "$callback_id" "$snapshot_id"
            ;;
        menu_delete)
            handle_menu_delete "$chat_id" "$message_id" "$callback_id"
            ;;
        delete_confirm_*)
            local snapshot_id="${data#delete_confirm_}"
            handle_delete_confirm "$chat_id" "$message_id" "$callback_id" "$snapshot_id"
            ;;
        delete_execute_*)
            local snapshot_id="${data#delete_execute_}"
            handle_delete_execute "$chat_id" "$message_id" "$callback_id" "$snapshot_id"
            ;;
        menu_config)
            handle_menu_config "$chat_id" "$message_id" "$callback_id"
            ;;
        menu_help)
            handle_menu_help "$chat_id" "$message_id" "$callback_id"
            ;;
        *)
            log_bot "未知回调: $data"
            answer_callback "$callback_id" "未知操作"
            ;;
    esac
}

# ===== 主循环 =====
main_loop() {
    log_bot "Bot 启动: ${HOSTNAME}"
    
    while true; do
        # 获取更新
        local updates=$(curl -sS -m 10 "${API_URL}/getUpdates?offset=${LAST_UPDATE_ID}&timeout=30" 2>/dev/null)
        
        if [[ -z "$updates" ]] || ! echo "$updates" | grep -q '"ok":true'; then
            sleep 1
            continue
        fi
        
        # 解析更新
        local update_ids=$(echo "$updates" | grep -o '"update_id":[0-9]*' | cut -d':' -f2)
        
        if [[ -z "$update_ids" ]]; then
            sleep 1
            continue
        fi
        
        # 处理每个更新
        while read -r update_id; do
            [[ -z "$update_id" ]] && continue
            
            LAST_UPDATE_ID=$((update_id + 1))
            
            # 提取消息或回调
            local result=$(echo "$updates" | grep -A 50 "\"update_id\":$update_id")
            
            # 处理命令
            if echo "$result" | grep -q '"text":"/start"'; then
                local chat_id=$(echo "$result" | grep -o '"chat":{"id":[0-9-]*' | grep -o '[0-9-]*$')
                [[ -n "$chat_id" ]] && handle_start "$chat_id"
                
            # 处理回调
            elif echo "$result" | grep -q '"callback_query"'; then
                local chat_id=$(echo "$result" | grep -o '"chat":{"id":[0-9-]*' | grep -o '[0-9-]*$' | head -1)
                local message_id=$(echo "$result" | grep -o '"message_id":[0-9]*' | head -1 | cut -d':' -f2)
                local callback_id=$(echo "$result" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
                local callback_data=$(echo "$result" | grep -o '"data":"[^"]*"' | cut -d'"' -f4)
                
                if [[ -n "$chat_id" && -n "$message_id" && -n "$callback_id" && -n "$callback_data" ]]; then
                    handle_callback "$chat_id" "$message_id" "$callback_id" "$callback_data"
                fi
            fi
            
        done <<< "$update_ids"
        
        sleep 0.5
    done
}

# ===== 启动 =====
log_bot "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_bot "SnapSync Telegram Bot v3.0"
log_bot "主机: ${HOSTNAME}"
log_bot "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 检查配置
if [[ -z "$TELEGRAM_BOT_TOKEN" ]] || [[ -z "$TELEGRAM_CHAT_ID" ]]; then
    log_bot "错误: Telegram 配置不完整"
    exit 1
fi

# 启动主循环
main_loop
