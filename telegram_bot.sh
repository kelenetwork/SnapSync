#!/bin/bash

# SnapSync v3.0 - Telegram Bot（终极修复版）
# 修复：offset 持久化 + 配置编辑

set -euo pipefail

# ===== 配置 =====
CONFIG_FILE="/etc/snapsync/config.conf"
LOG_FILE="/var/log/snapsync/bot.log"
OFFSET_FILE="/var/run/snapsync_bot_offset"

[[ ! -f "$CONFIG_FILE" ]] && echo "[ERROR] 配置不存在" >> "$LOG_FILE" && exit 1
source "$CONFIG_FILE" || exit 1

# ===== 变量 =====
API="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"
HOST="${HOSTNAME:-$(hostname)}"

mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$OFFSET_FILE")"

# ===== 日志 =====
log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"; }

# ===== API =====
call() {
    curl -sS -m 10 -X POST "${API}/$1" "${@:2}" 2>/dev/null
}

send() {
    call sendMessage -d "chat_id=$1" --data-urlencode "text=🖥️ <b>${HOST}</b>
━━━━━━━━━━━━━━━━━━━━━━━
$2" -d "parse_mode=HTML" ${3:+-d "reply_markup=$3"}
}

edit() {
    call editMessageText -d "chat_id=$1" -d "message_id=$2" --data-urlencode "text=🖥️ <b>${HOST}</b>
━━━━━━━━━━━━━━━━━━━━━━━
$3" -d "parse_mode=HTML" ${4:+-d "reply_markup=$4"}
}

answer() { call answerCallbackQuery -d "callback_query_id=$1" -d "text=${2:-OK}" >/dev/null; }

# ===== 菜单 =====
menu_main() { echo '{"inline_keyboard":[[{"text":"📊 状态","callback_data":"st"}],[{"text":"📋 列表","callback_data":"ls"}],[{"text":"🔄 备份","callback_data":"bk"}],[{"text":"🗑️ 删除","callback_data":"dl"}],[{"text":"⚙️ 配置","callback_data":"cf"}],[{"text":"✏️ 编辑配置","callback_data":"ed"}],[{"text":"❓ 帮助","callback_data":"hp"}]]}'; }
menu_back() { echo '{"inline_keyboard":[[{"text":"🔙 返回","callback_data":"mn"}]]}'; }
menu_edit() { echo '{"inline_keyboard":[[{"text":"📡 远程服务器","callback_data":"edr"}],[{"text":"📱 Telegram","callback_data":"edt"}],[{"text":"💾 保留策略","callback_data":"edp"}],[{"text":"🔙 返回","callback_data":"mn"}]]}'; }

# ===== 命令 =====
cmd_start() {
    log "[START] $1"
    send "$1" "👋 <b>欢迎使用 SnapSync</b>

📦 v3.0 | 💡 点击按钮" "$(menu_main)"
}

# ===== 回调 =====
cb_mn() { answer "$3"; edit "$1" "$2" "📱 <b>主菜单</b>" "$(menu_main)"; }

cb_st() {
    answer "$3"
    local up=$(uptime -p 2>/dev/null || echo "?")
    local ld=$(uptime | awk -F'load' '{print $2}' | awk '{print $1}' | tr -d ':,')
    local ct=$(find "${BACKUP_DIR}/system_snapshots" -name "*.tar*" -type f 2>/dev/null | grep -cv sha256 || echo 0)
    local dk=$(df -h "${BACKUP_DIR}" 2>/dev/null | awk 'NR==2{print $5}')
    edit "$1" "$2" "📊 <b>系统状态</b>

⏱️ ${up}
📈 负载: ${ld}
💾 磁盘: ${dk}
📦 快照: ${ct}个" "$(menu_back)"
}

