#!/bin/bash

set -euo pipefail
IFS=$'\n\t'
umask 077

# SnapSync v3.0 - Telegram Bot（修复版）

CONFIG_FILE="/etc/snapsync/config.conf"
LOG_FILE="/var/log/snapsync/bot.log"
OFFSET_FILE="/var/run/snapsync_bot_offset"

[[ ! -f "$CONFIG_FILE" ]] && echo "配置文件不存在" && exit 1
source "$CONFIG_FILE" || exit 1

API="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"
HOST="${HOSTNAME:-$(hostname)}"
BACKUP_DIR="${BACKUP_DIR:-/backups}"

mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$OFFSET_FILE")"

BOT_STATE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/snapsync_XXXXXX")

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"; }

cleanup() {
    [[ -d "$BOT_STATE_DIR" ]] && rm -rf "$BOT_STATE_DIR" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

snapshot_state_file() {
    printf '%s/snapshots_%s.txt\n' "$BOT_STATE_DIR" "$1"
}

config_state_file() {
    printf '%s/config_%s.txt\n' "$BOT_STATE_DIR" "$1"
}

run_curl() {
    local had_xtrace=0
    if [[ $- == *x* ]]; then
        had_xtrace=1
        set +x
    fi

    curl -sS --fail --connect-timeout 10 --max-time 30 "$@"
    local rc=$?

    if (( had_xtrace )); then
        set -x
    fi

    return "$rc"
}

http_get() {
    run_curl "$@"
}

http_post() {
    run_curl -X POST "$@"
}

set_config_value() {
    local key="$1"
    local value="$2"
    local temp_file
    local escaped_value

    temp_file=$(mktemp "${BOT_STATE_DIR}/config_XXXXXX")
    printf -v escaped_value '%q' "$value"

    awk -v key="$key" -v value="$escaped_value" '
        BEGIN { updated = 0 }
        $0 ~ ("^" key "=") {
            print key "=" value
            updated = 1
            next
        }
        { print }
        END {
            if (!updated) {
                print key "=" value
            }
        }
    ' "$CONFIG_FILE" > "$temp_file"

    mv "$temp_file" "$CONFIG_FILE"
}

format_bytes() {
    local b="$1"
    if (( b >= 1073741824 )); then echo "$(awk "BEGIN {printf \"%.2f\", $b/1073741824}")GB"
    elif (( b >= 1048576 )); then echo "$(awk "BEGIN {printf \"%.2f\", $b/1048576}")MB"
    elif (( b >= 1024 )); then echo "$(awk "BEGIN {printf \"%.2f\", $b/1024}")KB"
    else echo "${b}B"; fi
}

send_msg() {
    local cid="$1" txt="$2" kb="${3:-}"
    local result
    result=$(http_post "${API}/sendMessage" -d "chat_id=$cid" \
        --data-urlencode "text=🖥️ <b>${HOST}</b>
━━━━━━━━━━━━━━━━━━━━━━━━━
$txt" -d "parse_mode=HTML" ${kb:+-d "reply_markup=$kb"} 2>&1 || true)
    log "发送消息: ${txt:0:30}... -> ${result:0:50}"
}

edit_msg() {
    local cid="$1" mid="$2" txt="$3" kb="${4:-}"
    local result
    result=$(http_post "${API}/editMessageText" \
        -d "chat_id=$cid" \
        -d "message_id=$mid" \
        --data-urlencode "text=🖥️ <b>${HOST}</b>
━━━━━━━━━━━━━━━━━━━━━━━━━
$txt" \
        -d "parse_mode=HTML" \
        ${kb:+-d "reply_markup=$kb"} 2>&1 || true)
    
    if echo "$result" | grep -q '"ok":false'; then
        log "编辑失败: ${result:0:100}"
    else
        log "编辑消息: $cid/$mid -> ${txt:0:30}..."
    fi
}

# 菜单定义
menu_main='{"inline_keyboard":[[{"text":"📊 系统状态","callback_data":"status"}],[{"text":"📋 快照列表","callback_data":"list"}],[{"text":"🔄 创建快照","callback_data":"backup"},{"text":"♻️ 恢复指南","callback_data":"restore"}],[{"text":"🗑️ 删除快照","callback_data":"delete"}],[{"text":"⚙️ 配置管理","callback_data":"config"}],[{"text":"📝 查看日志","callback_data":"logs"},{"text":"🔌 测试连接","callback_data":"test"}]]}'

menu_back='{"inline_keyboard":[[{"text":"🔙 返回主菜单","callback_data":"main"}]]}'

menu_config='{"inline_keyboard":[[{"text":"📦 快照保留策略","callback_data":"cfg_retention"}],[{"text":"⏰ 备份计划","callback_data":"cfg_schedule"}],[{"text":"🗜️ 压缩级别","callback_data":"cfg_compress"}],[{"text":"🌐 远程备份","callback_data":"cfg_remote"}],[{"text":"🔙 返回主菜单","callback_data":"main"}]]}'

menu_logs='{"inline_keyboard":[[{"text":"📘 备份日志","callback_data":"log_backup"}],[{"text":"📗 恢复日志","callback_data":"log_restore"}],[{"text":"📙 Bot日志","callback_data":"log_bot"}],[{"text":"🔙 返回主菜单","callback_data":"main"}]]}'

menu_test='{"inline_keyboard":[[{"text":"🌐 测试远程服务器","callback_data":"test_remote"}],[{"text":"📱 测试Telegram","callback_data":"test_tg"}],[{"text":"🔙 返回主菜单","callback_data":"main"}]]}'

menu_compress='{"inline_keyboard":[[{"text":"1️⃣ 最快","callback_data":"cmp_1"},{"text":"3️⃣ 快","callback_data":"cmp_3"},{"text":"6️⃣ 平衡","callback_data":"cmp_6"}],[{"text":"9️⃣ 最高压缩","callback_data":"cmp_9"}],[{"text":"🔙 返回配置","callback_data":"config"}]]}'

menu_remote='{"inline_keyboard":[[{"text":"✅ 启用","callback_data":"rmt_on"}],[{"text":"❌ 禁用","callback_data":"rmt_off"}],[{"text":"🔙 返回配置","callback_data":"config"}]]}'

# 命令处理
answer_cb() {
    http_post "${API}/answerCallbackQuery" \
        -d "callback_query_id=$1" \
        -d "text=${2:-OK}" &>/dev/null || true
}

cmd_start() {
    send_msg "$1" "🎯 <b>SnapSync 控制中心</b>

📦 版本: v3.0
🖥️ 主机: ${HOST}

<i>选择功能开始操作</i>" "$menu_main"
}

# 回调处理函数
cb_main() {
    answer_cb "$3"
    edit_msg "$1" "$2" "🎯 <b>SnapSync 控制中心</b>

📦 版本: v3.0
🖥️ 主机: ${HOST}

<i>选择功能开始操作</i>" "$menu_main"
}

cb_status() {
    answer_cb "$3"
    local up=$(uptime -p 2>/dev/null || echo "未知")
    local load=$(uptime | awk -F'load average:' '{print $2}' | xargs || echo "N/A")
    local cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 || echo "N/A")
    local mem=$(free | awk '/Mem:/ {printf "%.1f", $3/$2*100}' || echo "N/A")
    local disk=$(df -h "$BACKUP_DIR" 2>/dev/null | awk 'NR==2 {print $5}' || echo "N/A")
    local free=$(df -h "$BACKUP_DIR" 2>/dev/null | awk 'NR==2 {print $4}' || echo "N/A")
    local cnt=$(find "${BACKUP_DIR}/system_snapshots" -name "*.tar*" -type f 2>/dev/null | grep -cv sha256 || echo 0)
    local size=$(du -sh "${BACKUP_DIR}/system_snapshots" 2>/dev/null | awk '{print $1}' || echo "0B")
    
    edit_msg "$1" "$2" "📊 <b>系统状态</b>

<b>⚡ 系统运行</b>
🕐 运行时间: ${up}
📈 负载: ${load}
🔥 CPU: ${cpu}%
💾 内存: ${mem}%

<b>💿 磁盘状态</b>
📊 使用率: ${disk}
💽 可用: ${free}

<b>📦 备份状态</b>
📸 快照数量: ${cnt} 个
📁 占用空间: ${size}

<i>更新时间: $(date '+%H:%M:%S')</i>" "$menu_back"
}

cb_list() {
    answer_cb "$3"
    local dir="${BACKUP_DIR}/system_snapshots"
    [[ ! -d "$dir" ]] && edit_msg "$1" "$2" "📋 <b>快照列表</b>

❌ 快照目录不存在" "$menu_back" && return
    
    local snaps=()
    while IFS= read -r -d '' f; do
        [[ "$f" != *.sha256 ]] && snaps+=("$f")
    done < <(find "$dir" -name "*.tar*" -type f -print0 2>/dev/null | sort -zr)
    
    [[ ${#snaps[@]} -eq 0 ]] && edit_msg "$1" "$2" "📋 <b>快照列表</b>

❌ 暂无快照

<i>点击「创建快照」开始备份</i>" "$menu_back" && return
    
    local txt="📋 <b>快照列表</b>

找到 ${#snaps[@]} 个快照:
━━━━━━━━━━━━━━━━━━━━━━━━━

"
    local i=1
    for f in "${snaps[@]}"; do
        local n=$(basename "$f")
        local s=$(stat -c%s "$f" 2>/dev/null || echo 0)
        local sz=$(format_bytes "$s")
        local dt=$(date -r "$f" "+%m-%d %H:%M" 2>/dev/null || echo "未知")
        local ck="❌"; [[ -f "${f}.sha256" ]] && ck="✅"
        txt+="${i}. <b>${n}</b>
   📦 ${sz} | 📅 ${dt} | ${ck}

"
        ((i++))
        [[ $i -gt 15 ]] && txt+="<i>... 还有 $((${#snaps[@]} - 15)) 个未显示</i>

" && break
    done
    
    edit_msg "$1" "$2" "$txt" "$menu_back"
}

cb_backup() {
    answer_cb "$3"
    source "$CONFIG_FILE"
    local remote="no"
    [[ "$(echo ${REMOTE_ENABLED:-false} | tr A-Z a-z)" =~ ^(y|yes|true)$ ]] && remote="yes"
    
    if [[ "$remote" == "yes" ]]; then
        local kb='{"inline_keyboard":[[{"text":"✅ 创建并上传","callback_data":"backup_exec_upload"}],[{"text":"💾 仅本地备份","callback_data":"backup_exec_local"}],[{"text":"❌ 取消","callback_data":"main"}]]}'
        edit_msg "$1" "$2" "🔄 <b>创建快照</b>

⚠️ <b>注意事项</b>
- 备份需要 3-10 分钟
- 期间请勿关闭服务器
- 完成后会收到通知

🌐 <b>远程备份已启用</b>
是否上传到远程服务器？

💡 <i>上传会消耗额外时间和带宽</i>" "$kb"
    else
        local kb='{"inline_keyboard":[[{"text":"✅ 确认创建","callback_data":"backup_exec_local"}],[{"text":"❌ 取消","callback_data":"main"}]]}'
        edit_msg "$1" "$2" "🔄 <b>创建快照</b>

⚠️ <b>注意事项</b>
- 备份需要 3-10 分钟
- 期间请勿关闭服务器
- 完成后会收到通知

确认创建快照？" "$kb"
    fi
}

cb_backup_exec() {
    answer_cb "$3" "⏳ 开始创建快照..."
    edit_msg "$1" "$2" "🔄 <b>备份进行中</b>

⏳ 正在创建系统快照...
📦 压缩文件中...

<i>这可能需要几分钟，请稍候</i>

💡 备份完成后会自动通知您"
    
    (
        if [[ "$4" == "upload" ]]; then
            UPLOAD_REMOTE="yes" bash /opt/snapsync/modules/backup.sh &>/dev/null
        else
            UPLOAD_REMOTE="no" bash /opt/snapsync/modules/backup.sh &>/dev/null
        fi
    ) &
}

cb_restore() {
    answer_cb "$3"
    edit_msg "$1" "$2" "♻️ <b>系统恢复指南</b>

⚠️ <b>重要提示</b>
系统恢复需要在服务器上操作
Bot 无法直接执行恢复命令

<b>📝 恢复步骤</b>

1️⃣ SSH 登录服务器
<code>ssh root@${HOST}</code>

2️⃣ 启动恢复程序
<code>sudo snapsync-restore</code>

3️⃣ 按照提示操作
- 选择恢复来源（本地/远程）
- 选择快照文件
- 选择恢复模式（智能/完全）
- 确认并执行

4️⃣ 恢复完成后重启
<code>sudo reboot</code>

💡 <b>建议</b>
- 使用「智能恢复」模式保留网络配置
- 恢复前备份重要数据
- 测试环境先验证" "$menu_back"
}

cb_delete() {
    answer_cb "$3"
    local dir="${BACKUP_DIR}/system_snapshots"
    
    # 检查目录是否存在
    if [[ ! -d "$dir" ]]; then
        edit_msg "$1" "$2" "🗑️ <b>删除快照</b>

❌ 快照目录不存在" "$menu_back"
        log "删除失败: 快照目录不存在 $dir"
        return
    fi
    
    # 收集快照文件
    local snaps=()
    while IFS= read -r -d '' f; do
        [[ "$f" != *.sha256 ]] && snaps+=("$f")
    done < <(find "$dir" -name "*.tar*" -type f -print0 2>/dev/null | sort -zr)
    
    # 检查是否有快照
    if [[ ${#snaps[@]} -eq 0 ]]; then
        edit_msg "$1" "$2" "🗑️ <b>删除快照</b>

❌ 暂无可删除的快照

<i>点击「创建快照」开始备份</i>" "$menu_back"
        log "删除失败: 无可用快照"
        return
    fi
    
    # 保存快照列表到临时文件
    local temp_file
    temp_file=$(snapshot_state_file "$1")
    printf "%s\n" "${snaps[@]}" > "$temp_file"
    log "快照列表已保存: $temp_file (${#snaps[@]} 个)"
    
    # 构建键盘按钮
    local buttons=()
    local i=0
    for f in "${snaps[@]}"; do
        [[ $i -ge 10 ]] && break
        
        local n=$(basename "$f")
        # 安全截取文件名（从 system_snapshot_ 之后开始）
        local display_name=""
        if [[ "$n" =~ ^system_snapshot_([0-9]{14}) ]]; then
            # 格式: YYYYMMDDHHMMSS
            local ts="${BASH_REMATCH[1]}"
            local year="${ts:0:4}"
            local month="${ts:4:2}"
            local day="${ts:6:2}"
            local hour="${ts:8:2}"
            local min="${ts:10:2}"
            display_name="${month}-${day} ${hour}:${min}"
        else
            # 如果不符合预期格式，取前20个字符
            display_name="${n:0:20}"
        fi
        
        # 转义特殊字符（防止破坏 JSON）
        display_name=$(echo "$display_name" | sed 's/"/\\"/g')
        
        # 添加按钮（每个按钮单独一行）
        buttons+=("[{\"text\":\"$((i+1)). ${display_name}\",\"callback_data\":\"del_${i}\"}]")
        ((i++))
    done
    
    # 构建完整的 inline keyboard JSON
    local keyboard_json="{\"inline_keyboard\":["
    
    # 添加快照按钮
    for btn in "${buttons[@]}"; do
        keyboard_json+="${btn},"
    done
    
    # 添加返回按钮
    keyboard_json+="[{\"text\":\"🔙 返回主菜单\",\"callback_data\":\"main\"}]"
    keyboard_json+="]}"
    
    log "键盘JSON已构建，包含 ${#buttons[@]} 个快照按钮"
    
    # 发送消息
    edit_msg "$1" "$2" "🗑️ <b>删除快照</b>

找到 ${#snaps[@]} 个快照
请选择要删除的快照:

⚠️ <b>删除后无法恢复</b>
显示前 ${#buttons[@]} 个，完整列表见「快照列表」" "$keyboard_json"
}

cb_delete_confirm() {
    answer_cb "$3"
    
    # 读取快照列表
    local temp_file
    temp_file=$(snapshot_state_file "$1")
    if [[ ! -f "$temp_file" ]]; then
        edit_msg "$1" "$2" "❌ <b>错误</b>

快照列表已过期
请重新选择" "$menu_back"
        log "删除确认失败: 临时文件不存在"
        return
    fi
    
    local snaps=()
    while IFS= read -r line; do
        snaps+=("$line")
    done < "$temp_file"
    
    # 验证索引
    local idx="$4"
    if [[ ! "$idx" =~ ^[0-9]+$ ]] || [[ $idx -ge ${#snaps[@]} ]]; then
        edit_msg "$1" "$2" "❌ <b>错误</b>

快照索引无效
请重新选择" "$menu_back"
        log "删除确认失败: 无效索引 $idx"
        return
    fi
    
    local f="${snaps[$idx]}"
    
    # 检查文件是否存在
    if [[ ! -f "$f" ]]; then
        edit_msg "$1" "$2" "❌ <b>错误</b>

快照文件不存在
可能已被删除" "$menu_back"
        log "删除确认失败: 文件不存在 $f"
        return
    fi
    
    local n=$(basename "$f")
    local s=$(stat -c%s "$f" 2>/dev/null || echo 0)
    local sz=$(format_bytes "$s")
    local dt=$(date -r "$f" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "未知")
    
    # 构建确认键盘
    local confirm_kb="{\"inline_keyboard\":[[{\"text\":\"✅ 确认删除\",\"callback_data\":\"delx_${idx}\"}],[{\"text\":\"❌ 取消\",\"callback_data\":\"delete\"}]]}"
    
    edit_msg "$1" "$2" "🗑️ <b>确认删除</b>

📸 快照: <code>${n}</code>
📦 大小: ${sz}
📅 时间: ${dt}

⚠️ <b>此操作不可撤销！</b>

确认删除此快照？" "$confirm_kb"
    
    log "显示删除确认: $n"
}

cb_delete_exec() {
    answer_cb "$3" "🗑️ 正在删除..."
    
    # 读取快照列表
    local temp_file
    temp_file=$(snapshot_state_file "$1")
    if [[ ! -f "$temp_file" ]]; then
        edit_msg "$1" "$2" "❌ <b>删除失败</b>

快照列表已过期" "$menu_back"
        log "删除执行失败: 临时文件不存在"
        return
    fi
    
    local snaps=()
    while IFS= read -r line; do
        snaps+=("$line")
    done < "$temp_file"
    
    # 验证索引
    local idx="$4"
    if [[ ! "$idx" =~ ^[0-9]+$ ]] || [[ $idx -ge ${#snaps[@]} ]]; then
        edit_msg "$1" "$2" "❌ <b>删除失败</b>

快照索引无效" "$menu_back"
        log "删除执行失败: 无效索引 $idx"
        rm -f "$temp_file"
        return
    fi
    
    local f="${snaps[$idx]}"
    local n=$(basename "$f")
    
    # 执行删除
    log "准备删除快照: $f"
    
    if [[ ! -f "$f" ]]; then
        edit_msg "$1" "$2" "❌ <b>删除失败</b>

📸 ${n}

文件不存在，可能已被删除" "$menu_back"
        log "删除执行失败: 文件不存在 $f"
        rm -f "$temp_file"
        return
    fi
    
    # 删除快照文件和校验文件
    if rm -f "$f" "${f}.sha256" 2>/dev/null; then
        edit_msg "$1" "$2" "✅ <b>删除成功</b>

📸 ${n}

快照已从系统中移除

<i>$(date '+%Y-%m-%d %H:%M:%S')</i>" "$menu_back"
        log "快照已删除: $n"
    else
        edit_msg "$1" "$2" "❌ <b>删除失败</b>

📸 ${n}

删除操作失败，可能是权限不足

<i>请检查文件权限和磁盘状态</i>" "$menu_back"
        log "删除执行失败: rm 命令失败 $f"
    fi
    
    # 清理临时文件
    rm -f "$temp_file"
}

cb_config() {
    answer_cb "$3"
    source "$CONFIG_FILE"
    edit_msg "$1" "$2" "⚙️ <b>配置管理</b>

📦 本地保留: ${LOCAL_KEEP_COUNT:-5} 个
🌐 远程保留: ${REMOTE_KEEP_DAYS:-30} 天
⏰ 备份间隔: ${BACKUP_INTERVAL_DAYS:-7} 天
🕐 备份时间: ${BACKUP_TIME:-03:00}
🗜️ 压缩级别: ${COMPRESSION_LEVEL:-6}
🌐 远程备份: ${REMOTE_ENABLED:-false}

<i>点击下方选项修改配置</i>" "$menu_config"
}

cb_config_retention() {
    answer_cb "$3"
    source "$CONFIG_FILE"
    edit_msg "$1" "$2" "📦 <b>快照保留策略</b>

当前配置:
- 本地保留: ${LOCAL_KEEP_COUNT:-5} 个
- 远程保留: ${REMOTE_KEEP_DAYS:-30} 天

<b>修改方法</b>
发送格式: <code>本地数量 远程天数</code>

示例:
<code>10 60</code> - 本地保留10个，远程保留60天

<i>发送配置或返回</i>" "$menu_back"
    printf '%s\n' "cfg_retention" > "$(config_state_file "$1")"
}

cb_config_schedule() {
    answer_cb "$3"
    source "$CONFIG_FILE"
    edit_msg "$1" "$2" "⏰ <b>备份计划</b>

当前配置:
- 备份间隔: ${BACKUP_INTERVAL_DAYS:-7} 天
- 备份时间: ${BACKUP_TIME:-03:00}

<b>修改方法</b>
发送格式: <code>间隔天数 时间</code>

示例:
<code>7 03:00</code> - 每7天凌晨3点

<i>发送配置或返回</i>" "$menu_back"
    printf '%s\n' "cfg_schedule" > "$(config_state_file "$1")"
}

cb_config_compress() {
    answer_cb "$3"
    source "$CONFIG_FILE"
    edit_msg "$1" "$2" "🗜️ <b>压缩级别</b>

当前: ${COMPRESSION_LEVEL:-6}

<b>级别说明</b>
1️⃣ 最快 - 速度快，压缩率低
3️⃣ 快速 - 平衡速度和压缩率
6️⃣ 平衡 - 推荐，性能最优
9️⃣ 最高 - 压缩率最高，速度慢

<i>选择压缩级别</i>" "$menu_compress"
}

cb_config_remote() {
    answer_cb "$3"
    source "$CONFIG_FILE"
    local st="❌ 禁用"
    [[ "$(echo ${REMOTE_ENABLED:-false} | tr A-Z a-z)" =~ ^(y|yes|true)$ ]] && st="✅ 启用"
    
    edit_msg "$1" "$2" "🌐 <b>远程备份</b>

当前状态: ${st}

服务器: ${REMOTE_HOST:-未配置}
用户: ${REMOTE_USER:-root}
端口: ${REMOTE_PORT:-22}

<b>注意</b>
启用前请确保已配置SSH密钥

<i>选择操作</i>" "$menu_remote"
}

cb_compress_set() {
    answer_cb "$3" "✅ 压缩级别已设置为 $4"
    set_config_value "COMPRESSION_LEVEL" "$4"
    cb_config "$1" "$2" "$3"
    log "压缩级别设置为: $4"
}

cb_remote_toggle() {
    local v="false" st="禁用"
    [[ "$4" == "on" ]] && v="true" && st="启用"
    answer_cb "$3" "✅ 远程备份已${st}"
    set_config_value "REMOTE_ENABLED" "$v"
    cb_config "$1" "$2" "$3"
    log "远程备份: $v"
}

cb_logs() {
    answer_cb "$3"
    edit_msg "$1" "$2" "📝 <b>查看日志</b>

选择要查看的日志:

📘 备份日志 - 快照创建记录
📗 恢复日志 - 系统恢复记录  
📙 Bot日志 - Bot运行记录

<i>显示最近50行</i>" "$menu_logs"
}

cb_log_view() {
    answer_cb "$3"
    local lf="" ti=""
    case "$4" in
        backup) lf="/var/log/snapsync/backup.log"; ti="📘 备份日志" ;;
        restore) lf="/var/log/snapsync/restore.log"; ti="📗 恢复日志" ;;
        bot) lf="/var/log/snapsync/bot.log"; ti="📙 Bot日志" ;;
    esac
    
    [[ ! -f "$lf" ]] && edit_msg "$1" "$2" "${ti}

❌ 日志文件不存在" "$menu_back" && return
    
    local log=$(tail -50 "$lf" | sed 's/</\&lt;/g; s/>/\&gt;/g')
    [[ ${#log} -gt 3000 ]] && log="${log: -3000}"
    
    edit_msg "$1" "$2" "${ti}

<code>${log}</code>

<i>最近50行</i>" "$menu_back"
}

cb_test() {
    answer_cb "$3"
    edit_msg "$1" "$2" "🔌 <b>连接测试</b>

选择要测试的连接:

🌐 远程服务器 - SSH连接测试
📱 Telegram - API连接测试

<i>测试可能需要几秒钟</i>" "$menu_test"
}

cb_test_remote() {
    answer_cb "$3" "⏳ 测试中..."
    source "$CONFIG_FILE"
    
    [[ -z "${REMOTE_HOST:-}" ]] && edit_msg "$1" "$2" "🌐 <b>远程服务器测试</b>

❌ 未配置远程服务器" "$menu_back" && return
    
    local key="/root/.ssh/id_ed25519"
    local res=""
    
    if [[ ! -f "$key" ]]; then
        res="❌ SSH密钥不存在"
    elif ssh -i "$key" -p "${REMOTE_PORT}" -o StrictHostKeyChecking=no \
              -o ConnectTimeout=10 -o BatchMode=yes \
              "${REMOTE_USER}@${REMOTE_HOST}" "echo ok" &>/dev/null; then
        res="✅ 连接成功

SSH密钥验证通过
远程服务器正常响应"
    else
        res="❌ 连接失败

可能原因:
- SSH密钥未添加到远程服务器
- 远程服务器不可达
- 防火墙阻止连接"
    fi
    
    edit_msg "$1" "$2" "🌐 <b>远程服务器测试</b>

服务器: ${REMOTE_HOST}
用户: ${REMOTE_USER}
端口: ${REMOTE_PORT}

$res" "$menu_back"
}

cb_test_tg() {
    answer_cb "$3" "⏳ 测试中..."
    local test
    test=$(http_get --max-time 10 "${API}/getMe" 2>&1 || true)
    local res=""
    
    if echo "$test" | grep -q '"ok":true'; then
        local un=$(echo "$test" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
        res="✅ Telegram API 正常

Bot用户名: @${un}
连接状态: 正常

如果你看到这条消息，说明配置正确"
    else
        res="❌ API测试失败

可能原因:
- Bot Token 错误
- 网络无法访问Telegram"
    fi
    
    edit_msg "$1" "$2" "📱 <b>Telegram 测试</b>

$res" "$menu_back"
}

# 文本处理
handle_text() {
    local cid="$1" txt="$2"
    
    [[ "$txt" == "/start" ]] && rm -f "$(config_state_file "$cid")" && cmd_start "$cid" && return
    
    local mode
    mode=$(cat "$(config_state_file "$cid")" 2>/dev/null || echo "")
    [[ -z "$mode" ]] && send_msg "$cid" "❓ 未知命令

发送 /start 打开主菜单" "$menu_main" && return
    
    case "$mode" in
        cfg_retention)
            if [[ "$txt" =~ ^([0-9]+)\ +([0-9]+)$ ]]; then
                local lk="${BASH_REMATCH[1]}" rk="${BASH_REMATCH[2]}"
                set_config_value "LOCAL_KEEP_COUNT" "$lk"
                set_config_value "REMOTE_KEEP_DAYS" "$rk"
                send_msg "$cid" "✅ <b>保留策略已更新</b>

📦 本地保留: ${lk} 个
🌐 远程保留: ${rk} 天" "$menu_main"
                rm -f "$(config_state_file "$cid")"
                log "保留策略: local=$lk, remote=$rk"
            else
                send_msg "$cid" "❌ <b>格式错误</b>

请使用: <code>本地数量 远程天数</code>
示例: <code>10 60</code>" "$menu_back"
            fi
            ;;
        cfg_schedule)
            if [[ "$txt" =~ ^([0-9]+)\ +([0-9]{2}:[0-9]{2})$ ]]; then
                local iv="${BASH_REMATCH[1]}" tm="${BASH_REMATCH[2]}"
                set_config_value "BACKUP_INTERVAL_DAYS" "$iv"
                set_config_value "BACKUP_TIME" "$tm"
                send_msg "$cid" "✅ <b>备份计划已更新</b>

⏰ 间隔: 每 ${iv} 天
🕐 时间: ${tm}

<i>需重启定时器生效</i>
<code>systemctl restart snapsync-backup.timer</code>" "$menu_main"
                rm -f "$(config_state_file "$cid")"
                log "备份计划: interval=$iv, time=$tm"
            else
                send_msg "$cid" "❌ <b>格式错误</b>

请使用: <code>间隔天数 时间</code>
示例: <code>7 03:00</code>" "$menu_back"
            fi
            ;;
    esac
}

# 路由
route() {
    local cid="$1" mid="$2" cbid="$3" data="$4"
    log "回调: $data from $cid/$mid"
    
    case "$data" in
        main) cb_main "$cid" "$mid" "$cbid" ;;
        status) cb_status "$cid" "$mid" "$cbid" ;;
        list) cb_list "$cid" "$mid" "$cbid" ;;
        backup) cb_backup "$cid" "$mid" "$cbid" ;;
        backup_exec_local) cb_backup_exec "$cid" "$mid" "$cbid" "local" ;;
        backup_exec_upload) cb_backup_exec "$cid" "$mid" "$cbid" "upload" ;;
        restore) cb_restore "$cid" "$mid" "$cbid" ;;
        delete) cb_delete "$cid" "$mid" "$cbid" ;;
        del_*) cb_delete_confirm "$cid" "$mid" "$cbid" "${data#del_}" ;;
        delx_*) cb_delete_exec "$cid" "$mid" "$cbid" "${data#delx_}" ;;
        config) cb_config "$cid" "$mid" "$cbid" ;;
        cfg_retention) cb_config_retention "$cid" "$mid" "$cbid" ;;
        cfg_schedule) cb_config_schedule "$cid" "$mid" "$cbid" ;;
        cfg_compress) cb_config_compress "$cid" "$mid" "$cbid" ;;
        cfg_remote) cb_config_remote "$cid" "$mid" "$cbid" ;;
        cmp_*) cb_compress_set "$cid" "$mid" "$cbid" "${data#cmp_}" ;;
        rmt_on) cb_remote_toggle "$cid" "$mid" "$cbid" "on" ;;
        rmt_off) cb_remote_toggle "$cid" "$mid" "$cbid" "off" ;;
        logs) cb_logs "$cid" "$mid" "$cbid" ;;
        log_backup) cb_log_view "$cid" "$mid" "$cbid" "backup" ;;
        log_restore) cb_log_view "$cid" "$mid" "$cbid" "restore" ;;
        log_bot) cb_log_view "$cid" "$mid" "$cbid" "bot" ;;
        test) cb_test "$cid" "$mid" "$cbid" ;;
        test_remote) cb_test_remote "$cid" "$mid" "$cbid" ;;
        test_tg) cb_test_tg "$cid" "$mid" "$cbid" ;;
    esac
}

