#!/bin/bash

# SnapSync v3.0 - 备份模块（修复通知 + 多VPS支持）
# 修复：Telegram通知功能
# 新增：多VPS识别

set -euo pipefail

# ===== 路径定义 =====
CONFIG_FILE="/etc/snapsync/config.conf"
LOG_FILE="/var/log/snapsync/backup.log"
LOCK_FILE="/var/run/snapsync-backup.lock"

# ===== 颜色定义 =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ===== 初始化 =====
mkdir -p "$(dirname "$LOG_FILE")"

# ===== 工具函数 =====
log_info() {
    echo -e "$(date '+%F %T') [INFO] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "$(date '+%F %T') ${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "$(date '+%F %T') ${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

# Telegram通知（修复版）
send_telegram() {
    local message="$1"
    
    # 详细检查Telegram配置
    if [[ "${TELEGRAM_ENABLED:-false}" != "Y" && "${TELEGRAM_ENABLED:-false}" != "true" ]]; then
        log_info "[TG] Telegram未启用 (TELEGRAM_ENABLED=${TELEGRAM_ENABLED:-未设置})"
        return 0
    fi
    
    if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
        log_error "[TG] BOT_TOKEN未设置"
        return 1
    fi
    
    if [[ -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        log_error "[TG] CHAT_ID未设置"
        return 1
    fi
    
    # 添加VPS标识（支持多VPS管理）
    local hostname="${HOSTNAME:-$(hostname)}"
    local vps_tag="🖥️ <b>${hostname}</b>"
    local full_message="${vps_tag}

${message}"
    
    log_info "[TG] 发送通知..."
    
    # 发送消息
    local response=$(curl -sS -m 15 -X POST \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${full_message}" \
        -d "parse_mode=HTML" \
        -d "disable_web_page_preview=true" 2>&1)
    
    # 检查结果
    if echo "$response" | grep -q '"ok":true'; then
        log_success "[TG] 通知发送成功"
        return 0
    else
        log_error "[TG] 通知发送失败: $response"
        return 1
    fi
}

# 测试Telegram连接
test_telegram() {
    log_info "${CYAN}测试 Telegram 连接...${NC}"
    
    if [[ "${TELEGRAM_ENABLED:-false}" != "Y" && "${TELEGRAM_ENABLED:-false}" != "true" ]]; then
        log_info "Telegram未启用，跳过测试"
        return 0
    fi
    
    if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        log_error "Telegram配置不完整"
        echo ""
        echo "当前配置:"
        echo "  TELEGRAM_ENABLED: ${TELEGRAM_ENABLED:-未设置}"
        echo "  TELEGRAM_BOT_TOKEN: ${TELEGRAM_BOT_TOKEN:0:20}... (${#TELEGRAM_BOT_TOKEN} 字符)"
        echo "  TELEGRAM_CHAT_ID: ${TELEGRAM_CHAT_ID:-未设置}"
        echo ""
        return 1
    fi
    
    # 测试API
    log_info "测试 Bot API..."
    local test_response=$(curl -sS -m 10 \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" 2>&1)
    
    if echo "$test_response" | grep -q '"ok":true'; then
        local bot_name=$(echo "$test_response" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
        log_success "Bot连接成功: @${bot_name}"
        
        # 发送测试消息
        log_info "发送测试消息..."
        if send_telegram "🔍 <b>连接测试</b>

✅ Telegram通知功能正常
⏰ 测试时间: $(date '+%Y-%m-%d %H:%M:%S')

备份任务将发送通知到此会话"; then
            log_success "测试消息发送成功！"
            return 0
        else
            log_error "测试消息发送失败"
            return 1
        fi
    else
        log_error "Bot API测试失败: $test_response"
        echo ""
        echo "可能的原因："
        echo "  1. Bot Token 错误"
        echo "  2. Bot 被删除"
        echo "  3. 网络连接问题"
        echo ""
        return 1
    fi
}

# 字节格式化
format_bytes() {
    local bytes="$1"
    [[ ! "$bytes" =~ ^[0-9]+$ ]] && echo "0B" && return
    
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

# 进程锁
acquire_lock() {
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        log_error "备份进程已在运行"
        send_telegram "⚠️ <b>备份跳过</b>

原因: 上一个备份任务仍在运行
时间: $(date '+%Y-%m-%d %H:%M:%S')"
        exit 1
    fi
    echo $$ >&200
}

release_lock() {
    flock -u 200 2>/dev/null || true
    rm -f "$LOCK_FILE" 2>/dev/null || true
}

trap release_lock EXIT

# ===== 加载配置 =====
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "配置文件不存在: $CONFIG_FILE"
        exit 1
    fi
    
    if ! bash -n "$CONFIG_FILE" 2>/dev/null; then
        log_error "配置文件语法错误"
        exit 1
    fi
    
    source "$CONFIG_FILE"
    
    # 设置默认值
    BACKUP_DIR="${BACKUP_DIR:-/backups}"
    COMPRESSION_LEVEL="${COMPRESSION_LEVEL:-6}"
    PARALLEL_THREADS="${PARALLEL_THREADS:-auto}"
    LOCAL_KEEP_COUNT="${LOCAL_KEEP_COUNT:-5}"
    ENABLE_ACL="${ENABLE_ACL:-true}"
    ENABLE_XATTR="${ENABLE_XATTR:-true}"
    ENABLE_VERIFICATION="${ENABLE_VERIFICATION:-true}"
    HOSTNAME="${HOSTNAME:-$(hostname)}"
    
    # 显示配置摘要
    log_info "配置加载完成"
    log_info "  主机: $HOSTNAME"
    log_info "  备份目录: $BACKUP_DIR"
    log_info "  Telegram: ${TELEGRAM_ENABLED:-false}"
}

# ===== 系统检查 =====
check_system_resources() {
    log_info "${CYAN}检查系统资源...${NC}"
    
    local disk_usage=$(df "$BACKUP_DIR" 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')
    [[ ! "$disk_usage" =~ ^[0-9]+$ ]] && log_error "无法获取磁盘使用率" && return 1
    
    if (( disk_usage > ${DISK_THRESHOLD:-90} )); then
        log_error "磁盘空间不足: ${disk_usage}%"
        send_telegram "❌ <b>备份失败</b>

💾 磁盘使用率: ${disk_usage}%
⚠️ 阈值: ${DISK_THRESHOLD:-90}%
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')

请清理磁盘空间后重试"
        return 1
    fi
    
    local disk_free=$(df -h "$BACKUP_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
    log_info "磁盘状态: 使用率 ${disk_usage}%, 可用 ${disk_free}"
    return 0
}

# ===== 创建快照 =====
create_snapshot() {
    local start_time=$(date +%s)
    local timestamp=$(date +"%Y%m%d%H%M%S")
    local snapshot_name="system_snapshot_${timestamp}"
    local snapshot_dir="${BACKUP_DIR}/system_snapshots"
    
    mkdir -p "$snapshot_dir"
    
    log_info "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "${CYAN}开始创建系统快照${NC}"
    log_info "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # 发送开始通知
    send_telegram "🔄 <b>开始备份</b>

📸 快照名称: ${snapshot_name}
📂 备份目录: ${BACKUP_DIR}
⏰ 开始时间: $(date '+%Y-%m-%d %H:%M:%S')

备份进行中，请稍候..."
    
    check_system_resources || return 1
    
    # 确定压缩工具
    local compress_cmd="gzip -${COMPRESSION_LEVEL}"
    local compress_ext=".gz"
    
    if command -v pigz &>/dev/null; then
        local threads="${PARALLEL_THREADS}"
        [[ "$threads" == "auto" ]] && threads=$(nproc)
        compress_cmd="pigz -${COMPRESSION_LEVEL} -p ${threads}"
        log_info "使用 pigz 多线程压缩 (级别:${COMPRESSION_LEVEL}, 线程:${threads})"
    else
        log_info "使用 gzip 压缩 (级别:${COMPRESSION_LEVEL})"
    fi
    
    local snapshot_file="${snapshot_dir}/${snapshot_name}.tar${compress_ext}"
    local temp_file="${snapshot_file}.tmp"
    
    # tar参数
    local tar_opts=(
        "--create" "--file=-"
        "--preserve-permissions"
        "--same-owner"
        "--numeric-owner"
        "--sparse"
        "--warning=no-file-changed"
        "--warning=no-file-removed"
    )
    
    [[ "${ENABLE_ACL}" == "true" ]] && command -v getfacl &>/dev/null && tar_opts+=("--acls") && log_info "✓ ACL支持"
    [[ "${ENABLE_XATTR}" == "true" ]] && command -v getfattr &>/dev/null && tar_opts+=("--xattrs" "--xattrs-include=*") && log_info "✓ 扩展属性支持"
    [[ -f /etc/selinux/config ]] && tar_opts+=("--selinux") && log_info "✓ SELinux支持"
    
    # 排除列表
    local exclude_patterns=(
        "dev/*" "proc/*" "sys/*" "tmp/*" "run/*"
        "mnt/*" "media/*" "lost+found"
        "${BACKUP_DIR}/*"
        "*.log" "*.tmp" "*.swp" "swap*"
        ".cache/*"
    )
    
    for pattern in "${exclude_patterns[@]}"; do
        tar_opts+=("--exclude=$pattern")
    done
    
    # 包含目录
    local include_dirs=(boot etc home opt root srv usr var)
    local valid_dirs=()
    for dir in "${include_dirs[@]}"; do
        [[ -d "/$dir" ]] && valid_dirs+=("$dir")
    done
    
    log_info "开始创建归档 (${#valid_dirs[@]} 个目录: ${valid_dirs[*]})..."
    
    # 执行备份
    cd / && {
        if tar "${tar_opts[@]}" "${valid_dirs[@]}" 2>/tmp/backup_err.log | $compress_cmd > "$temp_file"; then
            if [[ ! -s "$temp_file" ]]; then
                log_error "快照文件为空"
                rm -f "$temp_file"
                send_telegram "❌ <b>备份失败</b>

原因: 生成的快照文件为空
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')

请检查日志: $LOG_FILE"
                return 1
            fi
            mv "$temp_file" "$snapshot_file"
        else
            local tar_error=$(cat /tmp/backup_err.log 2>/dev/null | tail -5)
            log_error "tar失败: $tar_error"
            rm -f "$temp_file"
            send_telegram "❌ <b>备份失败</b>

原因: tar 归档失败
错误: ${tar_error:0:200}
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')

请检查日志: $LOG_FILE"
            return 1
        fi
    }
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local size=$(stat -c%s "$snapshot_file" 2>/dev/null || echo 0)
    local size_human=$(format_bytes "$size")
    
    log_success "快照创建成功"
    log_info "  文件: $(basename "$snapshot_file")"
    log_info "  大小: $size_human"
    log_info "  耗时: ${duration}秒"
    
    # 生成校验和
    if [[ "${ENABLE_VERIFICATION}" == "true" ]]; then
        log_info "生成校验和..."
        sha256sum "$snapshot_file" > "${snapshot_file}.sha256"
        local checksum=$(cut -d' ' -f1 "${snapshot_file}.sha256")
        log_info "✓ SHA256: ${checksum:0:16}..."
    fi
    
    # 发送成功通知（详细信息）
    local speed="N/A"
    if (( duration > 0 )); then
        local speed_bps=$((size / duration))
        speed=$(format_bytes "$speed_bps")/s
    fi
    
    send_telegram "✅ <b>备份完成</b>

📸 快照名称: $(basename "$snapshot_file")
📦 文件大小: $size_human
⏱️ 备份耗时: ${duration}秒
⚡ 平均速度: $speed
✓ 校验和: 已生成
⏰ 完成时间: $(date '+%Y-%m-%d %H:%M:%S')

快照已保存到: $snapshot_dir"
    
    echo "$snapshot_file"
}

# ===== 上传远程 =====
upload_to_remote() {
    local snapshot_file="$1"
    [[ ! -f "$snapshot_file" ]] && log_error "快照不存在" && return 1
    
    log_info "${CYAN}开始上传到远程服务器${NC}"
    
    local snapshot_name=$(basename "$snapshot_file")
    local size=$(format_bytes "$(stat -c%s "$snapshot_file" 2>/dev/null || echo 0)")
    
    send_telegram "⬆️ <b>开始上传</b>

📦 文件: ${snapshot_name}
📊 大小: ${size}
🌐 服务器: ${REMOTE_HOST}
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')

上传进行中..."
    
    local ssh_key="/root/.ssh/id_ed25519"
    local ssh_opts="-o ConnectTimeout=30 -o StrictHostKeyChecking=no"
    
    # 测试连接
    if ! ssh -i "$ssh_key" -p "$REMOTE_PORT" $ssh_opts "${REMOTE_USER}@${REMOTE_HOST}" "echo ok" &>/dev/null; then
        log_error "无法连接远程服务器"
        send_telegram "❌ <b>上传失败</b>

原因: 无法连接到远程服务器
🌐 服务器: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT}
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')

请检查：
• SSH密钥配置
• 网络连接
• 远程服务器状态"
        return 1
    fi
    
    # 创建远程目录
    ssh -i "$ssh_key" -p "$REMOTE_PORT" $ssh_opts "${REMOTE_USER}@${REMOTE_HOST}" \
        "mkdir -p '${REMOTE_PATH}/system_snapshots'" || true
    
    # 上传
    local upload_start=$(date +%s)
    
    if rsync -avz --partial --progress \
            -e "ssh -i $ssh_key -p $REMOTE_PORT $ssh_opts" \
            "$snapshot_file" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/system_snapshots/" \
            2>&1 | tee -a "$LOG_FILE"; then
        
        local upload_duration=$(($(date +%s) - upload_start))
        local upload_speed="N/A"
        
        if (( upload_duration > 0 )); then
            local file_size=$(stat -c%s "$snapshot_file")
            local speed_bps=$((file_size / upload_duration))
            upload_speed=$(format_bytes "$speed_bps")/s
        fi
        
        log_success "上传完成"
        log_info "  耗时: ${upload_duration}秒"
        log_info "  速度: $upload_speed"
        
        # 上传校验和
        [[ -f "${snapshot_file}.sha256" ]] && \
            rsync -az -e "ssh -i $ssh_key -p $REMOTE_PORT $ssh_opts" \
                "${snapshot_file}.sha256" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/system_snapshots/" || true
        
        send_telegram "✅ <b>上传完成</b>

📦 文件: ${snapshot_name}
⏱️ 上传耗时: ${upload_duration}秒
⚡ 上传速度: $upload_speed
🌐 目标: ${REMOTE_HOST}:${REMOTE_PATH}
⏰ 完成时间: $(date '+%Y-%m-%d %H:%M:%S')

远程备份已完成"
        
        clean_remote_snapshots
    else
        log_error "上传失败"
        send_telegram "❌ <b>上传失败</b>

📦 文件: ${snapshot_name}
🌐 服务器: ${REMOTE_HOST}
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')

本地备份已完成，但远程上传失败
请检查网络连接和远程服务器状态"
        return 1
    fi
}

# ===== 清理本地 =====
clean_local_snapshots() {
    log_info "清理本地旧快照..."
    
    local snapshots=($(find "${BACKUP_DIR}/system_snapshots" -name "system_snapshot_*.tar*" -type f 2>/dev/null | sort -r))
    local total=${#snapshots[@]}
    local keep=${LOCAL_KEEP_COUNT:-5}
    
    if (( total > keep )); then
        local removed=0
        for ((i=keep; i<total; i++)); do
            local old_file="${snapshots[$i]}"
            log_info "  删除: $(basename "$old_file")"
            rm -f "$old_file" "${old_file}.sha256"
            ((removed++))
        done
        log_success "清理完成: 删除 $removed 个旧快照"
    else
        log_info "快照数量未超限 ($total/$keep)"
    fi
}

# ===== 清理远程 =====
clean_remote_snapshots() {
    log_info "清理远程旧快照..."
    
    local ssh_key="/root/.ssh/id_ed25519"
    local ssh_opts="-o ConnectTimeout=30 -o StrictHostKeyChecking=no"
    
    ssh -i "$ssh_key" -p "$REMOTE_PORT" $ssh_opts "${REMOTE_USER}@${REMOTE_HOST}" \
        "find '${REMOTE_PATH}/system_snapshots' -name '*.tar*' -mtime +${REMOTE_KEEP_DAYS:-30} -delete" \
        2>/dev/null || true
    
    log_info "远程清理完成 (保留${REMOTE_KEEP_DAYS:-30}天)"
}

# ===== 主程序 =====
main() {
    log_info "========================================"
    log_info "SnapSync v3.0 备份开始"
    log_info "主机: ${HOSTNAME:-$(hostname)}"
    log_info "========================================"
    
    acquire_lock
    load_config
    
    # 测试Telegram（仅在启用时）
    if [[ "${TELEGRAM_ENABLED}" =~ ^[Yy]|true$ ]]; then
        test_telegram || log_error "Telegram测试失败，但继续备份"
    fi
    
    local snapshot_file
    if snapshot_file=$(create_snapshot); then
        log_success "快照创建成功: $snapshot_file"
    else
        log_error "快照创建失败"
        exit 1
    fi
    
    clean_local_snapshots
    
    # 上传（如果启用）
    if [[ "${REMOTE_ENABLED}" =~ ^[Yy]|true$ ]]; then
        if [[ "${UPLOAD_REMOTE:-Y}" =~ ^[Yy]$ ]]; then
            upload_to_remote "$snapshot_file" || log_error "上传失败"
        else
            log_info "跳过远程上传（用户选择）"
        fi
    fi
    
    log_info "========================================"
    log_success "SnapSync v3.0 备份完成"
    log_info "========================================"
}

main "$@"
