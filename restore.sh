#!/bin/bash

# SnapSync v3.0 - 无损恢复模块（已修复）
# 修复: 移除readonly冲突

set -euo pipefail

# ===== 路径定义（不使用readonly）=====
CONFIG_FILE="/etc/snapsync/config.conf"
LOG_FILE="/var/log/snapsync/restore.log"

# ===== 颜色 =====
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

log_warning() {
    echo -e "$(date '+%F %T') ${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

send_telegram() {
    [[ "${TELEGRAM_ENABLED:-}" != "Y" && "${TELEGRAM_ENABLED:-}" != "true" ]] && return 0
    [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]] && return 0
    
    curl -sS -m 15 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=$1" \
        -d "parse_mode=HTML" &>/dev/null || true
}

format_bytes() {
    local bytes="$1"
    [[ ! "$bytes" =~ ^[0-9]+$ ]] && echo "0B" && return
    
    if (( bytes >= 1073741824 )); then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1073741824}")GB"
    elif (( bytes >= 1048576 )); then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1048576}")MB"
    else
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1024}")KB"
    fi
}

# ===== 加载配置 =====
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        BACKUP_DIR="${BACKUP_DIR:-/backups}"
    else
        BACKUP_DIR="/backups"
        TELEGRAM_ENABLED="false"
    fi
}

# ===== 选择恢复方式 =====
select_restore_method() {
    echo ""
    log_info "${CYAN}选择恢复方式${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${GREEN}1)${NC} 📁 本地恢复"
    echo -e "  ${GREEN}2)${NC} 🌐 远程恢复"
    echo -e "  ${RED}0)${NC} 返回"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "请选择 [0-2]: " choice
    echo "$choice"
}

