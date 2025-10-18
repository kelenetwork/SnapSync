#!/bin/bash

# SnapSync v3.0 - 无损备份模块（已修复）
# 修复: 移除readonly冲突，改进配置加载

set -euo pipefail

# ===== 路径定义（不使用readonly）=====
CONFIG_FILE="/etc/snapsync/config.conf"
LOG_FILE="/var/log/snapsync/backup.log"
LOCK_FILE="/var/run/snapsync-backup.lock"

# ===== 颜色定义 =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ===== 初始化日志 =====
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

# Telegram通知
send_telegram() {
    [[ "${TELEGRAM_ENABLED:-}" != "Y" && "${TELEGRAM_ENABLED:-}" != "true" ]] && return 0
    [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]] && return 0
    
    curl -sS -m 15 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=$1" \
        -d "parse_mode=HTML" &>/dev/null || true
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
        log_info "请先运行安装脚本"
        exit 1
    fi
    
    # 安全加载配置（避免语法错误）
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
}

# ===== 系统检查 =====
check_system_resources() {
    log_info "${CYAN}检查系统资源...${NC}"
    
    local disk_usage=$(df "$BACKUP_DIR" 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')
    [[ ! "$disk_usage" =~ ^[0-9]+$ ]] && log_error "无法获取磁盘使用率" && return 1
    
    if (( disk_usage > ${DISK_THRESHOLD:-90} )); then
        log_error "磁盘空间不足: ${disk_usage}%"
        send_telegram "❌ <b>备份失败</b>

💾 磁盘使用: ${disk_usage}%
🖥️ 主机: ${HOSTNAME:-$(hostname)}"
        return 1
    fi
    
    log_info "磁盘使用: ${disk_usage}%"
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

📸 快照: ${snapshot_name}
🖥️ 主机: ${HOSTNAME:-$(hostname)}"
    
    check_system_resources || return 1
    
    # 确定压缩工具
    local compress_cmd="gzip -${COMPRESSION_LEVEL}"
    local compress_ext=".gz"
    
    if command -v pigz &>/dev/null; then
        local threads="${PARALLEL_THREADS}"
        [[ "$threads" == "auto" ]] && threads=$(nproc)
        compress_cmd="pigz -${COMPRESSION_LEVEL} -p ${threads}"
        log_info "使用 pigz (级别:${COMPRESSION_LEVEL}, 线程:${threads})"
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
    
    [[ "${ENABLE_ACL}" == "true" ]] && command -v getfacl &>/dev/null && tar_opts+=("--acls")
    [[ "${ENABLE_XATTR}" == "true" ]] && command -v getfattr &>/dev/null && tar_opts+=("--xattrs" "--xattrs-include=*")
    [[ -f /etc/selinux/config ]] && tar_opts+=("--selinux")
    
    # 排除列表
    local exclude_patterns=(
        "dev/*" "proc/*" "sys/*" "tmp/*" "run/*"
        "mnt/*" "media/*" "lost+found"
        "${BACKUP_DIR}/*"
        "*.log" "*.tmp" "*.swp"
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
    
    log_info "开始创建归档 (${#valid_dirs[@]} 个目录)..."
    
    # 执行备份
    cd / && {
        if tar "${tar_opts[@]}" "${valid_dirs[@]}" 2>/tmp/backup_err.log | $compress_cmd > "$temp_file"; then
            [[ ! -s "$temp_file" ]] && log_error "快照文件为空" && rm -f "$temp_file" && return 1
            mv "$temp_file" "$snapshot_file"
        else
            log_error "tar失败: $(cat /tmp/backup_err.log 2>/dev/null)"
            rm -f "$temp_file"
            return 1
        fi
    }
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local size=$(stat -c%s "$snapshot_file" 2>/dev/null || echo 0)
    local size_human=$(format_bytes "$size")
    
    log_success "快照创建成功"
    log_info "大小: $size_human | 耗时: ${duration}秒"
    
    # 生成校验和
    if [[ "${ENABLE_VERIFICATION}" == "true" ]]; then
        sha256sum "$snapshot_file" > "${snapshot_file}.sha256"
        log_info "✓ 已生成校验和"
    fi
    
    send_telegram "✅ <b>备份完成</b>

📦 大小: $size_human
⏱️ 耗时: ${duration}秒"
    
    echo "$snapshot_file"
}

# ===== 上传远程 =====
upload_to_remote() {
    local snapshot_file="$1"
    [[ ! -f "$snapshot_file" ]] && log_error "快照不存在" && return 1
    
    log_info "${CYAN}开始上传到远程${NC}"
    
    local ssh_key="/root/.ssh/id_ed25519"
    local ssh_opts="-o ConnectTimeout=30 -o StrictHostKeyChecking=no"
    
    # 测试连接
    if ! ssh -i "$ssh_key" -p "$REMOTE_PORT" $ssh_opts "${REMOTE_USER}@${REMOTE_HOST}" "echo ok" &>/dev/null; then
        log_error "无法连接远程服务器"
        return 1
    fi
    
    # 创建远程目录
    ssh -i "$ssh_key" -p "$REMOTE_PORT" $ssh_opts "${REMOTE_USER}@${REMOTE_HOST}" \
        "mkdir -p '${REMOTE_PATH}/system_snapshots'" || true
    
    # 上传
    if rsync -avz --partial -e "ssh -i $ssh_key -p $REMOTE_PORT $ssh_opts" \
            "$snapshot_file" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/system_snapshots/" \
            2>&1 | tee -a "$LOG_FILE"; then
        log_success "上传完成"
        
        # 上传校验和
        [[ -f "${snapshot_file}.sha256" ]] && \
            rsync -az -e "ssh -i $ssh_key -p $REMOTE_PORT $ssh_opts" \
                "${snapshot_file}.sha256" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/system_snapshots/" || true
        
        send_telegram "✅ <b>上传完成</b>"
        clean_remote_snapshots
    else
        log_error "上传失败"
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
        for ((i=keep; i<total; i++)); do
            log_info "  删除: $(basename "${snapshots[$i]}")"
            rm -f "${snapshots[$i]}" "${snapshots[$i]}.sha256"
        done
        log_success "本地清理完成"
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
}

# ===== 主程序 =====
main() {
    log_info "========================================"
    log_info "SnapSync v3.0 备份开始"
    log_info "========================================"
    
    acquire_lock
    load_config
    
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
        fi
    fi
    
    log_info "========================================"
    log_success "SnapSync v3.0 备份完成"
    log_info "========================================"
}

main "$@"