cb_ls() {
    answer "$3"
    local files=$(find "${BACKUP_DIR}/system_snapshots" -name "*.tar*" -type f 2>/dev/null | grep -v sha256 | sort -r)
    [[ -z "$files" ]] && { edit "$1" "$2" "📋 <b>快照列表</b>

暂无快照" "$(menu_back)"; return; }
    
    local txt="📋 <b>快照列表</b>

"
    local i=0
    while IFS= read -r f; do
        ((i++)); [[ $i -gt 5 ]] && break
        local n=$(basename "$f")
        local s=$(stat -c%s "$f" 2>/dev/null || echo 0)
        [[ $s -ge 1073741824 ]] && s="$(awk "BEGIN{printf \"%.1f\",$s/1073741824}")G" || s="$(awk "BEGIN{printf \"%.0f\",$s/1048576}")M"
        txt+="${i}. ${n:17:14}... ($s)
"
    done <<< "$files"
    edit "$1" "$2" "$txt" "$(menu_back)"
}

cb_bk() {
    answer "$3"
    edit "$1" "$2" "🔄 <b>创建快照</b>

即将创建系统备份
⚠️ 需要几分钟

继续?" '{"inline_keyboard":[[{"text":"✅ 确认","callback_data":"bkc"}],[{"text":"❌ 取消","callback_data":"mn"}]}'
}

cb_bkc() {
    answer "$3"
    edit "$1" "$2" "🔄 <b>备份中...</b>

⏳ 创建快照
请稍候..."
    (bash /opt/snapsync/modules/backup.sh &>/dev/null || log "[ERROR] 备份失败") &
}

cb_dl() {
    answer "$3"
    local files=$(find "${BACKUP_DIR}/system_snapshots" -name "*.tar*" -type f 2>/dev/null | grep -v sha256 | sort -r)
    [[ -z "$files" ]] && { edit "$1" "$2" "🗑️ <b>删除</b>

无快照" "$(menu_back)"; return; }
    
    echo "$files" > "/tmp/del_$1.txt"
    local btns='['
    local i=0
    while IFS= read -r f; do
        [[ $i -ge 5 ]] && break
        local n=$(basename "$f")
        btns+="{\"text\":\"$((i+1)). ${n:17:14}\",\"callback_data\":\"dx${i}\"},"
        ((i++))
    done <<< "$files"
    btns="${btns%,}]"
    
    edit "$1" "$2" "🗑️ <b>删除快照</b>

找到 $i 个
选择:" "{\"inline_keyboard\":[$btns,[{\"text\":\"🔙 返回\",\"callback_data\":\"mn\"}]]}"
}

cb_dx() {
    local idx="$4"
    answer "$3"
    local files=($(cat "/tmp/del_$1.txt" 2>/dev/null))
    local f="${files[$idx]}"
    local n=$(basename "$f")
    edit "$1" "$2" "🗑️ <b>确认删除</b>

📸 ${n}

⚠️ 不可撤销" "{\"inline_keyboard\":[[{\"text\":\"✅ 确认\",\"callback_data\":\"dk${idx}\"}],[{\"text\":\"❌ 取消\",\"callback_data\":\"dl\"}]]}"
}

cb_dk() {
    local idx="$4"
    answer "$3"
    local files=($(cat "/tmp/del_$1.txt" 2>/dev/null))
    local f="${files[$idx]}"
    local n=$(basename "$f")
    if rm -f "$f" "$f.sha256" 2>/dev/null; then
        edit "$1" "$2" "✅ <b>删除成功</b>

📸 ${n}" "$(menu_back)"
    else
        edit "$1" "$2" "❌ <b>删除失败</b>

📸 ${n}" "$(menu_back)"
    fi
}

cb_cf() {
    answer "$3"
    local tg="❌"; [[ "$(echo ${TELEGRAM_ENABLED:-false} | tr A-Z a-z)" =~ ^(y|yes|true)$ ]] && tg="✅"
    local rm="❌"; [[ "$(echo ${REMOTE_ENABLED:-false} | tr A-Z a-z)" =~ ^(y|yes|true)$ ]] && rm="✅"
    edit "$1" "$2" "⚙️ <b>配置</b>

<b>本地:</b>
📂 ${BACKUP_DIR}
💾 保留 ${LOCAL_KEEP_COUNT} 个

<b>远程:</b> ${rm}
🌐 ${REMOTE_HOST:-未配置}

<b>Telegram:</b> ${tg}

主控制台修改配置" "$(menu_back)"
}

cb_ed() {
    answer "$3"
    edit "$1" "$2" "✏️ <b>编辑配置</b>

选择要编辑的项目:" "$(menu_edit)"
}

cb_edr() {
    answer "$3"
    edit "$1" "$2" "📡 <b>远程服务器</b>

当前配置:
🌐 服务器: ${REMOTE_HOST:-未配置}
👤 用户: ${REMOTE_USER:-root}
🔌 端口: ${REMOTE_PORT:-22}

发送格式:
<code>服务器地址 用户 端口</code>

示例:
<code>192.168.1.100 root 22</code>

发送配置或点返回:" "$(menu_back)"
    echo "edr" > "/tmp/edit_$1.txt"
}

cb_edt() {
    answer "$3"
    edit "$1" "$2" "📱 <b>Telegram配置</b>

当前状态: ${TELEGRAM_ENABLED:-false}

发送以下之一:
<code>true</code> - 启用
<code>false</code> - 禁用

或点返回:" "$(menu_back)"
    echo "edt" > "/tmp/edit_$1.txt"
}

cb_edp() {
    answer "$3"
    edit "$1" "$2" "💾 <b>保留策略</b>

当前:
本地: ${LOCAL_KEEP_COUNT:-5} 个
远程: ${REMOTE_KEEP_DAYS:-30} 天

发送格式:
<code>本地数量 远程天数</code>

示例:
<code>10 60</code>

发送配置或点返回:" "$(menu_back)"
    echo "edp" > "/tmp/edit_$1.txt"
}

cb_hp() {
    answer "$3"
    edit "$1" "$2" "❓ <b>帮助</b>

📊 状态 - 查看系统
📋 列表 - 所有快照
🔄 备份 - 创建快照
🗑️ 删除 - 删除快照
⚙️ 配置 - 查看配置
✏️ 编辑 - 修改配置

控制台: <code>sudo snapsync</code>" "$(menu_back)"
}

# ===== 处理文本（配置编辑）=====
handle_text() {
    local cid="$1"
    local txt="$2"
    local mode=$(cat "/tmp/edit_$cid.txt" 2>/dev/null)
    
    if [[ -z "$mode" ]]; then
        cmd_start "$cid"
        return
    fi
    
    case "$mode" in
        edr)
            if [[ "$txt" =~ ^([^ ]+)\ +([^ ]+)\ +([0-9]+)$ ]]; then
                local host="${BASH_REMATCH[1]}"
                local user="${BASH_REMATCH[2]}"
                local port="${BASH_REMATCH[3]}"
                
                sed -i "s|^REMOTE_HOST=.*|REMOTE_HOST=\"$host\"|" "$CONFIG_FILE"
                sed -i "s|^REMOTE_USER=.*|REMOTE_USER=\"$user\"|" "$CONFIG_FILE"
                sed -i "s|^REMOTE_PORT=.*|REMOTE_PORT=\"$port\"|" "$CONFIG_FILE"
                sed -i "s|^REMOTE_ENABLED=.*|REMOTE_ENABLED=\"true\"|" "$CONFIG_FILE"
                
                send "$cid" "✅ <b>远程配置已更新</b>

🌐 ${host}
👤 ${user}
🔌 ${port}

记得添加SSH密钥到远程服务器" "$(menu_main)"
                rm -f "/tmp/edit_$cid.txt"
            else
                send "$cid" "❌ <b>格式错误</b>

请使用:
<code>IP地址 用户 端口</code>

示例:
<code>192.168.1.100 root 22</code>" "$(menu_back)"
            fi
            ;;
        edt)
            if [[ "$txt" =~ ^(true|false|y|n|yes|no)$ ]]; then
                local val="false"
                [[ "$txt" =~ ^(true|y|yes)$ ]] && val="true"
                
                sed -i "s|^TELEGRAM_ENABLED=.*|TELEGRAM_ENABLED=\"$val\"|" "$CONFIG_FILE"
                
                send "$cid" "✅ <b>Telegram配置已更新</b>

状态: $val" "$(menu_main)"
                rm -f "/tmp/edit_$cid.txt"
            else
                send "$cid" "❌ <b>无效输入</b>

请发送: true 或 false" "$(menu_back)"
            fi
            ;;
        edp)
            if [[ "$txt" =~ ^([0-9]+)\ +([0-9]+)$ ]]; then
                local local_keep="${BASH_REMATCH[1]}"
                local remote_keep="${BASH_REMATCH[2]}"
                
                sed -i "s|^LOCAL_KEEP_COUNT=.*|LOCAL_KEEP_COUNT=\"$local_keep\"|" "$CONFIG_FILE"
                sed -i "s|^REMOTE_KEEP_DAYS=.*|REMOTE_KEEP_DAYS=\"$remote_keep\"|" "$CONFIG_FILE"
                
                send "$cid" "✅ <b>保留策略已更新</b>

本地: ${local_keep} 个
远程: ${remote_keep} 天" "$(menu_main)"
                rm -f "/tmp/edit_$cid.txt"
            else
                send "$cid" "❌ <b>格式错误</b>

请使用:
<code>本地数量 远程天数</code>

示例:
<code>10 60</code>" "$(menu_back)"
            fi
            ;;
    esac
}

# ===== 路由 =====
route() {
    local cid="$1" mid="$2" cbid="$3" data="$4"
    log "[CB] $data"
    case "$data" in
        mn) cb_mn "$cid" "$mid" "$cbid" ;;
        st) cb_st "$cid" "$mid" "$cbid" ;;
        ls) cb_ls "$cid" "$mid" "$cbid" ;;
        bk) cb_bk "$cid" "$mid" "$cbid" ;;
        bkc) cb_bkc "$cid" "$mid" "$cbid" ;;
        dl) cb_dl "$cid" "$mid" "$cbid" ;;
        dx*) cb_dx "$cid" "$mid" "$cbid" "${data#dx}" ;;
        dk*) cb_dk "$cid" "$mid" "$cbid" "${data#dk}" ;;
        cf) cb_cf "$cid" "$mid" "$cbid" ;;
        ed) cb_ed "$cid" "$mid" "$cbid" ;;
        edr) cb_edr "$cid" "$mid" "$cbid" ;;
        edt) cb_edt "$cid" "$mid" "$cbid" ;;
        edp) cb_edp "$cid" "$mid" "$cbid" ;;
        hp) cb_hp "$cid" "$mid" "$cbid" ;;
        *) answer "$cbid" "未知" ;;
    esac
}

