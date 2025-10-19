#!/bin/bash

# SnapSync v3.0 - Telegram Bot（完整重写版）
# 功能：系统状态、快照管理、配置管理、日志查看、连接测试

set -euo pipefail

# ===== 配置文件 =====
CONFIG_FILE="/etc/snapsync/config.conf"
LOG_FILE="/var/log/snapsync/bot.log"
OFFSET_FILE="/var/run/snapsync_bot_offset"

# ===== 检查配置 =====
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] 配置文件不存在: $CONFIG_FILE" >> "$LOG_FILE"
    exit 1
fi

source "$CONFIG_FILE" || exit 1

# ===== 全局变量 =====
API="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"
HOST="${HOSTNAME:-$(hostname)}"
BACKUP_DIR="${BACKUP_DIR:-/backups}"

mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$OFFSET_FILE")"

# ===== 日志函数 =====
log() {
    echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"
}

# ===== API 调用函数 =====
call_api() {
    curl -sS -m 15 -X POST "${API}/$1" "${@:2}" 2>/dev/null || echo '{"ok":false}'
}

send_message() {
    local chat_id="$1"
    local text="$2"
    local keyboard="${3:-}"
    
    call_api sendMessage \
        -d "chat_id=$chat_id" \
        --data-urlencode "text=🖥️ <b>${HOST}</b>
━━━━━━━━━━━━━━━━━━━━━━━━━
$text" \
        -d "parse_mode=HTML" \
        ${keyboard:+-d "reply_markup=$keyboard"}
}

edit_message() {
    local chat_id="$1"
    local message_id="$2"
    local text="$3"
    local keyboard="${4:-}"
    
    call_api editMessageText \
        -d "chat_id=$chat_id" \
        -d "message_id=$message_id" \
        --data-urlencode "text=🖥️ <b>${HOST}</b>
━━━━━━━━━━━━━━━━━━━━━━━━━
$text" \
        -d "parse_mode=HTML" \
        ${keyboard:+-d "reply_markup=$keyboard"}
}

answer_callback() {
    local callback_id="$1"
    local text="${2:-✓}"
    call_api answerCallbackQuery -d "callback_query_id=$callback_id" -d "text=$text" >/dev/null
}

