#!/bin/bash

# SnapSync v3.0 - 无损恢复模块（路径修复版）
# 修复：BACKUP_DIR 默认值错误导致路径重复

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

# ===== 加载配置（修复版 - 正确的默认路径）=====
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        BACKUP_DIR="${BACKUP_DIR:-/backups}"  # ✓ 修复：改为 /backups
        log_info "配置已加载: 备份目录 = $BACKUP_DIR"
    else
        BACKUP_DIR="/backups"  # ✓ 修复：改为 /backups
        log_warning "配置文件不存在，使用默认: $BACKUP_DIR"
    fi
    
    # 调试信息
    log_info "快照目录将是: ${BACKUP_DIR}/system_snapshots"
}

# ===== 列出本地快照（调试增强版）=====
list_local_snapshots() {
    local snapshot_dir="${BACKUP_DIR}/system_snapshots"
    
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "扫描快照目录: $snapshot_dir"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 检查目录
    if [[ ! -d "$snapshot_dir" ]]; then
        log_error "快照目录不存在: $snapshot_dir"
        echo ""
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}错误: 快照目录不存在${NC}"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "目录路径: $snapshot_dir"
        echo "配置的备份目录: $BACKUP_DIR"
        echo ""
        echo "调试信息："
        echo "  检查父目录："
        ls -la "$BACKUP_DIR" 2>/dev/null | head -10 || echo "  父目录不存在"
        echo ""
        return 1
    fi
    
    log_info "目录存在，正在查找快照文件（排除 .sha256）..."
    
    # ===== 使用最简单的方法：直接在目标目录里用 ls =====
    local snapshots=()
    local current_dir=$(pwd)
    
    # 进入快照目录并获取文件列表
    cd "$snapshot_dir" || {
        log_error "无法进入目录: $snapshot_dir"
        return 1
    }
    
    # 获取所有 .tar* 文件，排除 .sha256，按时间倒序
    log_info "执行: ls -t system_snapshot_*.tar* | grep -v '.sha256\$'"
    for file in $(ls -t system_snapshot_*.tar* 2>/dev/null | grep -v '\.sha256$'); do
        # 使用绝对路径
        if [[ -f "$file" ]]; then
            snapshots+=("${snapshot_dir}/${file}")
            log_info "找到快照: ${file}"
        fi
    done
    
    # 返回原目录
    cd "$current_dir"
    
    log_info "总共找到 ${#snapshots[@]} 个快照文件"
    
    # 检查结果
    if [[ ${#snapshots[@]} -eq 0 ]]; then
        log_error "未找到快照文件"
        echo ""
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}警告: 未找到快照文件${NC}"
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "快照目录: $snapshot_dir"
        echo "配置的备份目录: $BACKUP_DIR"
        echo ""
        echo "调试信息："
        echo "  目录内容（包含.sha256）："
        ls -lh "$snapshot_dir" 2>/dev/null | head -15 || echo "  无法读取"
        echo ""
        echo "  统计："
        echo "    .tar.gz 文件: $(find "$snapshot_dir" -name "*.tar.gz" 2>/dev/null | wc -l)"
        echo "    .sha256 文件: $(find "$snapshot_dir" -name "*.sha256" 2>/dev/null | wc -l)"
        echo ""
        return 1
    fi
    
    # 显示列表
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}可用快照列表 (共 ${#snapshots[@]} 个)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    for i in "${!snapshots[@]}"; do
        local file="${snapshots[$i]}"
        local name=$(basename "$file")
        local size_bytes=$(stat -c%s "$file" 2>/dev/null || echo 0)
        local size=$(format_bytes "$size_bytes")
        local date=$(date -r "$file" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "未知")
        
        # 校验状态
        local checksum_status=""
        if [[ -f "${file}.sha256" ]]; then
            checksum_status="${GREEN}✓ 已校验${NC}"
        else
            checksum_status="${YELLOW}⚠ 无校验${NC}"
        fi
        
        echo -e "  ${GREEN}$((i+1)))${NC} ${CYAN}${name}${NC}"
        echo -e "      📦 大小: ${size}"
        echo -e "      📅 时间: ${date}"
        echo -e "      🔒 ${checksum_status}"
        echo ""
    done
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # 选择快照
    local choice
    while true; do
        read -p "选择快照 [1-${#snapshots[@]}] 或 0 取消: " choice
        
        if [[ "$choice" == "0" ]]; then
            log_info "用户取消"
            return 1
        fi
        
        if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}请输入有效数字！${NC}"
            continue
        fi
        
        if (( choice < 1 || choice > ${#snapshots[@]} )); then
            echo -e "${RED}选择超出范围 (1-${#snapshots[@]})${NC}"
            continue
        fi
        
        break
    done
    
    local selected="${snapshots[$((choice-1))]}"
    log_info "选择: $(basename "$selected")"
    
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
        echo ""
        echo -e "${YELLOW}⚠ 警告: 未找到校验和文件${NC}"
        echo "无法验证快照完整性"
        echo ""
        return 0
    fi
    
    log_info "验证快照完整性..."
    echo -e "${CYAN}正在验证...${NC}"
    
    local snapshot_dir=$(dirname "$snapshot_file")
    local snapshot_name=$(basename "$snapshot_file")
    local checksum_name=$(basename "$checksum_file")
    
    if (cd "$snapshot_dir" && sha256sum -c "$checksum_name" &>/dev/null); then
        log_success "验证通过"
        echo -e "${GREEN}✓ 快照完整性验证通过${NC}"
        echo ""
        return 0
    else
        log_error "验证失败"
        echo -e "${RED}✗ 快照完整性验证失败${NC}"
        echo "快照文件可能已损坏"
        echo ""
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
    
    echo ""
    log_info "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "${CYAN}开始系统恢复${NC}"
    log_info "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    log_info "快照: $snapshot_name"
    log_info "大小: $size"
    log_info "模式: $restore_mode"
    echo ""
    
    send_telegram "🔄 <b>开始恢复</b>

📸 快照: ${snapshot_name}
🔧 模式: ${restore_mode}"
    
    # 验证
    if ! verify_snapshot "$snapshot_file"; then
        echo ""
        read -p "验证失败，是否继续? [y/N]: " continue_restore
        [[ ! "$continue_restore" =~ ^[Yy]$ ]] && log_info "已取消" && return 1
    fi
    
    # 备份配置
    local config_backup_dir=""
    if [[ "$restore_mode" == "智能恢复" ]]; then
        echo ""
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
    
    echo ""
    log_info "开始解压恢复..."
    echo -e "${YELLOW}这可能需要几分钟...${NC}"
    echo ""
    
    local start_time=$(date +%s)
    
    # 执行
    cd / && {
        if $decompress_cmd "$snapshot_file" 2>/tmp/restore_err.log | tar "${tar_opts[@]}" 2>&1 | tee -a "$LOG_FILE"; then
            local duration=$(($(date +%s) - start_time))
            
            echo ""
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
            cat /tmp/restore_err.log 2>/dev/null | tail -10
            
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
    echo ""
    log_info "========================================"
    log_info "SnapSync v3.0 系统恢复"
    log_info "主机: $(hostname)"
    log_info "========================================"
    echo ""
    
    load_config
    
    # 选择快照
    local snapshot_file
    snapshot_file=$(list_local_snapshots) || {
        echo ""
        log_error "未选择快照"
        exit 1
    }
    
    [[ -z "$snapshot_file" || ! -f "$snapshot_file" ]] && log_error "无效快照" && exit 1
    
    # 选择模式
    echo ""
    echo -e "${CYAN}选择恢复模式${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${GREEN}1)${NC} 🛡️  智能恢复（推荐）"
    echo -e "      • 恢复系统文件"
    echo -e "      • 保留网络/SSH配置"
    echo -e "      • 防止断网"
    echo ""
    echo -e "  ${GREEN}2)${NC} 🔧 完全恢复"
    echo -e "      • 恢复所有内容"
    echo -e "      • ${RED}可能导致断网${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "选择 [1-2]: " mode_choice
    
    local restore_mode="智能恢复"
    [[ "$mode_choice" == "2" ]] && restore_mode="完全恢复"
    
    # 确认
    echo ""
    log_warning "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_warning "${RED}警告: 系统恢复不可撤销！${NC}"
    log_warning "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "即将恢复:"
    echo "  快照: $(basename "$snapshot_file")"
    echo "  模式: $restore_mode"
    echo ""
    
    read -p "确认恢复? 输入 'YES': " final_confirm
    
    [[ "$final_confirm" != "YES" ]] && log_info "已取消" && exit 0
    
    # 执行
    if perform_restore "$snapshot_file" "$restore_mode"; then
        echo ""
        log_success "========================================"
        log_success "系统恢复完成！"
        log_success "========================================"
        echo ""
        log_warning "${YELLOW}建议立即重启系统${NC}"
        echo ""
        
        read -p "是否重启? [y/N]: " do_reboot
        [[ "$do_reboot" =~ ^[Yy]$ ]] && { log_info "重启中..."; sleep 3; reboot; }
    else
        log_error "恢复失败"
        exit 1
    fi
}

# 权限检查
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 需要 root 权限${NC}"
    echo -e "${YELLOW}使用: sudo $0${NC}"
    exit 1
fi

main "$@"
