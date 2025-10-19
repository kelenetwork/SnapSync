#!/bin/bash

# SnapSync v3.0 - 远程恢复修复片段
# 将以下函数替换 telegram_bot.sh 中的对应函数

# ===== 恢复 - 远程快照确认（修复版）=====
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

# ===== 恢复 - 远程快照列表（修复版）=====
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