# ===== 工具函数 =====
format_bytes() {
    local bytes="$1"
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

get_cpu_usage() {
    top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1
}

get_mem_usage() {
    free | awk '/Mem:/ {printf "%.1f", $3/$2*100}'
}

get_backup_dir_size() {
    du -sh "${BACKUP_DIR}/system_snapshots" 2>/dev/null | awk '{print $1}' || echo "0B"
}

get_next_backup_time() {
    systemctl list-timers snapsync-backup.timer 2>/dev/null | awk '/snapsync-backup.timer/ {print $1,$2,$3}' | head -1 || echo "未启用"
}

# ===== 菜单构建 =====
menu_main() {
    cat << 'EOF'
{"inline_keyboard":[
[{"text":"📊 系统状态","callback_data":"status"}],
[{"text":"📋 快照列表","callback_data":"list"}],
[{"text":"🔄 创建快照","callback_data":"backup"},{"text":"♻️ 恢复指南","callback_data":"restore"}],
[{"text":"🗑️ 删除快照","callback_data":"delete"}],
[{"text":"⚙️ 配置管理","callback_data":"config"}],
[{"text":"📝 查看日志","callback_data":"logs"},{"text":"🔌 测试连接","callback_data":"test"}]
]}
EOF
}

menu_back() {
    echo '{"inline_keyboard":[[{"text":"🔙 返回主菜单","callback_data":"main"}]]}'
}

menu_config() {
    cat << 'EOF'
{"inline_keyboard":[
[{"text":"📦 快照保留策略","callback_data":"cfg_retention"}],
[{"text":"⏰ 备份计划","callback_data":"cfg_schedule"}],
[{"text":"🗜️ 压缩级别","callback_data":"cfg_compress"}],
[{"text":"🌐 远程备份","callback_data":"cfg_remote"}],
[{"text":"🔙 返回主菜单","callback_data":"main"}]
]}
EOF
}

menu_logs() {
    cat << 'EOF'
{"inline_keyboard":[
[{"text":"📘 备份日志","callback_data":"log_backup"}],
[{"text":"📗 恢复日志","callback_data":"log_restore"}],
[{"text":"📙 Bot日志","callback_data":"log_bot"}],
[{"text":"🔙 返回主菜单","callback_data":"main"}]
]}
EOF
}

menu_test() {
    cat << 'EOF'
{"inline_keyboard":[
[{"text":"🌐 测试远程服务器","callback_data":"test_remote"}],
[{"text":"📱 测试Telegram","callback_data":"test_tg"}],
[{"text":"🔙 返回主菜单","callback_data":"main"}]
]}
EOF
}

menu_confirm_backup() {
    local with_upload="$1"
    if [[ "$with_upload" == "yes" ]]; then
        cat << 'EOF'
{"inline_keyboard":[
[{"text":"✅ 创建并上传","callback_data":"backup_exec_upload"}],
[{"text":"💾 仅本地备份","callback_data":"backup_exec_local"}],
[{"text":"❌ 取消","callback_data":"main"}]
]}
EOF
    else
        cat << 'EOF'
{"inline_keyboard":[
[{"text":"✅ 确认创建","callback_data":"backup_exec_local"}],
[{"text":"❌ 取消","callback_data":"main"}]
]}
EOF
    fi
}

menu_compress_level() {
    cat << 'EOF'
{"inline_keyboard":[
[{"text":"1️⃣ 最快","callback_data":"cmp_1"},{"text":"3️⃣ 快","callback_data":"cmp_3"},{"text":"6️⃣ 平衡","callback_data":"cmp_6"}],
[{"text":"9️⃣ 最高压缩","callback_data":"cmp_9"}],
[{"text":"🔙 返回配置","callback_data":"config"}]
]}
EOF
}

menu_remote_toggle() {
    cat << 'EOF'
{"inline_keyboard":[
[{"text":"✅ 启用","callback_data":"rmt_on"}],
[{"text":"❌ 禁用","callback_data":"rmt_off"}],
[{"text":"🔙 返回配置","callback_data":"config"}]
]}
EOF
}

# ===== 命令处理 =====
cmd_start() {
    local chat_id="$1"
    log "[CMD] /start from $chat_id"
    send_message "$chat_id" "🎯 <b>SnapSync 控制中心</b>

📦 版本: v3.0
🖥️ 主机: ${HOST}

<i>选择功能开始操作</i>" "$(menu_main)"
}

# ===== 回调处理 =====
cb_main() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id"
    edit_message "$chat_id" "$message_id" "🎯 <b>SnapSync 控制中心</b>

📦 版本: v3.0
🖥️ 主机: ${HOST}

<i>选择功能开始操作</i>" "$(menu_main)"
}

cb_status() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id"
    
    # 收集系统信息
    local uptime=$(uptime -p 2>/dev/null || echo "未知")
    local load=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    local cpu=$(get_cpu_usage)
    local mem=$(get_mem_usage)
    local disk=$(df -h "$BACKUP_DIR" 2>/dev/null | awk 'NR==2 {print $5}')
    local disk_free=$(df -h "$BACKUP_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
    local snapshot_count=$(find "${BACKUP_DIR}/system_snapshots" -name "*.tar*" -type f 2>/dev/null | grep -cv sha256 || echo 0)
    local backup_size=$(get_backup_dir_size)
    local next_backup=$(get_next_backup_time)
    
    edit_message "$chat_id" "$message_id" "📊 <b>系统状态</b>

<b>⚡ 系统运行</b>
🕐 运行时间: ${uptime}
📈 负载: ${load}
🔥 CPU: ${cpu}%
💾 内存: ${mem}%

<b>💿 磁盘状态</b>
📊 使用率: ${disk}
💽 可用: ${disk_free}

<b>📦 备份状态</b>
📸 快照数量: ${snapshot_count} 个
📁 占用空间: ${backup_size}
⏰ 下次备份: ${next_backup}

<i>更新时间: $(date '+%H:%M:%S')</i>" "$(menu_back)"
}

cb_list() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id"
    
    local snapshot_dir="${BACKUP_DIR}/system_snapshots"
    
    if [[ ! -d "$snapshot_dir" ]]; then
        edit_message "$chat_id" "$message_id" "📋 <b>快照列表</b>

❌ 快照目录不存在
📂 目录: ${snapshot_dir}

