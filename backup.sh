#!/bin/bash

# SnapSync v3.0 - 无损备份模块
# 完整保留文件权限、ACL、扩展属性

set -euo pipefail

# ===== 路径定义 =====
readonly CONFIG_FILE="/etc/snapsync/config.conf"
readonly LOG_FILE="/var/log/snapsync/backup.log"
readonly LOCK_FILE="/var/run/snapsync-backup.lock"

# ===== 颜色定义 =====
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# ===== 加载或创建配置 =====
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${YELLOW}首次运行，创建配置文件...${NC}"
    mkdir -p "$CONFIG_DIR"
    
    # 创建默认配置
    cat > "$CONFIG_FILE" << 'EOFCONFIG'
#!/bin/bash
# SnapSync 配置文件（自动生成）

# Telegram 配置（可选）
TELEGRAM_ENABLED="false"
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

# 远程备份（可选）
REMOTE_ENABLED="false"
REMOTE_HOST=""
REMOTE_USER="root"
REMOTE_PORT="22"
REMOTE_PATH="/backups"
REMOTE_KEEP_DAYS="30"

# 本地备份
BACKUP_DIR="/backups"
LOCAL_KEEP_COUNT="5"

# 定时任务
AUTO_BACKUP_ENABLED="false"
BACKUP_INTERVAL_DAYS="7"
BACKUP_TIME="03:00"

# 无损备份特性（自动启用）
ENABLE_ACL="true"
ENABLE_XATTR="true"
ENABLE_SELINUX="true"
ENABLE_VERIFICATION="true"

# 性能优化（自动）
PARALLEL_THREADS="auto"
COMPRESSION_LEVEL="6"

# 系统信息
HOSTNAME="$(hostname)"
EOFCONFIG
    
    chmod 600 "$CONFIG_FILE"
    echo -e "${GREEN}✓ 配置文件已创建: $CONFIG_FILE${NC}"
    echo -e "${YELLOW}提示: 可编辑此文件修改配置${NC}\n"
fi

source "$CONFIG_FILE"

# ===== 工具函数 =====
log_info() {
    local msg="$1"
    echo -e "$(date '+%F %T') [INFO] $msg" | tee -a "$LOG_FILE"
}

log_error() {
    local msg="$1"
    echo -e "$(date '+%F %T') ${RED}[ERROR]${NC} $msg" | tee -a "$LOG_FILE"
}

log_success() {
    local msg="$1"
    echo -e "$(date '+%F %T') ${GREEN}[SUCCESS]${NC} $msg" | tee -a "$LOG_FILE"
}