# ===== 列出本地快照 =====
list_local_snapshots() {
    local snapshot_dir="${BACKUP_DIR}/system_snapshots"
    
    [[ ! -d "$snapshot_dir" ]] && log_error "快照目录不存在" && return 1
    
    local snapshots=($(find "$snapshot_dir" -name "*.tar*" -type f 2>/dev/null | sort -r))
    
    [[ ${#snapshots[@]} -eq 0 ]] && log_error "未找到快照" && return 1
    
    echo ""
    log_info "${CYAN}可用本地快照:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    for i in "${!snapshots[@]}"; do
        local file="${snapshots[$i]}"
        local name=$(basename "$file")
        local size=$(format_bytes "$(stat -c%s "$file" 2>/dev/null || echo 0)")
        local date=$(date -r "$file" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "未知")
        
        echo -e "  $((i+1))) ${GREEN}$name${NC}"
        echo -e "      大小: $size | 时间: $date"
    done
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "选择快照 [1-${#snapshots[@]}] 或 0 取消: " choice
    
    [[ "$choice" == "0" ]] && return 1
    [[ ! "$choice" =~ ^[0-9]+$ ]] && log_error "无效选择" && return 1
    (( choice < 1 || choice > ${#snapshots[@]} )) && log_error "无效选择" && return 1
    
    echo "${snapshots[$((choice-1))]}"
}

# ===== 验证快照 =====
verify_snapshot() {
    local snapshot_file="$1"
    
    [[ ! -f "$snapshot_file" ]] && log_error "快照不存在" && return 1
    
    local checksum_file="${snapshot_file}.sha256"
    
    if [[ ! -f "$checksum_file" ]]; then
        log_warning "未找到校验和文件"
        return 0
    fi
    
    log_info "验证完整性..."
    
    if (cd "$(dirname "$snapshot_file")" && sha256sum -c "$(basename "$checksum_file")" &>/dev/null); then
        log_success "验证通过"
        return 0
    else
        log_error "验证失败"
        return 1
    fi
}

# ===== 备份关键配置 =====
backup_critical_configs() {
    local backup_dir="/tmp/snapsync_config_$$"
    mkdir -p "$backup_dir"
    
    log_info "备份关键配置..."
    
    # 网络
    cp -r /etc/network "$backup_dir/" 2>/dev/null || true
    cp -r /etc/netplan "$backup_dir/" 2>/dev/null || true
    cp /etc/resolv.conf "$backup_dir/" 2>/dev/null || true
    
    # SSH
    cp -r /etc/ssh "$backup_dir/" 2>/dev/null || true
    cp -r /root/.ssh "$backup_dir/root_ssh" 2>/dev/null || true
    
    # 主机
    cp /etc/hostname "$backup_dir/" 2>/dev/null || true
    cp /etc/hosts "$backup_dir/" 2>/dev/null || true
    cp /etc/fstab "$backup_dir/" 2>/dev/null || true
    
    log_success "配置已备份"
    echo "$backup_dir"
}

# ===== 恢复关键配置 =====
restore_critical_configs() {
    local backup_dir="$1"
    
    [[ ! -d "$backup_dir" ]] && return 0
    
    log_info "恢复关键配置..."
    
    # 网络
    [[ -d "$backup_dir/network" ]] && cp -r "$backup_dir/network" /etc/ 2>/dev/null || true
    [[ -d "$backup_dir/netplan" ]] && cp -r "$backup_dir/netplan" /etc/ 2>/dev/null || true
    [[ -f "$backup_dir/resolv.conf" ]] && cp "$backup_dir/resolv.conf" /etc/ 2>/dev/null || true
    
    # SSH
    [[ -d "$backup_dir/ssh" ]] && cp -r "$backup_dir/ssh" /etc/ 2>/dev/null || true
    [[ -d "$backup_dir/root_ssh" ]] && cp -r "$backup_dir/root_ssh" /root/.ssh 2>/dev/null || true
    
    # 主机
    [[ -f "$backup_dir/hostname" ]] && cp "$backup_dir/hostname" /etc/ 2>/dev/null || true
    [[ -f "$backup_dir/hosts" ]] && cp "$backup_dir/hosts" /etc/ 2>/dev/null || true
    [[ -f "$backup_dir/fstab" ]] && cp "$backup_dir/fstab" /etc/ 2>/dev/null || true
    
    chmod 700 /root/.ssh 2>/dev/null || true
    chmod 600 /root/.ssh/* 2>/dev/null || true
    
    log_success "配置已恢复"
}

# ===== 执行恢复 =====
perform_restore() {
    local snapshot_file="$1"
    local restore_mode="$2"
    
    [[ ! -f "$snapshot_file" ]] && log_error "快照不存在" && return 1
    
    local snapshot_name=$(basename "$snapshot_file")
    local size=$(format_bytes "$(stat -c%s "$snapshot_file" 2>/dev/null || echo 0)")
    
    log_info "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "${CYAN}开始系统恢复${NC}"
    log_info "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "快照: $snapshot_name"
    log_info "模式: $restore_mode"
    
    send_telegram "🔄 <b>开始恢复</b>

📸 快照: ${snapshot_name}
🔧 模式: ${restore_mode}"
    
    # 验证
    if ! verify_snapshot "$snapshot_file"; then
        read -p "验证失败，是否继续? [y/N]: " continue_restore
        [[ ! "$continue_restore" =~ ^[Yy]$ ]] && log_error "已取消" && return 1
    fi
    
    # 备份配置（智能模式）
    local config_backup_dir=""
    [[ "$restore_mode" == "智能恢复" ]] && config_backup_dir=$(backup_critical_configs)
    
    # 检测压缩
    local decompress_cmd="cat"
    if [[ "$snapshot_file" =~ \.gz$ ]]; then
        decompress_cmd=$(command -v pigz &>/dev/null && echo "pigz -dc" || echo "gunzip -c")
    elif [[ "$snapshot_file" =~ \.bz2$ ]]; then
        decompress_cmd="bunzip2 -c"
    elif [[ "$snapshot_file" =~ \.xz$ ]]; then
        decompress_cmd="xz -dc"
    fi
    
    # tar参数
    local tar_opts=(
        "--extract" "--file=-"
        "--preserve-permissions"
        "--same-owner"
        "--numeric-owner"
    )
    
    command -v setfacl &>/dev/null && tar_opts+=("--acls")
    command -v setfattr &>/dev/null && tar_opts+=("--xattrs" "--xattrs-include=*")
    [[ -f /etc/selinux/config ]] && tar_opts+=("--selinux")
    
    tar_opts+=(
        "--exclude=dev/*"
        "--exclude=proc/*"
        "--exclude=sys/*"
        "--exclude=run/*"
        "--exclude=tmp/*"
    )
    
    log_info "开始解压..."
    
    local start_time=$(date +%s)
    
    # 执行恢复
    cd / && {
        if $decompress_cmd "$snapshot_file" | tar "${tar_opts[@]}" 2>/tmp/restore_err.log; then
            local duration=$(($(date +%s) - start_time))
            
            log_success "恢复完成"
            log_info "耗时: ${duration}秒"
            
            # 恢复配置
            [[ -n "$config_backup_dir" ]] && restore_critical_configs "$config_backup_dir"
            [[ -n "$config_backup_dir" ]] && rm -rf "$config_backup_dir"
            
            send_telegram "✅ <b>恢复完成</b>

⏱️ 耗时: ${duration}秒
⚠️ 建议重启"
            
            return 0
        else
            log_error "恢复失败: $(cat /tmp/restore_err.log 2>/dev/null)"
            [[ -n "$config_backup_dir" ]] && restore_critical_configs "$config_backup_dir"
            [[ -n "$config_backup_dir" ]] && rm -rf "$config_backup_dir"
            return 1
        fi
    }
}

# ===== 主程序 =====
main() {
    log_info "========================================"
    log_info "SnapSync v3.0 系统恢复"
    log_info "========================================"
    
    load_config
    
    # 选择方式
    local method=$(select_restore_method)
    
    [[ "$method" == "0" ]] && log_info "已取消" && return 0
    
    local snapshot_file=""
    
    # 获取快照
    if [[ "$method" == "1" ]]; then
        snapshot_file=$(list_local_snapshots)
        [[ -z "$snapshot_file" ]] && log_error "未选择快照" && return 1
    else
        log_error "远程恢复暂未实现"
        return 1
    fi
    
    # 选择模式
    echo ""
    log_info "${CYAN}选择恢复模式${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${GREEN}1)${NC} 🛡️ 智能恢复（推荐）"
    echo -e "  ${GREEN}2)${NC} 🔧 完全恢复"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "选择 [1-2]: " mode_choice
    
    local restore_mode="智能恢复"
    [[ "$mode_choice" == "2" ]] && restore_mode="完全恢复"
    
    # 确认
    echo ""
    log_warning "${RED}警告: 恢复不可撤销！${NC}"
    echo ""
    
    read -p "确认恢复? 输入 'YES': " final_confirm
    
    [[ "$final_confirm" != "YES" ]] && log_info "已取消" && return 0
    
    # 执行
    if perform_restore "$snapshot_file" "$restore_mode"; then
        log_success "========================================"
        log_success "系统恢复完成！"
        log_success "========================================"
        
        echo ""
        log_warning "${YELLOW}建议重启系统${NC}"
        echo ""
        
        read -p "是否重启? [y/N]: " do_reboot
        [[ "$do_reboot" =~ ^[Yy]$ ]] && { log_info "重启中..."; sleep 3; reboot; }
    else
        log_error "恢复失败"
    fi
}

main "$@"