<i>请先创建快照</i>" "$(menu_back)"
        return
    fi
    
    local snapshots=()
    while IFS= read -r -d '' file; do
        if [[ "$file" != *.sha256 ]]; then
            snapshots+=("$file")
        fi
    done < <(find "$snapshot_dir" -maxdepth 1 -name "*.tar*" -type f -print0 2>/dev/null | sort -zr)
    
    if [[ ${#snapshots[@]} -eq 0 ]]; then
        edit_message "$chat_id" "$message_id" "📋 <b>快照列表</b>

❌ 暂无快照

<i>点击「创建快照」开始备份</i>" "$(menu_back)"
        return
    fi
    
    local text="📋 <b>快照列表</b>

找到 ${#snapshots[@]} 个快照:
━━━━━━━━━━━━━━━━━━━━━━━━━

"
    
    local idx=1
    for file in "${snapshots[@]}"; do
        local name=$(basename "$file")
        local size=$(stat -c%s "$file" 2>/dev/null || echo 0)
        local size_human=$(format_bytes "$size")
        local date=$(date -r "$file" "+%m-%d %H:%M" 2>/dev/null || echo "未知")
        local checksum="❌"
        [[ -f "${file}.sha256" ]] && checksum="✅"
        
        text+="${idx}. <b>${name}</b>
   📦 ${size_human} | 📅 ${date} | ${checksum}

"
        ((idx++))
        
        # 限制显示数量避免消息过长
        [[ $idx -gt 20 ]] && text+="<i>... 还有 $((${#snapshots[@]} - 20)) 个快照未显示</i>

" && break
    done
    
    edit_message "$chat_id" "$message_id" "$text" "$(menu_back)"
}

cb_backup() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id"
    
    # 检查远程备份是否启用
    source "$CONFIG_FILE"
    local remote_enabled="no"
    if [[ "$(echo ${REMOTE_ENABLED:-false} | tr '[:upper:]' '[:lower:]')" =~ ^(y|yes|true)$ ]]; then
        remote_enabled="yes"
    fi
    
    if [[ "$remote_enabled" == "yes" ]]; then
        edit_message "$chat_id" "$message_id" "🔄 <b>创建快照</b>

⚠️ <b>注意事项</b>
• 备份需要 3-10 分钟
• 期间请勿关闭服务器
• 完成后会收到通知

🌐 <b>远程备份已启用</b>
是否上传到远程服务器？

💡 <i>上传会消耗额外时间和带宽</i>" "$(menu_confirm_backup yes)"
    else
        edit_message "$chat_id" "$message_id" "🔄 <b>创建快照</b>

⚠️ <b>注意事项</b>
• 备份需要 3-10 分钟
• 期间请勿关闭服务器
• 完成后会收到通知

确认创建快照？" "$(menu_confirm_backup no)"
    fi
}

cb_backup_exec() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local upload="$4"
    
    answer_callback "$callback_id" "⏳ 开始创建快照..."
    
    edit_message "$chat_id" "$message_id" "🔄 <b>备份进行中</b>

⏳ 正在创建系统快照...
📦 压缩文件中...

<i>这可能需要几分钟，请稍候</i>

💡 备份完成后会自动通知您"
    
    # 在后台执行备份
    (
        if [[ "$upload" == "upload" ]]; then
            UPLOAD_REMOTE="yes" bash /opt/snapsync/modules/backup.sh &>/dev/null
        else
            UPLOAD_REMOTE="no" bash /opt/snapsync/modules/backup.sh &>/dev/null
        fi
        
        if [[ $? -eq 0 ]]; then
            log "[BACKUP] 手动备份完成 (upload: $upload)"
        else
            log "[ERROR] 手动备份失败"
            send_message "$chat_id" "❌ <b>备份失败</b>

请查看日志了解详情
或使用「测试连接」排查问题" "$(menu_back)"
        fi
    ) &
}

cb_restore() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id"
    
    edit_message "$chat_id" "$message_id" "♻️ <b>系统恢复指南</b>

⚠️ <b>重要提示</b>
系统恢复需要在服务器上操作
Bot 无法直接执行恢复命令

<b>📝 恢复步骤</b>

1️⃣ SSH 登录服务器
<code>ssh root@${HOST}</code>

2️⃣ 启动恢复程序
<code>sudo snapsync-restore</code>

3️⃣ 按照提示操作
• 选择恢复来源（本地/远程）
• 选择快照文件
• 选择恢复模式（智能/完全）
• 确认并执行

4️⃣ 恢复完成后重启
<code>sudo reboot</code>

💡 <b>建议</b>
• 使用「智能恢复」模式保留网络配置
• 恢复前备份重要数据
• 测试环境先验证

<i>需要帮助？查看完整文档</i>" "$(menu_back)"
}