# ===== 主循环 =====
main() {
    log "========== Bot 启动: $HOST =========="
    
    # 首次运行清空旧更新
    if [[ ! -f "$OFFSET_FILE" ]]; then
        log "[INIT] 清空旧更新..."
        local last=$(curl -sS "${API}/getUpdates" | grep -o '"update_id":[0-9]*' | tail -1 | cut -d: -f2)
        [[ -n "$last" ]] && echo $((last + 1)) > "$OFFSET_FILE" || echo 0 > "$OFFSET_FILE"
    fi
    
    while true; do
        local offset=$(cat "$OFFSET_FILE" 2>/dev/null || echo 0)
        local resp=$(curl -sS -m 30 "${API}/getUpdates?offset=$offset&timeout=25" 2>/dev/null)
        
        [[ -z "$resp" ]] && sleep 1 && continue
        echo "$resp" | grep -q '"ok":true' || { sleep 1; continue; }
        
        # 解析（使用简单的 grep）
        local uids=$(echo "$resp" | grep -o '"update_id":[0-9]*' | cut -d: -f2)
        [[ -z "$uids" ]] && sleep 1 && continue
        
        while read -r uid; do
            [[ -z "$uid" ]] && continue
            
            # 提取这个 update 的数据
            local update=$(echo "$resp" | grep -A 100 "\"update_id\":$uid" | grep -B 100 "\"update_id\":" | head -n -1)
            
            # 文本消息
            if echo "$update" | grep -q '"message".*"text"'; then
                local cid=$(echo "$update" | grep -o '"chat":{"id":[0-9-]*' | grep -o '[0-9-]*$' | head -1)
                local txt=$(echo "$update" | grep -o '"text":"[^"]*"' | head -1 | cut -d'"' -f4)
                log "[TXT] $txt"
                handle_text "$cid" "$txt"
            
            # 回调
            elif echo "$update" | grep -q '"callback_query"'; then
                local cid=$(echo "$update" | grep -o '"chat":{"id":[0-9-]*' | grep -o '[0-9-]*$' | head -1)
                local mid=$(echo "$update" | grep -o '"message_id":[0-9]*' | head -1 | cut -d: -f2)
                local cbid=$(echo "$update" | grep -o '"callback_query":{"id":"[^"]*"' | cut -d'"' -f4)
                local data=$(echo "$update" | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4)
                route "$cid" "$mid" "$cbid" "$data"
            fi
            
            # 保存新的 offset
            echo $((uid + 1)) > "$OFFSET_FILE"
        done <<< "$uids"
        
        sleep 0.5
    done
}

# 启动
[[ -z "${TELEGRAM_BOT_TOKEN}" ]] && log "[ERROR] Token 未配置" && exit 1
[[ -z "${TELEGRAM_CHAT_ID}" ]] && log "[ERROR] Chat ID 未配置" && exit 1

main
