#!/bin/bash

# SnapSync v3.0 - 无损恢复模块
# 完整恢复文件权限、ACL、扩展属性

set -euo pipefail

# ===== 路径定义 =====
readonly CONFIG_FILE="/etc/snapsync/config.conf"
readonly LOG_FILE="/var/log/snapsync/restore.log"

# ===== 颜色定义 =====
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# ===== 加载配置 =====
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

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

log_warning() {
    local msg="$1"
    echo -e "$(date '+%F %T') ${YELLOW}[WARNING]${NC} $msg" | tee -a "$LOG_FILE"
}

# Telegram 通知
send_telegram() {
    if [[ "${TELEGRAM_ENABLED:-}" != "Y" ]] && [[ "${TELEGRAM_ENABLED:-}" != "true" ]]; then
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

# ===== 显示恢复方式选择 =====
select_restore_method() {
    echo ""
    log_info "${CYAN}选择恢复方式${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${GREEN}1)${NC} 📁 本地恢复 - 从本地备份目录恢复"
    echo -e "  ${GREEN}2)${NC} 🌐 远程恢复 - 从远程服务器下载并恢复"
    echo -e "  ${RED}0)${NC} 返回"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "请选择 [0-2]: " choice
    echo "$choice"
}

# ===== 列出本地快照 =====
list_local_snapshots() {
    local snapshot_dir="${BACKUP_DIR:-/backups}/system_snapshots"
    
    if [[ ! -d "$snapshot_dir" ]]; then
        log_error "本地快照目录不存在: $snapshot_dir"
        return 1
    fi
    
    # 查找所有快照文件
    local snapshots=($(find "$snapshot_dir" -name "system_snapshot_*.tar*" -type f 2>/dev/null | sort -r))
    
    if [[ ${#snapshots[@]} -eq 0 ]]; then
        log_error "未找到本地快照文件"
        return 1
    fi
    
    echo ""
    log_info "${CYAN}可用本地快照:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    for i in "${!snapshots[@]}"; do
        local file="${snapshots[$i]}"
        local name=$(basename "$file")
        local size=$(format_bytes "$(stat -c%s "$file" 2>/dev/null || echo 0)")
        local date=$(date -r "$file" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "未知")
        local has_checksum="  "
        
        if [[ -f "${file}.sha256" ]]; then
            has_checksum="${GREEN}✓${NC}"
        fi
        
        echo -e "  $((i+1))) ${GREEN}$name${NC}"
        echo -e "      大小: $size | 时间: $date | 校验: $has_checksum"
    done
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "选择快照编号 [1-${#snapshots[@]}] 或 0 取消: " choice
    
    if [[ "$choice" == "0" ]]; then
        return 1
    fi
    
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 )) || (( choice > ${#snapshots[@]} )); then
        log_error "无效选择"
        return 1
    fi
    
    echo "${snapshots[$((choice-1))]}"
}

# ===== 列出远程快照 =====
list_remote_snapshots() {
    if [[ -z "${REMOTE_HOST:-}" ]]; then
        log_error "未配置远程服务器"
        return 1
    fi
    
    log_info "连接远程服务器: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT}"
    
    local ssh_key="/root/.ssh/id_ed25519"
    local ssh_opts="-o ConnectTimeout=30 -o StrictHostKeyChecking=no"
    
    # SSH 连接测试
    if ! ssh -i "$ssh_key" -p "$REMOTE_PORT" $ssh_opts \
            "${REMOTE_USER}@${REMOTE_HOST}" "echo 'test'" &>/dev/null; then
        log_error "无法连接到远程服务器"
        return 1
    fi
    
    # 获取远程快照列表
    local snapshot_list
    snapshot_list=$(ssh -i "$ssh_key" -p "$REMOTE_PORT" $ssh_opts \
        "${REMOTE_USER}@${REMOTE_HOST}" \
        "find '${REMOTE_PATH}/system_snapshots' -name 'system_snapshot_*.tar*' -type f 2>/dev/null | sort -r" || echo "")
    
    if [[ -z "$snapshot_list" ]]; then
        log_error "远程未找到快照文件"
        return 1
    fi
    
    local -a snapshots
    while IFS= read -r line; do
        snapshots+=("$line")
    done <<< "$snapshot_list"
    
    echo ""
    log_info "${CYAN}可用远程快照:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    for i in "${!snapshots[@]}"; do
        local file="${snapshots[$i]}"
        local name=$(basename "$file")
        
        # 获取远程文件信息
        local file_info=$(ssh -i "$ssh_key" -p "$REMOTE_PORT" $ssh_opts \
            "${REMOTE_USER}@${REMOTE_HOST}" \
            "stat -c '%s %Y' '$file' 2>/dev/null" || echo "0 0")
        
        local size=$(format_bytes "$(echo "$file_info" | awk '{print $1}')")
        local timestamp=$(echo "$file_info" | awk '{print $2}')
        local date="未知"
        
        if [[ "$timestamp" != "0" ]]; then
            date=$(date -d "@$timestamp" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "未知")
        fi
        
        echo -e "  $((i+1))) ${GREEN}$name${NC}"
        echo -e "      大小: $size | 时间: $date"
    done
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "选择快照编号 [1-${#snapshots[@]}] 或 0 取消: " choice
    
    if [[ "$choice" == "0" ]]; then
        return 1
    fi
    
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 )) || (( choice > ${#snapshots[@]} )); then
        log_error "无效选择"
        return 1
    fi
    
    echo "${snapshots[$((choice-1))]}"
}

# ===== 下载远程快照 =====
download_remote_snapshot() {
    local remote_file="$1"
    local temp_dir="/tmp/snapsync_restore_$$"
    local snapshot_name=$(basename "$remote_file")
    local local_file="$temp_dir/$snapshot_name"
    
    mkdir -p "$temp_dir"
    
    log_info "下载远程快照: $snapshot_name"
    
    local ssh_key="/root/.ssh/id_ed25519"
    local ssh_opts="-o ConnectTimeout=30 -o StrictHostKeyChecking=no"
    
    # 使用 rsync 下载（支持断点续传）
    if rsync -avz --partial --progress \
            -e "ssh -i $ssh_key -p $REMOTE_PORT $ssh_opts" \
            "${REMOTE_USER}@${REMOTE_HOST}:${remote_file}" \
            "$local_file" 2>&1 | tee -a "$LOG_FILE"; then
        
        log_success "下载完成"
        
        # 下载校验和文件
        rsync -az -e "ssh -i $ssh_key -p $REMOTE_PORT $ssh_opts" \
            "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/checksums/${snapshot_name}.sha256" \
            "${local_file}.sha256" 2>/dev/null || true
        
        echo "$local_file"
        return 0
    else
        log_error "下载失败"
        rm -rf "$temp_dir"
        return 1
    fi
}

# ===== 验证快照完整性 =====
verify_snapshot() {
    local snapshot_file="$1"
    
    if [[ ! -f "$snapshot_file" ]]; then
        log_error "快照文件不存在"
        return 1
    fi
    
    local checksum_file="${snapshot_file}.sha256"
    
    if [[ ! -f "$checksum_file" ]]; then
        log_warning "未找到校验和文件，跳过验证"
        return 0
    fi
    
    log_info "验证快照完整性..."
    
    if (cd "$(dirname "$snapshot_file")" && sha256sum -c "$(basename "$checksum_file")" &>/dev/null); then
        log_success "完整性验证通过"
        return 0
    else
        log_error "完整性验证失败"
        return 1
    fi
}

# ===== 备份关键配置 =====
backup_critical_configs() {
    local backup_dir="/tmp/snapsync_config_backup_$$"
    mkdir -p "$backup_dir"
    
    log_info "备份关键配置文件..."
    
    # 网络配置
    cp -r /etc/network "$backup_dir/" 2>/dev/null || true
    cp -r /etc/netplan "$backup_dir/" 2>/dev/null || true
    cp /etc/resolv.conf "$backup_dir/" 2>/dev/null || true
    
    # SSH 配置
    cp -r /etc/ssh "$backup_dir/" 2>/dev/null || true
    cp -r /root/.ssh "$backup_dir/root_ssh" 2>/dev/null || true
    
    # 主机配置
    cp /etc/hostname "$backup_dir/" 2>/dev/null || true
    cp /etc/hosts "$backup_dir/" 2>/dev/null || true
    
    # fstab
    cp /etc/fstab "$backup_dir/" 2>/dev/null || true
    
    log_success "关键配置已备份到: $backup_dir"
    echo "$backup_dir"
}

# ===== 恢复关键配置 =====
restore_critical_configs() {
    local backup_dir="$1"
    
    if [[ ! -d "$backup_dir" ]]; then
        return 0
    fi
    
    log_info "恢复关键配置文件..."
    
    # 网络配置
    [[ -d "$backup_dir/network" ]] && cp -r "$backup_dir/network" /etc/ 2>/dev/null || true
    [[ -d "$backup_dir/netplan" ]] && cp -r "$backup_dir/netplan" /etc/ 2>/dev/null || true
    [[ -f "$backup_dir/resolv.conf" ]] && cp "$backup_dir/resolv.conf" /etc/ 2>/dev/null || true
    
    # SSH 配置
    [[ -d "$backup_dir/ssh" ]] && cp -r "$backup_dir/ssh" /etc/ 2>/dev/null || true
    [[ -d "$backup_dir/root_ssh" ]] && cp -r "$backup_dir/root_ssh" /root/.ssh 2>/dev/null || true
    
    # 主机配置
    [[ -f "$backup_dir/hostname" ]] && cp "$backup_dir/hostname" /etc/ 2>/dev/null || true
    [[ -f "$backup_dir/hosts" ]] && cp "$backup_dir/hosts" /etc/ 2>/dev/null || true
    
    # fstab
    [[ -f "$backup_dir/fstab" ]] && cp "$backup_dir/fstab" /etc/ 2>/dev/null || true
    
    # 修复权限
    chmod 700 /root/.ssh 2>/dev/null || true
    chmod 600 /root/.ssh/* 2>/dev/null || true
    
    log_success "关键配置已恢复"
}

# ===== 停止关键服务 =====
stop_critical_services() {
    log_info "停止关键服务..."
    
    local services=("nginx" "apache2" "mysql" "mariadb" "postgresql" "docker")
    
    for service in "${services[@]}"; do
        if systemctl is-active "$service" &>/dev/null; then
            log_info "  停止 $service"
            systemctl stop "$service" 2>/dev/null || true
        fi
    done
}

# ===== 执行恢复 =====
perform_restore() {
    local snapshot_file="$1"
    local restore_mode="$2"
    
    if [[ ! -f "$snapshot_file" ]]; then
        log_error "快照文件不存在: $snapshot_file"
        return 1
    fi
    
    local snapshot_name=$(basename "$snapshot_file")
    local snapshot_size=$(format_bytes "$(stat -c%s "$snapshot_file" 2>/dev/null || echo 0)")
    
    log_info "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "${CYAN}开始无损系统恢复${NC}"
    log_info "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "快照: $snapshot_name"
    log_info "大小: $snapshot_size"
    log_info "模式: $restore_mode"
    
    send_telegram "🔄 <b>开始恢复</b>

📸 快照: ${snapshot_name}
📦 大小: ${snapshot_size}
🔧 模式: ${restore_mode}
🖥️ 主机: $(hostname)
⏰ 时间: $(date '+%F %T')"
    
    # 验证快照
    if ! verify_snapshot "$snapshot_file"; then
        read -p "完整性验证失败，是否继续? [y/N]: " continue_restore
        if [[ ! "$continue_restore" =~ ^[Yy]$ ]]; then
            log_error "恢复已取消"
            return 1
        fi
    fi
    
    # 备份关键配置（智能恢复模式）
    local config_backup_dir=""
    if [[ "$restore_mode" == "智能恢复" ]]; then
        config_backup_dir=$(backup_critical_configs)
    fi
    
    # 停止服务
    stop_critical_services
    
    # 检测压缩格式
    local decompress_cmd="cat"
    if [[ "$snapshot_file" =~ \.gz$ ]]; then
        if command -v pigz &>/dev/null; then
            decompress_cmd="pigz -dc"
        else
            decompress_cmd="gunzip -c"
        fi
    elif [[ "$snapshot_file" =~ \.bz2$ ]]; then
        decompress_cmd="bunzip2 -c"
    elif [[ "$snapshot_file" =~ \.xz$ ]]; then
        decompress_cmd="xz -dc"
    fi
    
    # 构建 tar 参数
    local tar_opts=(
        "--extract"
        "--file=-"
        "--preserve-permissions"
        "--same-owner"
        "--numeric-owner"
    )
    
    # 启用 ACL 恢复
    if command -v setfacl &>/dev/null; then
        tar_opts+=("--acls")
        log_info "✓ 启用 ACL 恢复"
    fi
    
    # 启用扩展属性恢复
    if command -v setfattr &>/dev/null; then
        tar_opts+=("--xattrs" "--xattrs-include=*")
        log_info "✓ 启用扩展属性恢复"
    fi
    
    # 启用 SELinux 上下文恢复
    if [[ -f /etc/selinux/config ]] && command -v restorecon &>/dev/null; then
        tar_opts+=("--selinux")
        log_info "✓ 启用 SELinux 上下文恢复"
    fi
    
    # 排除列表
    tar_opts+=(
        "--exclude=dev/*"
        "--exclude=proc/*"
        "--exclude=sys/*"
        "--exclude=run/*"
        "--exclude=tmp/*"
        "--exclude=${BACKUP_DIR:-/backups}/*"
    )
    
    log_info "开始解压恢复..."
    
    local start_time=$(date +%s)
    
    # 执行恢复
    cd / && {
        if $decompress_cmd "$snapshot_file" | tar "${tar_opts[@]}" 2>/tmp/restore_stderr.log; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            
            log_success "系统恢复完成"
            log_info "耗时: ${duration} 秒"
            
            # 恢复关键配置
            if [[ -n "$config_backup_dir" ]]; then
                restore_critical_configs "$config_backup_dir"
                rm -rf "$config_backup_dir"
            fi
            
            send_telegram "✅ <b>恢复完成</b>

⏱️ 耗时: ${duration} 秒
🔧 模式: ${restore_mode}
⚠️ 建议重启系统"
            
            return 0
        else
            local exit_code=$?
            log_error "恢复失败 (退出码: $exit_code)"
            
            if [[ -f /tmp/restore_stderr.log ]]; then
                log_error "错误详情: $(cat /tmp/restore_stderr.log)"
            fi
            
            # 尝试恢复配置
            if [[ -n "$config_backup_dir" ]]; then
                restore_critical_configs "$config_backup_dir"
                rm -rf "$config_backup_dir"
            fi
            
            send_telegram "❌ <b>恢复失败</b>

请检查日志文件获取详细信息"
            
            return 1
        fi
    }
}

# ===== 主程序 =====
main() {
    log_info "========================================="
    log_info "SnapSync v3.0 无损恢复"
    log_info "========================================="
    
    # 选择恢复方式
    local method=$(select_restore_method)
    
    if [[ "$method" == "0" ]]; then
        log_info "恢复已取消"
        return 0
    fi
    
    local snapshot_file=""
    local temp_dir=""
    
    # 根据选择获取快照
    if [[ "$method" == "1" ]]; then
        snapshot_file=$(list_local_snapshots)
        if [[ -z "$snapshot_file" ]]; then
            log_error "未选择快照"
            return 1
        fi
    elif [[ "$method" == "2" ]]; then
        local remote_file=$(list_remote_snapshots)
        if [[ -z "$remote_file" ]]; then
            log_error "未选择快照"
            return 1
        fi
        
        snapshot_file=$(download_remote_snapshot "$remote_file")
        if [[ -z "$snapshot_file" ]]; then
            log_error "下载失败"
            return 1
        fi
        temp_dir=$(dirname "$snapshot_file")
    fi
    
    # 选择恢复模式
    echo ""
    log_info "${CYAN}选择恢复模式${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${GREEN}1)${NC} 🛡️ 智能恢复 - 保留网络、SSH 配置（${GREEN}推荐${NC}）"
    echo -e "  ${GREEN}2)${NC} 🔧 完全恢复 - 恢复所有内容（${RED}谨慎${NC}）"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "请选择 [1-2]: " mode_choice
    
    local restore_mode="智能恢复"
    if [[ "$mode_choice" == "2" ]]; then
        restore_mode="完全恢复"
    fi
    
    # 最终确认
    echo ""
    log_warning "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_warning "${RED}警告: 恢复操作不可撤销！${NC}"
    log_warning "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "确认执行恢复? 输入 'YES' 继续: " final_confirm
    
    if [[ "$final_confirm" != "YES" ]]; then
        log_info "恢复已取消"
        [[ -n "$temp_dir" ]] && rm -rf "$temp_dir"
        return 0
    fi
    
    # 执行恢复
    if perform_restore "$snapshot_file" "$restore_mode"; then
        log_success "========================================="
        log_success "系统恢复完成！"
        log_success "========================================="
        
        echo ""
        log_warning "${YELLOW}建议立即重启系统以确保所有更改生效${NC}"
        echo ""
        
        read -p "是否立即重启? [y/N]: " do_reboot
        if [[ "$do_reboot" =~ ^[Yy]$ ]]; then
            log_info "系统将在 10 秒后重启..."
            sleep 10
            reboot
        fi
    else
        log_error "恢复失败，请检查日志"
    fi
    
    # 清理临时文件
    [[ -n "$temp_dir" ]] && rm -rf "$temp_dir"
}

# 运行主程序
main "$@"