cb_delete() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id"
    
    local snapshot_dir="${BACKUP_DIR}/system_snapshots"
    local snapshots=()
    
    while IFS= read -r -d '' file; do
        if [[ "$file" != *.sha256 ]]; then
            snapshots+=("$file")
        fi
    done < <(find "$snapshot_dir" -maxdepth 1 -name "*.tar*" -type f -print0 2>/dev/null | sort -zr)
    
    if [[ ${#snapshots[@]} -eq 0 ]]; then
        edit_message "$chat_id" "$message_id" "🗑️ <b>删除快照</b>

❌ 暂无可删除的快照" "$(menu_back)"
        return
    fi
    
    # 保存快照列表
    printf "%s\n" "${snapshots[@]}" > "/tmp/snapshots_${chat_id}.txt"
    
    # 构建按钮（最多显示10个）
    local buttons='['
    local idx=0
    for file in "${snapshots[@]}"; do
        [[ $idx -ge 10 ]] && break
        local name=$(basename "$file")
        local short_name="${name:17:20}"  # 截取部分名称
        buttons+="[{\"text\":\"$((idx+1)). ${short_name}...\",\"callback_data\":\"del_${idx}\"}],"
        ((idx++))
    done
    buttons="${buttons%,}]"
    
    local menu="{\"inline_keyboard\":${buttons},[{\"text\":\"🔙 返回主菜单\",\"callback_data\":\"main\"}]}"
    
    edit_message "$chat_id" "$message_id" "🗑️ <b>删除快照</b>

找到 ${#snapshots[@]} 个快照
请选择要删除的快照:

⚠️ <b>删除后无法恢复</b>
${idx}/10 显示，完整列表见「快照列表」" "$menu"
}

cb_delete_confirm() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local idx="$4"
    
    answer_callback "$callback_id"
    
    local snapshots=()
    while IFS= read -r line; do
        snapshots+=("$line")
    done < "/tmp/snapshots_${chat_id}.txt"
    
    local file="${snapshots[$idx]}"
    local name=$(basename "$file")
    local size=$(stat -c%s "$file" 2>/dev/null || echo 0)
    local size_human=$(format_bytes "$size")
    
    edit_message "$chat_id" "$message_id" "🗑️ <b>确认删除</b>

📸 快照: <code>${name}</code>
📦 大小: ${size_human}

⚠️ <b>此操作不可撤销！</b>
确认删除？" "{\"inline_keyboard\":[[{\"text\":\"✅ 确认删除\",\"callback_data\":\"delx_${idx}\"}],[{\"text\":\"❌ 取消\",\"callback_data\":\"delete\"}]]}"
}

cb_delete_execute() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local idx="$4"
    
    answer_callback "$callback_id" "🗑️ 正在删除..."
    
    local snapshots=()
    while IFS= read -r line; do
        snapshots+=("$line")
    done < "/tmp/snapshots_${chat_id}.txt"
    
    local file="${snapshots[$idx]}"
    local name=$(basename "$file")
    
    if rm -f "$file" "${file}.sha256" 2>/dev/null; then
        edit_message "$chat_id" "$message_id" "✅ <b>删除成功</b>

📸 ${name}

已从系统中移除" "$(menu_back)"
        log "[DELETE] 删除快照: $name"
    else
        edit_message "$chat_id" "$message_id" "❌ <b>删除失败</b>

📸 ${name}

可能权限不足或文件不存在" "$(menu_back)"
    fi
    
    rm -f "/tmp/snapshots_${chat_id}.txt"
}

cb_config() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id"
    
    source "$CONFIG_FILE"
    
    edit_message "$chat_id" "$message_id" "⚙️ <b>配置管理</b>

📦 本地保留: ${LOCAL_KEEP_COUNT:-5} 个
🌐 远程保留: ${REMOTE_KEEP_DAYS:-30} 天
⏰ 备份间隔: ${BACKUP_INTERVAL_DAYS:-7} 天
🕐 备份时间: ${BACKUP_TIME:-03:00}
🗜️ 压缩级别: ${COMPRESSION_LEVEL:-6}
🌐 远程备份: ${REMOTE_ENABLED:-false}

<i>点击下方选项修改配置</i>" "$(menu_config)"
}

cb_config_retention() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id"
    
    source "$CONFIG_FILE"
    
    edit_message "$chat_id" "$message_id" "📦 <b>快照保留策略</b>

当前配置:
• 本地保留: ${LOCAL_KEEP_COUNT:-5} 个
• 远程保留: ${REMOTE_KEEP_DAYS:-30} 天

<b>修改方法</b>
发送格式: <code>本地数量 远程天数</code>

示例:
<code>10 60</code> - 本地保留10个，远程保留60天
<code>5 30</code> - 本地保留5个，远程保留30天

<i>发送配置或返回</i>" "$(menu_back)"
    
    echo "cfg_retention" > "/tmp/config_${chat_id}.txt"
}