# Telegram 通知
send_telegram() {
    if [[ "${TELEGRAM_ENABLED}" != "Y" ]] && [[ "${TELEGRAM_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    local message="$1"
    local formatted=$(printf "%b" "$message")
    
    curl -sS -m 15 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${formatted}" \
        -d "parse_mode=HTML" &>/dev/null || true
}

# 字节格式化
format_bytes() {
    local bytes="$1"
    
    if [[ ! "$bytes" =~ ^[0-9]+$ ]]; then
        echo "0B"
        return
    fi
    
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
        log_error "备份进程已在运行中"
        exit 1
    fi
    echo $$ >&200
}

release_lock() {
    flock -u 200 2>/dev/null || true
    rm -f "$LOCK_FILE" 2>/dev/null || true
}

trap release_lock EXIT

# ===== 系统检查 =====
check_system_resources() {
    log_info "${CYAN}检查系统资源...${NC}"
    
    # 磁盘空间
    local disk_usage=$(df "$BACKUP_DIR" 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')
    
    if [[ ! "$disk_usage" =~ ^[0-9]+$ ]]; then
        log_error "无法获取磁盘使用率"
        return 1
    fi
    
    if (( disk_usage > ${DISK_THRESHOLD:-90} )); then
        log_error "磁盘空间不足: ${disk_usage}% > ${DISK_THRESHOLD}%"
        send_telegram "❌ <b>备份失败</b>

💾 磁盘使用率: ${disk_usage}%
🖥️ 主机: ${HOSTNAME}
⏰ 时间: $(date '+%F %T')"
        return 1
    fi
    
    # 内存检查
    local mem_usage=$(free | awk '/^Mem:/ {printf "%.0f", $3/$2 * 100}')
    
    if (( mem_usage > ${MEMORY_THRESHOLD:-85} )); then
        log_info "内存使用率较高: ${mem_usage}%，启用内存优化模式"
        export COMPRESSION_LEVEL=1
    fi
    
    # 负载检查
    local load=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')
    local cpu_cores=$(nproc)
    
    log_info "系统状态 - 磁盘: ${disk_usage}%, 内存: ${mem_usage}%, 负载: ${load}/${cpu_cores}"
    
    return 0
}

# ===== 备份元数据 =====
backup_metadata() {
    log_info "备份系统元数据..."
    
    local metadata_dir="${BACKUP_DIR}/metadata/$(date +%Y%m%d%H%M%S)"
    mkdir -p "$metadata_dir"
    
    # 系统信息
    {
        echo "=== 系统信息 ==="
        uname -a
        echo ""
        echo "=== 主机名 ==="
        hostname
        echo ""
        echo "=== 内核版本 ==="
        cat /proc/version 2>/dev/null
    } > "$metadata_dir/system_info.txt"
    
    # 硬件信息
    {
        echo "=== CPU 信息 ==="
        lscpu 2>/dev/null || cat /proc/cpuinfo
        echo ""
        echo "=== 内存信息 ==="
        free -h
        echo ""
        echo "=== 磁盘信息 ==="
        lsblk
    } > "$metadata_dir/hardware_info.txt"
    
    # 文件系统
    {
        echo "=== 挂载点 ==="
        mount
        echo ""
        echo "=== 磁盘空间 ==="
        df -h
        echo ""
        echo "=== fstab ==="
        cat /etc/fstab
    } > "$metadata_dir/filesystem_info.txt"
    
    # 网络配置
    {
        echo "=== 网络接口 ==="
        ip addr show
        echo ""
        echo "=== 路由表 ==="
        ip route show
        echo ""
        echo "=== DNS 配置 ==="
        cat /etc/resolv.conf 2>/dev/null || echo "N/A"
    } > "$metadata_dir/network_info.txt"
    
    # 已安装软件包
    if command -v dpkg &>/dev/null; then
        dpkg -l > "$metadata_dir/packages.txt" 2>/dev/null
    elif command -v rpm &>/dev/null; then
        rpm -qa > "$metadata_dir/packages.txt" 2>/dev/null
    fi
    
    # 用户和组
    cp /etc/passwd "$metadata_dir/" 2>/dev/null || true
    cp /etc/group "$metadata_dir/" 2>/dev/null || true
    cp /etc/shadow "$metadata_dir/" 2>/dev/null || true
    
    # Systemd 服务
    if command -v systemctl &>/dev/null; then
        systemctl list-units --all > "$metadata_dir/systemd_units.txt" 2>/dev/null || true
    fi
    
    log_success "元数据备份完成"
}

# ===== 创建无损快照 =====
create_lossless_snapshot() {
    local start_time=$(date +%s)
    local timestamp=$(date +"%Y%m%d%H%M%S")
    local snapshot_name="system_snapshot_${timestamp}"
    local snapshot_dir="${BACKUP_DIR}/system_snapshots"
    
    mkdir -p "$snapshot_dir"
    
    log_info "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "${CYAN}开始创建无损系统快照${NC}"
    log_info "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    send_telegram "🔄 <b>开始备份</b>

📸 快照名称: ${snapshot_name}
🖥️ 主机: ${HOSTNAME}
⏰ 时间: $(date '+%F %T')"
    
    # 检查系统资源
    if ! check_system_resources; then
        return 1
    fi
    
    # 备份元数据
    backup_metadata
    
    # 确定压缩工具
    local compress_cmd="cat"
    local compress_ext=""
    
    if command -v pigz &>/dev/null; then
        local threads="${PARALLEL_THREADS}"
        [[ "$threads" == "auto" ]] && threads=$(nproc)
        compress_cmd="pigz -${COMPRESSION_LEVEL} -p ${threads}"
        compress_ext=".gz"
        log_info "使用 pigz 多线程压缩 (级别: ${COMPRESSION_LEVEL}, 线程: ${threads})"
    else
        compress_cmd="gzip -${COMPRESSION_LEVEL}"
        compress_ext=".gz"
        log_info "使用 gzip 压缩 (级别: ${COMPRESSION_LEVEL})"
    fi
    
    local snapshot_file="${snapshot_dir}/${snapshot_name}.tar${compress_ext}"
    local temp_file="${snapshot_file}.tmp"
    
    # 构建 tar 参数
    local tar_opts=(
        "--create"
        "--file=-"
        "--preserve-permissions"
        "--same-owner"
        "--numeric-owner"
        "--sparse"
        "--warning=no-file-changed"
        "--warning=no-file-removed"
    )
    
    # 启用 ACL 支持
    if [[ "${ENABLE_ACL}" == "true" ]] && command -v getfacl &>/dev/null; then
        tar_opts+=("--acls")
        log_info "✓ 启用 ACL 权限保留"
    fi
    
    # 启用扩展属性
    if [[ "${ENABLE_XATTR}" == "true" ]] && command -v getfattr &>/dev/null; then
        tar_opts+=("--xattrs" "--xattrs-include=*")
        log_info "✓ 启用扩展属性保留"
    fi
    
    # 启用 SELinux 上下文
    if [[ -f /etc/selinux/config ]] && command -v getenforce &>/dev/null; then
        tar_opts+=("--selinux")
        log_info "✓ 启用 SELinux 上下文保留"
    fi
    
    # 定义排除列表
    local exclude_patterns=(
        "dev/*" "proc/*" "sys/*" "tmp/*" "run/*"
        "mnt/*" "media/*" "lost+found"
        "var/cache/*" "var/tmp/*"
        "var/lib/docker/overlay2/*"
        "${BACKUP_DIR}/*"
        "*.log" "*.tmp" "*.swp" "swap*"
        ".cache/*" ".thumbnails/*"
    )
    
    # 添加排除参数
    for pattern in "${exclude_patterns[@]}"; do
        tar_opts+=("--exclude=$pattern")
    done
    
    # 包含的目录
    local include_dirs=(
        "boot" "etc" "home" "opt" "root" "srv"
        "usr" "var"
    )
    
    # 只包含存在的目录
    local valid_dirs=()
    for dir in "${include_dirs[@]}"; do
        if [[ -d "/$dir" ]]; then
            valid_dirs+=("$dir")
        fi
    done
    
    log_info "开始创建 tar 归档 (包含 ${#valid_dirs[@]} 个目录)..."
    
    # 执行备份
    cd / && {
        if tar "${tar_opts[@]}" "${valid_dirs[@]}" 2>/tmp/backup_stderr.log | \
           $compress_cmd > "$temp_file"; then
            
            # 检查文件大小
            if [[ ! -s "$temp_file" ]]; then
                log_error "快照文件为空"
                rm -f "$temp_file"
                return 1
            fi
            
            # 移动到最终位置
            mv "$temp_file" "$snapshot_file"
            
        else
            local exit_code=$?
            log_error "tar 命令失败 (退出码: $exit_code)"
            
            if [[ -f /tmp/backup_stderr.log ]]; then
                log_error "错误详情: $(cat /tmp/backup_stderr.log)"
            fi
            
            rm -f "$temp_file"
            return 1
        fi
    }
    
    # 计算统计信息
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local snapshot_size=$(stat -c%s "$snapshot_file" 2>/dev/null || echo 0)
    local size_human=$(format_bytes "$snapshot_size")
    
    log_success "快照创建成功"
    log_info "文件名: $(basename "$snapshot_file")"
    log_info "大小: $size_human"
    log_info "耗时: ${duration} 秒"
    
    # 生成校验和
    if [[ "${ENABLE_VERIFICATION}" == "true" ]]; then
        log_info "生成 SHA256 校验和..."
        local checksum_file="${snapshot_file}.sha256"
        sha256sum "$snapshot_file" > "$checksum_file"
        local checksum=$(cut -d' ' -f1 "$checksum_file")
        log_success "校验和: ${checksum:0:16}..."
    fi
    
    # 发送成功通知
    local notification="✅ <b>备份完成</b>

📸 快照: $(basename "$snapshot_file")
📦 大小: $size_human
⏱️ 耗时: ${duration} 秒
🖥️ 主机: ${HOSTNAME}
⏰ 时间: $(date '+%F %T')"
    
    send_telegram "$notification"
    
    # 返回快照文件路径供上传使用
    echo "$snapshot_file"
}

# ===== 上传到远程 =====
upload_to_remote() {
    local snapshot_file="$1"
    
    if [[ ! -f "$snapshot_file" ]]; then
        log_error "快照文件不存在: $snapshot_file"
        return 1
    fi
    
    log_info "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "${CYAN}开始上传到远程服务器${NC}"
    log_info "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    local snapshot_name=$(basename "$snapshot_file")
    local snapshot_size=$(stat -c%s "$snapshot_file" 2>/dev/null || echo 0)
    local size_human=$(format_bytes "$snapshot_size")
    
    log_info "服务器: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT}"
    log_info "路径: ${REMOTE_PATH}"
    log_info "文件: $snapshot_name ($size_human)"
    
    send_telegram "⬆️ <b>开始上传</b>

📦 文件: ${snapshot_name}
📊 大小: ${size_human}
🌐 服务器: ${REMOTE_HOST}"
    
    # SSH 配置
    local ssh_key="/root/.ssh/id_ed25519"
    local ssh_opts="-o ConnectTimeout=30 -o ServerAliveInterval=60 -o StrictHostKeyChecking=no"
    
    # SSH 连接测试
    if ! ssh -i "$ssh_key" -p "$REMOTE_PORT" $ssh_opts \
            "${REMOTE_USER}@${REMOTE_HOST}" "echo 'test'" &>/dev/null; then
        log_error "无法连接到远程服务器"
        send_telegram "❌ <b>上传失败</b>

原因: 无法连接服务器
服务器: ${REMOTE_HOST}"
        return 1
    fi
    
    # 创建远程目录
    ssh -i "$ssh_key" -p "$REMOTE_PORT" $ssh_opts \
        "${REMOTE_USER}@${REMOTE_HOST}" \
        "mkdir -p '${REMOTE_PATH}/system_snapshots' '${REMOTE_PATH}/checksums'" || true
    
    # 上传快照
    local start_time=$(date +%s)
    
    if rsync -avz --partial --progress \
            -e "ssh -i $ssh_key -p $REMOTE_PORT $ssh_opts" \
            "$snapshot_file" \
            "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/system_snapshots/" \
            2>&1 | tee -a "$LOG_FILE"; then
        
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local speed="N/A"
        
        if (( duration > 0 )); then
            local speed_bps=$((snapshot_size / duration))
            speed=$(format_bytes "$speed_bps")/s
        fi
        
        log_success "上传完成"
        log_info "耗时: ${duration} 秒"
        log_info "速度: $speed"
        
        # 上传校验和
        if [[ -f "${snapshot_file}.sha256" ]]; then
            rsync -az -e "ssh -i $ssh_key -p $REMOTE_PORT $ssh_opts" \
                "${snapshot_file}.sha256" \
                "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/checksums/" || true
        fi
        
        send_telegram "✅ <b>上传完成</b>

⏱️ 耗时: ${duration} 秒
📊 速度: $speed"
        
        # 远程清理
        clean_remote_snapshots
        
    else
        log_error "上传失败"
        send_telegram "❌ <b>上传失败</b>

请检查网络连接和远程服务器状态"
        return 1
    fi
}

# ===== 清理本地快照 =====
clean_local_snapshots() {
    log_info "清理本地旧快照..."
    
    local snapshot_dir="${BACKUP_DIR}/system_snapshots"
    local snapshots=($(find "$snapshot_dir" -name "system_snapshot_*.tar*" -type f 2>/dev/null | sort -r))
    local total=${#snapshots[@]}
    local keep=${LOCAL_KEEP_COUNT:-5}
    
    if (( total > keep )); then
        local to_remove=$((total - keep))
        log_info "需要删除 $to_remove 个旧快照 (保留 $keep 个)"
        
        for ((i=keep; i<total; i++)); do
            local old_snapshot="${snapshots[$i]}"
            log_info "  删除: $(basename "$old_snapshot")"
            rm -f "$old_snapshot" "${old_snapshot}.sha256"
        done
        
        log_success "本地清理完成"
    else
        log_info "本地快照数量未超过限制 ($total/$keep)"
    fi
}

# ===== 清理远程快照 =====
clean_remote_snapshots() {
    log_info "清理远程旧快照..."
    
    local ssh_key="/root/.ssh/id_ed25519"
    local ssh_opts="-o ConnectTimeout=30 -o StrictHostKeyChecking=no"
    local keep_days=${REMOTE_KEEP_DAYS:-30}
    
    ssh -i "$ssh_key" -p "$REMOTE_PORT" $ssh_opts \
        "${REMOTE_USER}@${REMOTE_HOST}" \
        "find '${REMOTE_PATH}/system_snapshots' -name '*.tar*' -mtime +${keep_days} -delete" \
        2>/dev/null || true
    
    log_info "远程清理完成 (保留 ${keep_days} 天)"
}

# ===== 主执行流程 =====
main() {
    log_info "========================================="
    log_info "SnapSync v3.0 无损备份开始"
    log_info "========================================="
    
    # 获取进程锁
    acquire_lock
    
    # 创建快照
    local snapshot_file
    if snapshot_file=$(create_lossless_snapshot); then
        log_success "快照创建成功: $snapshot_file"
    else
        log_error "快照创建失败"
        exit 1
    fi
    
    # 清理本地旧快照
    clean_local_snapshots
    
    # 上传到远程 (如果启用)
    if [[ "${REMOTE_ENABLED}" == "Y" ]] || [[ "${REMOTE_ENABLED}" == "true" ]]; then
        if [[ "${UPLOAD_REMOTE:-Y}" =~ ^[Yy]$ ]]; then
            if ! upload_to_remote "$snapshot_file"; then
                log_error "远程上传失败，快照仅保存在本地"
            fi
        else
            log_info "跳过远程上传（用户选择）"
        fi
    else
        log_info "远程备份未启用"
    fi
    
    log_info "========================================="
    log_success "SnapSync v3.0 无损备份完成"
    log_info "========================================="
}

# 运行主程序
main "$@"
