#!/bin/bash

# SnapSync v3.0 - 恢复模块（完整修复版）
# 重点修复：远程快照下载和恢复逻辑

set -euo pipefail

# ===== 路径定义 =====
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
    echo -e "$(date '+%F %T') [INFO] $1" | tee -a "$LOG_FILE" >&2
}

log_error() {
    echo -e "$(date '+%F %T') ${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE" >&2
}

log_success() {
    echo -e "$(date '+%F %T') ${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE" >&2
}

log_warning() {
    echo -e "$(date '+%F %T') ${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE" >&2
}

send_telegram() {
    local tg_enabled=$(echo "${TELEGRAM_ENABLED:-false}" | tr '[:upper:]' '[:lower:]')
    [[ "$tg_enabled" != "y" && "$tg_enabled" != "yes" && "$tg_enabled" != "true" ]] && return 0
    [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]] && return 0
    
    local hostname="${HOSTNAME:-$(hostname)}"
    local message="🖥️ <b>${hostname}</b>
━━━━━━━━━━━━━━━━━━━━━━━
$1"
    
    curl -sS -m 15 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${message}" \
        -d "parse_mode=HTML" &>/dev/null || true
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

# ===== 加载配置 =====
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        BACKUP_DIR="${BACKUP_DIR:-/backups}"
        log_info "配置已加载: 备份目录 = $BACKUP_DIR"
    else
        BACKUP_DIR="/backups"
        log_warning "配置文件不存在，使用默认: $BACKUP_DIR"
    fi
}