cb_config_schedule() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id"
    
    source "$CONFIG_FILE"
    
    edit_message "$chat_id" "$message_id" "⏰ <b>备份计划</b>

当前配置:
• 备份间隔: ${BACKUP_INTERVAL_DAYS:-7} 天
• 备份时间: ${BACKUP_TIME:-03:00}

<b>修改方法</b>
发送格式: <code>间隔天数 时间</code>

示例:
<code>1 02:00</code> - 每天凌晨2点
<code>7 03:30</code> - 每7天凌晨3:30
<code>30 04:00</code> - 每30天凌晨4点

<i>发送配置或返回</i>" "$(menu_back)"
    
    echo "cfg_schedule" > "/tmp/config_${chat_id}.txt"
}

cb_config_compress() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id"
    
    source "$CONFIG_FILE"
    
    edit_message "$chat_id" "$message_id" "🗜️ <b>压缩级别</b>

当前: ${COMPRESSION_LEVEL:-6}

<b>级别说明</b>
1️⃣ 最快 - 速度快，压缩率低
3️⃣ 快速 - 平衡速度和压缩率
6️⃣ 平衡 - 推荐，性能最优
9️⃣ 最高 - 压缩率最高，速度慢

<i>选择压缩级别</i>" "$(menu_compress_level)"
}

cb_config_remote() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id"
    
    source "$CONFIG_FILE"
    
    local status="❌ 禁用"
    if [[ "$(echo ${REMOTE_ENABLED:-false} | tr '[:upper:]' '[:lower:]')" =~ ^(y|yes|true)$ ]]; then
        status="✅ 启用"
    fi
    
    edit_message "$chat_id" "$message_id" "🌐 <b>远程备份</b>

当前状态: ${status}

服务器: ${REMOTE_HOST:-未配置}
用户: ${REMOTE_USER:-root}
端口: ${REMOTE_PORT:-22}

<b>注意</b>
启用前请确保:
• SSH密钥已配置
• 远程服务器可访问
• 网络连接稳定

<i>选择操作</i>" "$(menu_remote_toggle)"
}

cb_compress_set() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local level="$4"
    
    answer_callback "$callback_id" "✅ 压缩级别已设置为 $level"
    
    sed -i "s|^COMPRESSION_LEVEL=.*|COMPRESSION_LEVEL=\"$level\"|" "$CONFIG_FILE"
    
    cb_config "$chat_id" "$message_id" "$callback_id"
    log "[CONFIG] 压缩级别设置为: $level"
}

cb_remote_toggle() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local action="$4"
    
    local value="false"
    local status="禁用"
    if [[ "$action" == "on" ]]; then
        value="true"
        status="启用"
    fi
    
    answer_callback "$callback_id" "✅ 远程备份已${status}"
    
    sed -i "s|^REMOTE_ENABLED=.*|REMOTE_ENABLED=\"$value\"|" "$CONFIG_FILE"
    
    cb_config "$chat_id" "$message_id" "$callback_id"
    log "[CONFIG] 远程备份: $value"
}

cb_logs() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id"
    
    edit_message "$chat_id" "$message_id" "📝 <b>查看日志</b>

选择要查看的日志:

📘 备份日志 - 快照创建记录
📗 恢复日志 - 系统恢复记录  
📙 Bot日志 - Bot运行记录

<i>显示最近50行</i>" "$(menu_logs)"
}