# 主循环
log "Bot 启动: $HOST"
[[ ! -f "$OFFSET_FILE" ]] && echo 0 > "$OFFSET_FILE"

while true; do
    offset=$(cat "$OFFSET_FILE")
    resp=$(http_get --max-time 25 "${API}/getUpdates?offset=$offset&timeout=20" 2>/dev/null || echo "")
    
    [[ -z "$resp" ]] && sleep 1 && continue
    echo "$resp" | grep -q '"ok":true' || continue
    
    # 优先处理回调（避免同时处理文本和回调）
    if echo "$resp" | grep -q '"callback_query"'; then
        cid=$(echo "$resp" | grep -o '"chat":{"id":[0-9-]*' | grep -o '[0-9-]*' | head -1)
        mid=$(echo "$resp" | grep -o '"message_id":[0-9]*' | head -1 | cut -d: -f2)
        cbid=$(echo "$resp" | grep -o '"callback_query":{"id":"[^"]*"' | cut -d'"' -f4)
        data=$(echo "$resp" | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4)
        [[ -n "$cid" && -n "$mid" && -n "$cbid" && -n "$data" ]] && route "$cid" "$mid" "$cbid" "$data"
    # 只有不是回调时才处理文本消息
    elif echo "$resp" | grep -q '"message".*"text"'; then
        cid=$(echo "$resp" | grep -o '"chat":{"id":[0-9-]*' | grep -o '[0-9-]*' | head -1)
        txt=$(echo "$resp" | grep -o '"text":"[^"]*"' | head -1 | cut -d'"' -f4)
        [[ -n "$cid" && -n "$txt" ]] && handle_text "$cid" "$txt"
    fi
    
    # 更新offset
    last=$(echo "$resp" | grep -o '"update_id":[0-9]*' | tail -1 | cut -d: -f2)
    [[ -n "$last" ]] && echo $((last + 1)) > "$OFFSET_FILE"
    
    sleep 0.5
done