# ===== 列出远程快照（修复版）=====
list_remote_snapshots() {
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
    
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "连接远程服务器: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT}" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    
    # 测试连接
    if ! ssh -i "$ssh_key" -p "$REMOTE_PORT" "${ssh_opts[@]}" \
            "${REMOTE_USER}@${REMOTE_HOST}" "echo ok" &>/dev/null; then
        echo "${RED}错误: 无法连接远程服务器${NC}" >&2
        echo "" >&2
        echo "可能的原因：" >&2
        echo "  1. SSH 密钥未配置或未添加到远程服务器" >&2
        echo "  2. 远程服务器不可达" >&2
        echo "  3. 防火墙阻止" >&2
        echo "" >&2
        echo "解决方法：" >&2
        echo "  运行: sudo snapsync" >&2
        echo "  选择: 3) 配置管理 -> 1) 修改远程服务器配置" >&2
        echo "" >&2
        echo "测试命令:" >&2
        echo "  ssh -i $ssh_key -p $REMOTE_PORT ${REMOTE_USER}@${REMOTE_HOST}" >&2
        return 1
    fi
    
    echo "正在读取远程快照..." >&2
    echo "" >&2
    
    # 获取远程快照列表
    local remote_list=$(ssh -i "$ssh_key" -p "$REMOTE_PORT" "${ssh_opts[@]}" \
        "${REMOTE_USER}@${REMOTE_HOST}" \
        "find '${REMOTE_PATH}/system_snapshots' -name 'system_snapshot_*.tar*' -type f 2>/dev/null | grep -v '\.sha256$' | sort -r" 2>/dev/null)
    
    if [[ -z "$remote_list" ]]; then
        echo "未找到远程快照" >&2
        return 1
    fi
    
    # 转换为数组
    local snapshots=()
    while IFS= read -r file; do
        [[ -n "$file" ]] && snapshots+=("$file")
    done <<< "$remote_list"
    
    if [[ ${#snapshots[@]} -eq 0 ]]; then
        echo "未找到快照文件" >&2
        return 1
    fi
    
    # 显示列表
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "找到 ${#snapshots[@]} 个远程快照" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    
    local idx=1
    for file in "${snapshots[@]}"; do
        local name=$(basename "$file")
        
        # 获取远程文件信息
        local file_info=$(ssh -i "$ssh_key" -p "$REMOTE_PORT" "${ssh_opts[@]}" \
            "${REMOTE_USER}@${REMOTE_HOST}" \
            "stat -c '%s %Y' '$file' 2>/dev/null" || echo "0 0")
        
        local size_bytes=$(echo "$file_info" | awk '{print $1}')
        local timestamp=$(echo "$file_info" | awk '{print $2}')
        
        local size=$(format_bytes "$size_bytes")
        local date=$(date -d "@$timestamp" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "未知")
        
        echo "${idx}) ${name}" >&2
        echo "   大小: ${size}" >&2
        echo "   时间: ${date}" >&2
        echo "   位置: 远程服务器" >&2
        echo "" >&2
        
        ((idx++))
    done
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    
    # 选择快照
    local choice
    while true; do
        read -p "选择快照 [1-${#snapshots[@]}] 或 0 取消: " choice >&2
        
        if [[ "$choice" == "0" ]]; then
            echo "已取消" >&2
            return 1
        fi
        
        if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
            echo "请输入有效数字！" >&2
            continue
        fi
        
        if (( choice < 1 || choice > ${#snapshots[@]} )); then
            echo "选择超出范围 (1-${#snapshots[@]})" >&2
            continue
        fi
        
        break
    done
    
    local selected="${snapshots[$((choice-1))]}"
    echo "已选择: $(basename "$selected")" >&2
    echo "" >&2
    
    # 输出选中的文件路径到 stdout
    echo "$selected"
    return 0
}

# ===== 下载远程快照（修复版）=====
download_remote_snapshot() {
    local remote_file="$1"
    local local_dir="${BACKUP_DIR}/system_snapshots"
    
    mkdir -p "$local_dir"
    
    local filename=$(basename "$remote_file")
    local local_file="${local_dir}/${filename}"
    
    log_info "准备下载快照..."
    echo ""
    echo -e "${YELLOW}下载信息:${NC}" >&2
    echo "  远程文件: $remote_file" >&2
    echo "  本地路径: $local_file" >&2
    echo "" >&2
    
    # 检查本地是否已存在
    if [[ -f "$local_file" ]]; then
        echo -e "${YELLOW}⚠ 本地已存在同名文件${NC}" >&2
        read -p "是否覆盖? [y/N]: " overwrite >&2
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            log_info "使用现有本地文件"
            echo "$local_file"
            return 0
        fi
    fi
    
    send_telegram "⬇️ <b>开始下载远程快照</b>

📦 文件: ${filename}
🌐 服务器: ${REMOTE_HOST}

下载进行中..."
    
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
    
    log_info "开始下载..."
    local download_start=$(date +%s)
    
    # 构建 rsync SSH 命令
    local rsync_ssh_cmd="ssh -i $ssh_key -p $REMOTE_PORT"
    for opt in "${ssh_opts[@]}"; do
        rsync_ssh_cmd="$rsync_ssh_cmd $opt"
    done
    
    # 使用 rsync 下载（支持断点续传）
    if rsync -avz --partial --progress \
            -e "$rsync_ssh_cmd" \
            "${REMOTE_USER}@${REMOTE_HOST}:${remote_file}" \
            "$local_file" 2>&1 | tee -a "$LOG_FILE" >&2; then
        
        local download_duration=$(($(date +%s) - download_start))
        local file_size=$(stat -c%s "$local_file" 2>/dev/null || echo 0)
        local size_human=$(format_bytes "$file_size")
        
        local download_speed="N/A"
        if (( download_duration > 0 )); then
            local speed_bps=$((file_size / download_duration))
            download_speed=$(format_bytes "$speed_bps")/s
        fi
        
        log_success "下载完成"
        log_info "  大小: $size_human"
        log_info "  耗时: ${download_duration}秒"
        log_info "  速度: $download_speed"
        
        # 下载校验文件
        if ssh -i "$ssh_key" -p "$REMOTE_PORT" "${ssh_opts[@]}" \
                "${REMOTE_USER}@${REMOTE_HOST}" \
                "test -f '${remote_file}.sha256'" 2>/dev/null; then
            log_info "下载校验文件..."
            rsync -az -e "$rsync_ssh_cmd" \
                "${REMOTE_USER}@${REMOTE_HOST}:${remote_file}.sha256" \
                "${local_file}.sha256" 2>&1 | tee -a "$LOG_FILE" >&2 || true
        fi
        
        send_telegram "✅ <b>下载完成</b>

📦 文件: ${filename}
📊 大小: ${size_human}
⏱️ 耗时: ${download_duration}秒
⚡ 速度: ${download_speed}

快照已下载到本地"
        
        echo ""
        echo "$local_file"
        return 0
    else
        log_error "下载失败"
        
        send_telegram "❌ <b>下载失败</b>

📦 文件: ${filename}
🌐 服务器: ${REMOTE_HOST}

请检查网络连接和远程服务器状态"
        
        return 1
    fi
}

# ===== 列出本地快照 =====
list_local_snapshots() {
    local snapshot_dir="${BACKUP_DIR}/system_snapshots"
    
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "扫描快照目录: $snapshot_dir" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    
    if [[ ! -d "$snapshot_dir" ]]; then
        echo "错误: 目录不存在" >&2
        return 1
    fi
    
    echo "正在读取快照文件..." >&2
    echo "" >&2
    
    local snapshots=()
    while IFS= read -r -d '' file; do
        if [[ "$file" != *.sha256 ]]; then
            snapshots+=("$file")
        fi
    done < <(find "$snapshot_dir" -maxdepth 1 -name "system_snapshot_*.tar*" -type f -print0 2>/dev/null | sort -zr)
    
    if [[ ${#snapshots[@]} -eq 0 ]]; then
        echo "未找到快照文件" >&2
        return 1
    fi
    
    # 显示列表
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "找到 ${#snapshots[@]} 个本地快照" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    
    local idx=1
    for file in "${snapshots[@]}"; do
        local name=$(basename "$file")
        local size_bytes=$(stat -c%s "$file" 2>/dev/null || echo 0)
        local size=$(format_bytes "$size_bytes")
        local date=$(date -r "$file" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "未知")
        
        echo "${idx}) ${name}" >&2
        echo "   大小: ${size}" >&2
        echo "   时间: ${date}" >&2
        
        if [[ -f "${file}.sha256" ]]; then
            echo "   状态: ✓ 已校验" >&2
        else
            echo "   状态: ⚠ 无校验" >&2
        fi
        echo "" >&2
        
        ((idx++))
    done
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    
    # 选择快照
    local choice
    while true; do
        read -p "选择快照 [1-${#snapshots[@]}] 或 0 取消: " choice >&2
        
        if [[ "$choice" == "0" ]]; then
            echo "已取消" >&2
            return 1
        fi
        
        if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
            echo "请输入有效数字！" >&2
            continue
        fi
        
        if (( choice < 1 || choice > ${#snapshots[@]} )); then
            echo "选择超出范围 (1-${#snapshots[@]})" >&2
            continue
        fi
        
        break
    done
    
    local selected="${snapshots[$((choice-1))]}"
    echo "已选择: $(basename "$selected")" >&2
    echo "" >&2
    
    echo "$selected"
    return 0
}

# ===== 验证快照 =====
verify_snapshot() {
    local snapshot_file="$1"
    
    [[ ! -f "$snapshot_file" ]] && log_error "快照不存在" && return 1
    
    local checksum_file="${snapshot_file}.sha256"
    
    if [[ ! -f "$checksum_file" ]]; then
        log_warning "未找到校验文件"
        echo "" >&2
        echo -e "${YELLOW}⚠ 警告: 未找到校验和文件${NC}" >&2
        echo "无法验证快照完整性" >&2
        echo "" >&2
        return 0
    fi
    
    log_info "验证快照完整性..."
    echo -e "${CYAN}正在验证...${NC}" >&2
    
    local snapshot_dir=$(dirname "$snapshot_file")
    local snapshot_name=$(basename "$snapshot_file")
    local checksum_name=$(basename "$checksum_file")
    
    if (cd "$snapshot_dir" && sha256sum -c "$checksum_name" &>/dev/null); then
        log_success "验证通过"
        echo -e "${GREEN}✓ 快照完整性验证通过${NC}" >&2
        echo "" >&2
        return 0
    else
        log_error "验证失败"
        echo -e "${RED}✗ 快照完整性验证失败${NC}" >&2
        echo "快照文件可能已损坏" >&2
        echo "" >&2
        return 1
    fi
}

# ===== 备份关键配置 =====
backup_critical_configs() {
    local backup_dir="/tmp/snapsync_config_$$"
    mkdir -p "$backup_dir"
    
    log_info "备份关键配置到: $backup_dir"
    
    [[ -d /etc/network ]] && cp -r /etc/network "$backup_dir/" 2>/dev/null || true
    [[ -d /etc/netplan ]] && cp -r /etc/netplan "$backup_dir/" 2>/dev/null || true
    [[ -f /etc/resolv.conf ]] && cp /etc/resolv.conf "$backup_dir/" 2>/dev/null || true
    [[ -d /etc/ssh ]] && cp -r /etc/ssh "$backup_dir/" 2>/dev/null || true
    [[ -d /root/.ssh ]] && cp -r /root/.ssh "$backup_dir/root_ssh" 2>/dev/null || true
    [[ -f /etc/hostname ]] && cp /etc/hostname "$backup_dir/" 2>/dev/null || true
    [[ -f /etc/hosts ]] && cp /etc/hosts "$backup_dir/" 2>/dev/null || true
    [[ -f /etc/fstab ]] && cp /etc/fstab "$backup_dir/" 2>/dev/null || true
    
    log_success "配置已备份"
    echo "$backup_dir"
}

# ===== 恢复关键配置 =====
restore_critical_configs() {
    local backup_dir="$1"
    
    [[ ! -d "$backup_dir" ]] && return 0
    
    log_info "恢复关键配置..."
    
    [[ -d "$backup_dir/network" ]] && cp -r "$backup_dir/network" /etc/ 2>/dev/null || true
    [[ -d "$backup_dir/netplan" ]] && cp -r "$backup_dir/netplan" /etc/ 2>/dev/null || true
    [[ -f "$backup_dir/resolv.conf" ]] && cp "$backup_dir/resolv.conf" /etc/ 2>/dev/null || true
    [[ -d "$backup_dir/ssh" ]] && cp -r "$backup_dir/ssh" /etc/ 2>/dev/null || true
    [[ -d "$backup_dir/root_ssh" ]] && cp -r "$backup_dir/root_ssh" /root/.ssh 2>/dev/null || true
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
    
    echo "" >&2
    log_info "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "${CYAN}开始系统恢复${NC}"
    log_info "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "" >&2
    log_info "快照: $snapshot_name"
    log_info "大小: $size"
    log_info "模式: $restore_mode"
    echo "" >&2
    
    send_telegram "🔄 <b>开始恢复</b>

📸 快照: ${snapshot_name}
🔧 模式: ${restore_mode}"
    
    # 验证
    if ! verify_snapshot "$snapshot_file"; then
        echo "" >&2
        read -p "验证失败，是否继续? [y/N]: " continue_restore >&2
        [[ ! "$continue_restore" =~ ^[Yy]$ ]] && log_info "已取消" && return 1
    fi
    
    # 备份配置
    local config_backup_dir=""
    if [[ "$restore_mode" == "智能恢复" ]]; then
        echo "" >&2
        log_info "正在备份关键配置..."
        config_backup_dir=$(backup_critical_configs)
    fi
    
    # 解压工具
    local decompress_cmd="cat"
    if [[ "$snapshot_file" =~ \.gz$ ]]; then
        decompress_cmd=$(command -v pigz &>/dev/null && echo "pigz -dc" || echo "gunzip -c")
    elif [[ "$snapshot_file" =~ \.bz2$ ]]; then
        decompress_cmd="bunzip2 -c"
    elif [[ "$snapshot_file" =~ \.xz$ ]]; then
        decompress_cmd="xz -dc"
    fi
    
    log_info "解压: $decompress_cmd"
    
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
    
    echo "" >&2
    log_info "开始解压恢复..."
    echo -e "${YELLOW}这可能需要几分钟...${NC}" >&2
    echo "" >&2
    
    local start_time=$(date +%s)
    
    # 执行
    cd / && {
        if $decompress_cmd "$snapshot_file" 2>/tmp/restore_err.log | tar "${tar_opts[@]}" 2>&1 | tee -a "$LOG_FILE" >&2; then
            local duration=$(($(date +%s) - start_time))
            
            echo "" >&2
            log_success "恢复完成"
            log_info "耗时: ${duration}秒"
            
            # 恢复配置
            [[ -n "$config_backup_dir" ]] && restore_critical_configs "$config_backup_dir"
            [[ -n "$config_backup_dir" ]] && rm -rf "$config_backup_dir"
            
            send_telegram "✅ <b>恢复完成</b>

⏱️ 耗时: ${duration}秒
⚠️ 建议重启系统"
            
            return 0
        else
            log_error "恢复失败"
            cat /tmp/restore_err.log 2>/dev/null | tail -10 >&2
            
            [[ -n "$config_backup_dir" ]] && restore_critical_configs "$config_backup_dir"
            [[ -n "$config_backup_dir" ]] && rm -rf "$config_backup_dir"
            
            send_telegram "❌ <b>恢复失败</b>

请查看日志: $LOG_FILE"
            
            return 1
        fi
    }
}

# ===== 主程序 =====
main() {
    clear
    echo "" >&2
    log_info "========================================"
    log_info "SnapSync v3.0 系统恢复"
    log_info "主机: $(hostname)"
    log_info "========================================"
    echo "" >&2
    
    load_config
    
    # 选择恢复来源
    echo -e "${CYAN}选择恢复来源${NC}" >&2
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo -e "  ${GREEN}1)${NC} 📁 本地恢复 - 从本地备份目录" >&2
    echo -e "  ${GREEN}2)${NC} 🌐 远程恢复 - 从远程服务器下载" >&2
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo "" >&2
    
    read -p "请选择 [1-2]: " source_choice >&2
    
    local snapshot_file=""
    
    case "$source_choice" in
        1)
            # 本地恢复
            snapshot_file=$(list_local_snapshots) || {
                echo "" >&2
                log_error "未选择快照"
                exit 1
            }
            ;;
        2)
            # 远程恢复
            local remote_enabled=$(echo "${REMOTE_ENABLED:-false}" | tr '[:upper:]' '[:lower:]')
            
            if [[ "$remote_enabled" != "y" && "$remote_enabled" != "yes" && "$remote_enabled" != "true" ]]; then
                echo "" >&2
                log_error "远程备份未启用"
                echo "" >&2
                echo "请先配置远程服务器:" >&2
                echo "  sudo snapsync" >&2
                echo "  选择: 3) 配置管理 -> 1) 修改远程服务器配置" >&2
                exit 1
            fi
            
            # 列出远程快照
            local remote_file
            remote_file=$(list_remote_snapshots) || {
                echo "" >&2
                log_error "未选择远程快照"
                exit 1
            }
            
            # 下载快照
            snapshot_file=$(download_remote_snapshot "$remote_file") || {
                echo "" >&2
                log_error "下载失败"
                exit 1
            }
            ;;
        *)
            log_error "无效选择"
            exit 1
            ;;
    esac
    
    [[ -z "$snapshot_file" || ! -f "$snapshot_file" ]] && log_error "无效快照" && exit 1
    
    # 选择模式
    echo "" >&2
    echo -e "${CYAN}选择恢复模式${NC}" >&2
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo -e "  ${GREEN}1)${NC} 🛡️  智能恢复（推荐）" >&2
    echo -e "      • 恢复系统文件" >&2
    echo -e "      • 保留网络/SSH配置" >&2
    echo -e "      • 防止断网" >&2
    echo "" >&2
    echo -e "  ${GREEN}2)${NC} 🔧 完全恢复" >&2
    echo -e "      • 恢复所有内容" >&2
    echo -e "      • ${RED}可能导致断网${NC}" >&2
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo "" >&2
    
    read -p "选择 [1-2]: " mode_choice >&2
    
    local restore_mode="智能恢复"
    [[ "$mode_choice" == "2" ]] && restore_mode="完全恢复"
    
    # 确认
    echo "" >&2
    log_warning "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_warning "${RED}警告: 系统恢复不可撤销！${NC}"
    log_warning "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "" >&2
    echo "即将恢复:" >&2
    echo "  快照: $(basename "$snapshot_file")" >&2
    echo "  模式: $restore_mode" >&2
    echo "" >&2
    
    read -p "确认恢复? 输入 'YES': " final_confirm >&2
    
    [[ "$final_confirm" != "YES" ]] && log_info "已取消" && exit 0
    
    # 执行
    if perform_restore "$snapshot_file" "$restore_mode"; then
        echo "" >&2
        log_success "========================================"
        log_success "系统恢复完成！"
        log_success "========================================"
        echo "" >&2
        log_warning "${YELLOW}建议立即重启系统${NC}"
        echo "" >&2
        
        read -p "是否重启? [y/N]: " do_reboot >&2
        [[ "$do_reboot" =~ ^[Yy]$ ]] && { log_info "重启中..."; sleep 3; reboot; }
    else
        log_error "恢复失败"
        exit 1
    fi
}

# 权限检查
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 需要 root 权限${NC}" >&2
    echo -e "${YELLOW}使用: sudo $0${NC}" >&2
    exit 1
fi

main "$@"