cb_log_view() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local log_type="$4"
    
    answer_callback "$callback_id"
    
    local log_file=""
    local title=""
    
    case "$log_type" in
        backup)
            log_file="/var/log/snapsync/backup.log"
            title="📘 备份日志"
            ;;
        restore)
            log_file="/var/log/snapsync/restore.log"
            title="📗 恢复日志"
            ;;
        bot)
            log_file="/var/log/snapsync/bot.log"
            title="📙 Bot日志"
            ;;
    esac
    
    if [[ ! -f "$log_file" ]]; then
        edit_message "$chat_id" "$message_id" "${title}

❌ 日志文件不存在

<i>可能还没有相关操作记录</i>" "$(menu_back)"
        return
    fi
    
    local log_content=$(tail -50 "$log_file" | sed 's/</\&lt;/g; s/>/\&gt;/g')
    
    # 限制消息长度
    if [[ ${#log_content} -gt 3000 ]]; then
        log_content="${log_content: -3000}"
        log_content="... (内容过长，仅显示末尾)

$log_content"
    fi
    
    edit_message "$chat_id" "$message_id" "${title}

<code>${log_content}</code>

<i>最近50行记录</i>" "$(menu_back)"
}

cb_test() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id"
    
    edit_message "$chat_id" "$message_id" "🔌 <b>连接测试</b>

选择要测试的连接:

🌐 远程服务器 - SSH连接测试
📱 Telegram - API连接测试

<i>测试可能需要几秒钟</i>" "$(menu_test)"
}

cb_test_remote() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "⏳ 测试中..."
    
    source "$CONFIG_FILE"
    
    if [[ -z "${REMOTE_HOST:-}" ]]; then
        edit_message "$chat_id" "$message_id" "🌐 <b>远程服务器测试</b>

❌ 未配置远程服务器

请先在配置管理中设置" "$(menu_back)"
        return
    fi
    
    local result="⏳ 正在测试..."
    edit_message "$chat_id" "$message_id" "🌐 <b>远程服务器测试</b>

服务器: ${REMOTE_HOST}
用户: ${REMOTE_USER}
端口: ${REMOTE_PORT}

$result"
    
    # 执行测试
    local ssh_key="/root/.ssh/id_ed25519"
    local test_output=""
    
    if [[ ! -f "$ssh_key" ]]; then
        result="❌ SSH密钥不存在

路径: $ssh_key
需要先生成密钥并添加到远程服务器"
    elif ssh -i "$ssh_key" -p "${REMOTE_PORT}" \
              -o StrictHostKeyChecking=no \
              -o ConnectTimeout=10 \
              -o BatchMode=yes \
              "${REMOTE_USER}@${REMOTE_HOST}" "echo ok" &>/dev/null; then
        result="✅ 连接成功

SSH密钥验证通过
远程服务器正常响应"
    else
        result="❌ 连接失败

可能原因:
• SSH密钥未添加到远程服务器
• 远程服务器不可达
• 防火墙阻止连接
• 端口配置错误

排查命令:
<code>ssh -i $ssh_key -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST}</code>"
    fi
    
    edit_message "$chat_id" "$message_id" "🌐 <b>远程服务器测试</b>

服务器: ${REMOTE_HOST}
用户: ${REMOTE_USER}
端口: ${REMOTE_PORT}

$result" "$(menu_back)"
}

cb_test_telegram() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    
    answer_callback "$callback_id" "⏳ 测试中..."
    
    edit_message "$chat_id" "$message_id" "📱 <b>Telegram 测试</b>

⏳ 正在测试API连接..."
    
    # 测试 getMe
    local result=""
    local api_test=$(curl -sS -m 10 "${API}/getMe")
    
    if echo "$api_test" | grep -q '"ok":true'; then
        local bot_username=$(echo "$api_test" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
        result="✅ Telegram API 正常

Bot用户名: @${bot_username}
连接状态: 正常
消息发送: 正常

如果你看到这条消息，说明:
• Bot Token 配置正确
• 网络连接正常
• 消息推送正常"
    else
        result="❌ API测试失败

可能原因:
• Bot Token 错误
• 网络无法访问Telegram
• 需要代理

响应: ${api_test:0:200}"
    fi
    
    edit_message "$chat_id" "$message_id" "📱 <b>Telegram 测试</b>

$result" "$(menu_back)"
}

