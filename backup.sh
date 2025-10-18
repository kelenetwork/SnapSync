#!/bin/bash

# SnapSync v3.0 - 备份模块（完整修复版）
# 修复：
# 1. log 函数输出到 stderr，避免污染 stdout
# 2. SSH 连接强制使用密钥认证，禁用密码提示
# 3. 快照路径捕获逻辑完善

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

# ===== 工具函数（修复：输出到 stderr）=====
log_info() {
    # 输出到 stderr 和日志文件，避免污染 stdout
    echo -e "$(date '+%F %T') [INFO] $1" | tee -a "$LOG_FILE" >&2
}

log_error() {
    echo -e "$(date '+%F %T') ${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE" >&2
}

log_success() {
    echo -e "$(date '+%F %T') ${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE" >&2
}

# Telegram通知
send_telegram() {
    local message="$1"
    
    local tg_enabled=$(echo "${TELEGRAM_ENABLED:-false}" | tr '[:upper:]' '[:lower:]')
    if [[ "$tg_enabled" != "y" && "$tg_enabled" != "yes" && "$tg_enabled" != "true" ]]; then
        log_info "[TG] Telegram未启用"
        return 0
    fi
    
    if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        log_error "[TG] Telegram配置不完整"
        return 1
    fi
    
    local hostname="${HOSTNAME:-$(hostname)}"
    local vps_tag="🖥️ <b>${hostname}</b>"
    local full_message="${vps_tag}

${message}"
    
    log_info "[TG] 发送通知..."
    
    local response=$(curl -sS -m 15 -X POST \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${full_message}" \
        -d "parse_mode=HTML" \
        -d "disable_web_page_preview=true" 2>&1)
    
    if echo "$response" | grep -q '"ok":true'; then
        log_success "[TG] 通知发送成功"
        return 0
    else
        log_error "[TG] 通知发送失败: $response"
        return 1
    fi
}

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
    
    log_info "配置加载完成"
    log_info "  主机: $HOSTNAME"
    log_info "  备份目录: $BACKUP_DIR"
    log_info "  Telegram: ${TELEGRAM_ENABLED:-false}"
    log_info "  远程备份: ${REMOTE_ENABLED:-false}"
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
    
    # 发送成功通知
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
    
    # 只输出文件路径到 stdout
    echo "$snapshot_file"
    return 0
}

# ===== 上传远程（修复：强制使用密钥认证）=====
upload_to_remote() {
    local snapshot_file="$1"
    [[ ! -f "$snapshot_file" ]] && log_error "快照不存在: $snapshot_file" && return 1
    
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
    
    # 检查密钥文件
    if [[ ! -f "$ssh_key" ]]; then
        log_error "SSH 密钥不存在: $ssh_key"
        send_telegram "❌ <b>上传失败</b>

原因: SSH 密钥未配置
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')

请运行配置向导:
sudo snapsync
选择: 3) 配置管理 -> 1) 修改远程服务器配置"
        return 1
    fi
    
    # 修复：强制使用密钥认证，禁用密码提示
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
    log_info "测试 SSH 连接..."
    if ! ssh -i "$ssh_key" -p "$REMOTE_PORT" "${ssh_opts[@]}" \
            "${REMOTE_USER}@${REMOTE_HOST}" "echo ok" &>/dev/null; then
        log_error "无法连接远程服务器"
        send_telegram "❌ <b>上传失败</b>

原因: 无法连接到远程服务器
🌐 服务器: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT}
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')

请检查：
- SSH密钥是否已添加到远程服务器
- 远程服务器是否可达
- 网络连接是否正常

测试命令:
ssh -i $ssh_key -p $REMOTE_PORT ${REMOTE_USER}@${REMOTE_HOST}"
        return 1
    fi
    
    log_success "SSH 连接测试成功"
    
    # 创建远程目录
    log_info "创建远程目录..."
    ssh -i "$ssh_key" -p "$REMOTE_PORT" "${ssh_opts[@]}" \
        "${REMOTE_USER}@${REMOTE_HOST}" \
        "mkdir -p '${REMOTE_PATH}/system_snapshots'" || true
    
    # 上传
    local upload_start=$(date +%s)
    
    log_info "开始上传快照..."
    
    # 构建 rsync SSH 命令
    local rsync_ssh_cmd="ssh -i $ssh_key -p $REMOTE_PORT"
    for opt in "${ssh_opts[@]}"; do
        rsync_ssh_cmd="$rsync_ssh_cmd $opt"
    done
    
    if rsync -avz --partial --progress \
            -e "$rsync_ssh_cmd" \
            "$snapshot_file" \
            "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/system_snapshots/" \
            2>&1 | tee -a "$LOG_FILE" >&2; then
        
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
        if [[ -f "${snapshot_file}.sha256" ]]; then
            log_info "上传校验文件..."
            rsync -az -e "$rsync_ssh_cmd" \
                "${snapshot_file}.sha256" \
                "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/system_snapshots/" 2>&1 | tee -a "$LOG_FILE" >&2 || true
        fi
        
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
    
    local snapshots=()
    while IFS= read -r -d '' file; do
        if [[ "$file" != *.sha256 ]]; then
            snapshots+=("$file")
        fi
    done < <(find "${BACKUP_DIR}/system_snapshots" -name "system_snapshot_*.tar*" -type f -print0 2>/dev/null | sort -zr)
    
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

# ===== 清理远程（修复：强制使用密钥认证）=====
clean_remote_snapshots() {
    log_info "清理远程旧快照..."
    
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
    
    ssh -i "$ssh_key" -p "$REMOTE_PORT" "${ssh_opts[@]}" \
        "${REMOTE_USER}@${REMOTE_HOST}" \
        "find '${REMOTE_PATH}/system_snapshots' -name '*.tar*' -type f -mtime +${REMOTE_KEEP_DAYS:-30} -delete" \
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
    
    # 创建快照并捕获文件路径
    local snapshot_file
    snapshot_file=$(create_snapshot)
    local create_status=$?
    
    # 验证快照创建结果
    if [[ $create_status -eq 0 && -n "$snapshot_file" && -f "$snapshot_file" ]]; then
        log_success "快照创建成功: $snapshot_file"
    else
        log_error "快照创建失败 (状态码: $create_status, 文件: ${snapshot_file:-未生成})"
        exit 1
    fi
    
    clean_local_snapshots
    
    # 判断是否上传
    local remote_enabled=$(echo "${REMOTE_ENABLED:-false}" | tr '[:upper:]' '[:lower:]')
    local should_upload="no"
    
    if [[ "$remote_enabled" == "y" || "$remote_enabled" == "yes" || "$remote_enabled" == "true" ]]; then
        if [[ -n "${UPLOAD_REMOTE:-}" ]]; then
            local upload_choice=$(echo "${UPLOAD_REMOTE}" | tr '[:upper:]' '[:lower:]')
            if [[ "$upload_choice" == "y" || "$upload_choice" == "yes" ]]; then
                should_upload="yes"
            fi
        else
            should_upload="yes"
        fi
    fi
    
    # 执行上传
    if [[ "$should_upload" == "yes" ]]; then
        log_info "准备上传到远程服务器..."
        log_info "快照文件: $snapshot_file"
        
        if [[ -f "$snapshot_file" ]]; then
            upload_to_remote "$snapshot_file" || log_error "上传失败（本地备份已完成）"
        else
            log_error "快照文件丢失，无法上传: $snapshot_file"
        fi
    else
        log_info "跳过远程上传"
    fi
    
    log_info "========================================"
    log_success "SnapSync v3.0 备份完成"
    log_info "========================================"
}

main "$@"