# ===== 文本消息处理 =====
handle_text() {
    local chat_id="$1"
    local text="$2"
    
    # 处理命令
    if [[ "$text" == "/start" ]]; then
        rm -f "/tmp/config_${chat_id}.txt" 2>/dev/null
        cmd_start "$chat_id"
        return
    fi
    
    # 检查是否在配置模式
    local config_mode=$(cat "/tmp/config_${chat_id}.txt" 2>/dev/null)
    
    if [[ -z "$config_mode" ]]; then
        send_message "$chat_id" "❓ 未知命令

发送 /start 打开主菜单" "$(menu_main)"
        return
    fi
    
    # 处理配置输入
    case "$config_mode" in
        cfg_retention)
            if [[ "$text" =~ ^([0-9]+)\ +([0-9]+)$ ]]; then
                local local_keep="${BASH_REMATCH[1]}"
                local remote_keep="${BASH_REMATCH[2]}"
                
                sed -i "s|^LOCAL_KEEP_COUNT=.*|LOCAL_KEEP_COUNT=\"$local_keep\"|" "$CONFIG_FILE"
                sed -i "s|^REMOTE_KEEP_DAYS=.*|REMOTE_KEEP_DAYS=\"$remote_keep\"|" "$CONFIG_FILE"
                
                send_message "$chat_id" "✅ <b>保留策略已更新</b>

📦 本地保留: ${local_keep} 个
🌐 远程保留: ${remote_keep} 天" "$(menu_main)"
                
                rm -f "/tmp/config_${chat_id}.txt"
                log "[CONFIG] 保留策略更新: local=$local_keep, remote=$remote_keep"
            else
                send_message "$chat_id" "❌ <b>格式错误</b>

请使用: <code>本地数量 远程天数</code>

示例: <code>10 60</code>" "$(menu_back)"
            fi
            ;;
            
        cfg_schedule)
            if [[ "$text" =~ ^([0-9]+)\ +([0-9]{2}:[0-9]{2})$ ]]; then
                local interval="${BASH_REMATCH[1]}"
                local time="${BASH_REMATCH[2]}"
                
                sed -i "s|^BACKUP_INTERVAL_DAYS=.*|BACKUP_INTERVAL_DAYS=\"$interval\"|" "$CONFIG_FILE"
                sed -i "s|^BACKUP_TIME=.*|BACKUP_TIME=\"$time\"|" "$CONFIG_FILE"
                
                send_message "$chat_id" "✅ <b>备份计划已更新</b>

⏰ 间隔: 每 ${interval} 天
🕐 时间: ${time}

<i>需要重启定时器生效</i>
重启命令: <code>systemctl restart snapsync-backup.timer</code>" "$(menu_main)"
                
                rm -f "/tmp/config_${chat_id}.txt"
                log "[CONFIG] 备份计划更新: interval=$interval, time=$time"
            else
                send_message "$chat_id" "❌ <b>格式错误</b>

请使用: <code>间隔天数 时间</code>

示例: <code>7 03:00</code>" "$(menu_back)"
            fi
            ;;
    esac
}

# ===== 回调路由 =====
route_callback() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local data="$4"
    
    log "[CB] $data from $chat_id"
    
    case "$data" in
        main) cb_main "$chat_id" "$message_id" "$callback_id" ;;
        status) cb_status "$chat_id" "$message_id" "$callback_id" ;;
        list) cb_list "$chat_id" "$message_id" "$callback_id" ;;
        backup) cb_backup "$chat_id" "$message_id" "$callback_id" ;;
        backup_exec_local) cb_backup_exec "$chat_id" "$message_id" "$callback_id" "local" ;;
        backup_exec_upload) cb_backup_exec "$chat_id" "$message_id" "$callback_id" "upload" ;;
        restore) cb_restore "$chat_id" "$message_id" "$callback_id" ;;
        delete) cb_delete "$chat_id" "$message_id" "$callback_id" ;;
        del_*) cb_delete_confirm "$chat_id" "$message_id" "$callback_id" "${data#del_}" ;;
        delx_*) cb_delete_execute "$chat_id" "$message_id" "$callback_id" "${data#delx_}" ;;
        config) cb_config "$chat_id" "$message_id" "$callback_id" ;;
        cfg_retention) cb_config_retention "$chat_id" "$message_id" "$callback_id" ;;
        cfg_schedule) cb_config_schedule "$chat_id" "$message_id" "$callback_id" ;;
        cfg_compress) cb_config_compress "$chat_id" "$message_id" "$callback_id" ;;
        cfg_remote) cb_config_remote "$chat_id" "$message_id" "$callback_id" ;;
        cmp_*) cb_compress_set "$chat_id" "$message_id" "$callback_id" "${data#cmp_}" ;;
        rmt_on) cb_remote_toggle "$chat_id" "$message_id" "$callback_id" "on" ;;
        rmt_off) cb_remote_toggle "$chat_id" "$message_id" "$callback_id" "off" ;;
        logs) cb_logs "$chat_id" "$message_id" "$callback_id" ;;
        log_backup) cb_log_view "$chat_id" "$message_id" "$callback_id" "backup" ;;
        log_restore) cb_log_view "$chat_id" "$message_id" "$callback_id" "restore" ;;
        log_bot) cb_log_view "$chat_id" "$message_id" "$callback_id" "bot" ;;
        test) cb_test "$chat_id" "$message_id" "$callback_id" ;;
        test_remote) cb_test_remote "$chat_id" "$message_id" "$callback_id" ;;
        test_tg) cb_test_telegram "$chat_id" "$message_id" "$callback_id" ;;
        *) answer_callback "$callback_id" "❌ 未知操作" ;;
    esac
}

# ===== 主循环 =====
main() {
    log "========== Bot 启动: $HOST =========="
    
    # 初始化 offset
    if [[ ! -f "$OFFSET_FILE" ]]; then
        log "[INIT] 初始化offset..."
        local last=$(curl -sS "${API}/getUpdates" 2>/dev/null | grep -o '"update_id":[0-9]*' | tail -1 | cut -d: -f2)
        echo $((${last:-0} + 1)) > "$OFFSET_FILE"
    fi
    
    # 主循环
    while true; do
        local offset=$(cat "$OFFSET_FILE" 2>/dev/null || echo 0)
        local response=$(curl -sS -m 30 "${API}/getUpdates?offset=$offset&timeout=25" 2>/dev/null)
        
        [[ -z "$response" ]] && sleep 1 && continue
        echo "$response" | grep -q '"ok":true' || { sleep 1; continue; }
        
        # 提取所有 update_id
        local update_ids=$(echo "$response" | grep -o '"update_id":[0-9]*' | cut -d: -f2)
        [[ -z "$update_ids" ]] && sleep 1 && continue
        
        # 处理每个更新
        while read -r uid; do
            [[ -z "$uid" ]] && continue
            
            # 提取当前更新的数据
            local update=$(echo "$response" | grep -A 100 "\"update_id\":$uid" | grep -B 100 "\"update_id\":" | head -n -1)
            
            # 处理文本消息
            if echo "$update" | grep -q '"message".*"text"'; then
                local cid=$(echo "$update" | grep -o '"chat":{"id":[0-9-]*' | grep -o '[0-9-]*$' | head -1)
                local txt=$(echo "$update" | grep -o '"text":"[^"]*"' | head -1 | cut -d'"' -f4)
                
                [[ -n "$cid" && -n "$txt" ]] && handle_text "$cid" "$txt"
            
            # 处理回调
            elif echo "$update" | grep -q '"callback_query"'; then
                local cid=$(echo "$update" | grep -o '"chat":{"id":[0-9-]*' | grep -o '[0-9-]*$' | head -1)
                local mid=$(echo "$update" | grep -o '"message_id":[0-9]*' | head -1 | cut -d: -f2)
                local cbid=$(echo "$update" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
                local data=$(echo "$update" | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4)
                
                [[ -n "$cid" && -n "$mid" && -n "$cbid" && -n "$data" ]] && route_callback "$cid" "$mid" "$cbid" "$data"
            fi
            
            # 更新 offset
            echo $((uid + 1)) > "$OFFSET_FILE"
        done <<< "$update_ids"
        
        sleep 0.3
    done
}

# ===== 启动检查 =====
if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
    log "[ERROR] TELEGRAM_BOT_TOKEN 未配置"
    exit 1
fi

if [[ -z "${TELEGRAM_CHAT_ID:-}" ]]; then
    log "[ERROR] TELEGRAM_CHAT_ID 未配置"
    exit 1
fi

# 启动
main
