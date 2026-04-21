#!/bin/bash

# SnapSync v3.0 - 主控制脚本（完整版）

set -euo pipefail
IFS=$'\n\t'
umask 077

# ===== 版本信息 =====
SNAPSYNC_VERSION="3.0.1"
GITHUB_REPO="kelenetwork/SnapSync"
GITHUB_CLONE_URL="https://github.com/${GITHUB_REPO}.git"


# ===== 颜色定义 =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ===== 路径定义 =====
INSTALL_DIR="/opt/snapsync"
CONFIG_DIR="/etc/snapsync"
CONFIG_FILE="$CONFIG_DIR/config.conf"
LOG_DIR="/var/log/snapsync"
MODULE_DIR="$INSTALL_DIR/modules"
TMP_FILES=()

# ===== 权限检查 =====
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 需要 root 权限${NC}"
    echo -e "${YELLOW}使用: sudo $0${NC}"
    exit 1
fi

# ===== 工具函数 =====
log() {
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    echo -e "$(date '+%F %T') $*" | tee -a "$LOG_DIR/main.log" 2>/dev/null || echo -e "$*"
}

create_temp_file() {
    local template="${1:-snapsync_XXXXXX}"
    local temp_file
    temp_file=$(mktemp "${TMPDIR:-/tmp}/${template}")
    TMP_FILES+=("$temp_file")
    printf '%s\n' "$temp_file"
}

cleanup() {
    if ((${#TMP_FILES[@]})); then
        rm -f "${TMP_FILES[@]}" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

run_curl() {
    local had_xtrace=0
    if [[ $- == *x* ]]; then
        had_xtrace=1
        set +x
    fi

    curl -sS --fail --connect-timeout 10 --max-time 30 "$@"
    local rc=$?

    if (( had_xtrace )); then
        set -x
    fi

    return "$rc"
}

http_get() {
    run_curl "$@"
}

set_config_value() {
    local key="$1"
    local value="$2"
    local temp_file
    local escaped_value

    temp_file=$(create_temp_file "snapsync_config_XXXXXX")
    printf -v escaped_value '%q' "$value"

    awk -v key="$key" -v value="$escaped_value" '
        BEGIN { updated = 0 }
        $0 ~ ("^" key "=") {
            print key "=" value
            updated = 1
            next
        }
        { print }
        END {
            if (!updated) {
                print key "=" value
            }
        }
    ' "$CONFIG_FILE" > "$temp_file"

    mv "$temp_file" "$CONFIG_FILE"
}

show_header() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${CYAN}       SnapSync v3.0 管理控制台            ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
    echo ""
}

show_status_bar() {
    local backup_dir="/backups"
    local snapshot_count="0"
    local disk_usage="N/A"
    
    # 安全加载配置
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE" 2>/dev/null || true
        backup_dir="${BACKUP_DIR:-/backups}"
    fi
    
    # 安全统计快照数量
    if [[ -d "$backup_dir/system_snapshots" ]]; then
        snapshot_count=$(find "$backup_dir/system_snapshots" -maxdepth 1 -name "*.tar*" -type f 2>/dev/null | grep -cv '\.sha256$' || echo "0")
    fi
    
    # 安全获取磁盘使用率
    if [[ -d "$backup_dir" ]]; then
        disk_usage=$(df -h "$backup_dir" 2>/dev/null | awk 'NR==2 {print $5}' || echo "N/A")
    fi
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}主机:${NC} $(hostname) ${GREEN}| 快照:${NC} ${snapshot_count} ${GREEN}| 磁盘:${NC} ${disk_usage}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

pause() {
    echo ""
    read -p "按 Enter 继续..."
}

# ===== 主菜单 =====
show_main_menu() {
    show_header
    show_status_bar
    
    echo -e "${YELLOW}主菜单${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${GREEN}1)${NC} 📸 创建系统快照"
    echo -e "  ${GREEN}2)${NC} 🔄 恢复系统快照"
    echo -e "  ${GREEN}3)${NC} ⚙️  配置管理"
    echo -e "  ${GREEN}4)${NC} 📊 查看快照列表"
    echo -e "  ${GREEN}5)${NC} 🤖 Telegram Bot 管理"
    echo -e "  ${GREEN}6)${NC} 🗑️  清理旧快照"
    echo -e "  ${GREEN}7)${NC} 📋 查看日志"
    echo -e "  ${GREEN}8)${NC} ℹ️  系统信息"
    echo -e "  ${GREEN}9)${NC} 🔧 升级到最新版本"
    echo -e "  ${GREEN}10)${NC} 🧹 完全卸载"
    echo -e "  ${RED}0)${NC} 🚪 退出"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# ===== 1. 创建快照 =====
create_snapshot() {
    show_header
    log "${CYAN}创建系统快照${NC}\n"
    
    if [[ ! -f "$MODULE_DIR/backup.sh" ]]; then
        log "${RED}错误: 备份模块不存在${NC}"
        pause
        return
    fi
    
    bash "$MODULE_DIR/backup.sh"
    
    pause
}

# ===== 2. 恢复快照 =====
restore_snapshot() {
    show_header
    log "${CYAN}恢复系统快照${NC}\n"
    
    if [[ ! -f "$MODULE_DIR/restore.sh" ]]; then
        log "${RED}错误: 恢复模块不存在${NC}"
        pause
        return
    fi
    
    bash "$MODULE_DIR/restore.sh"
    
    pause
}

# ===== 3. 配置管理 =====
manage_config() {
    while true; do
        show_header
        log "${CYAN}配置管理${NC}\n"
        
        echo -e "${YELLOW}配置选项${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${GREEN}1)${NC} 修改远程服务器配置"
        echo -e "  ${GREEN}2)${NC} 修改 Telegram 配置"
        echo -e "  ${GREEN}3)${NC} 修改保留策略"
        echo -e "  ${GREEN}4)${NC} 查看当前配置"
        echo -e "  ${GREEN}5)${NC} 编辑配置文件"
        echo -e "  ${GREEN}6)${NC} 重启服务"
        echo -e "  ${GREEN}7)${NC} 测试 Telegram 连接"
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        
        read -p "请选择 [0-7]: " config_choice
        
        case "$config_choice" in
            1) configure_remote ;;
            2) configure_telegram ;;
            3) configure_retention ;;
            4) view_config ;;
            5) edit_config_file ;;
            6) restart_services ;;
            7) test_telegram ;;
            0) return ;;
            *) log "${RED}无效选择${NC}"; sleep 1 ;;
        esac
    done
}

configure_remote() {
    show_header
    log "${CYAN}配置远程服务器${NC}\n"
    
    echo "当前配置:"
    source "$CONFIG_FILE" 2>/dev/null || true
    echo "  远程备份: ${REMOTE_ENABLED:-false}"
    echo "  服务器: ${REMOTE_HOST:-未配置}"
    echo "  用户: ${REMOTE_USER:-root}"
    echo "  端口: ${REMOTE_PORT:-22}"
    echo ""
    
    read -p "是否启用远程备份? [y/N]: " enable_remote
    
    if [[ "$enable_remote" =~ ^[Yy]$ ]]; then
        read -p "远程服务器地址: " remote_host
        read -p "SSH 用户 [root]: " remote_user
        remote_user="${remote_user:-root}"
        read -p "SSH 端口 [22]: " remote_port
        remote_port="${remote_port:-22}"
        read -p "远程路径 [/backups]: " remote_path
        remote_path="${remote_path:-/backups}"
        
        # 更新配置
        set_config_value "REMOTE_ENABLED" "true"
        set_config_value "REMOTE_HOST" "$remote_host"
        set_config_value "REMOTE_USER" "$remote_user"
        set_config_value "REMOTE_PORT" "$remote_port"
        set_config_value "REMOTE_PATH" "$remote_path"
        
        log "${GREEN}✓ 远程服务器配置已保存${NC}"
        
        # 生成SSH密钥
        if [[ ! -f /root/.ssh/id_ed25519 ]]; then
            echo ""
            log "${YELLOW}生成 SSH 密钥...${NC}"
            ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N "" -q
            log "${GREEN}✓ SSH 密钥已生成${NC}"
        fi
        
        echo ""
        log "${YELLOW}请将以下公钥添加到远程服务器:${NC}"
        echo ""
        cat /root/.ssh/id_ed25519.pub
        echo ""
        log "${CYAN}在远程服务器执行:${NC}"
        echo "  mkdir -p ~/.ssh"
        echo "  echo '$(cat /root/.ssh/id_ed25519.pub)' >> ~/.ssh/authorized_keys"
        echo "  chmod 700 ~/.ssh"
        echo "  chmod 600 ~/.ssh/authorized_keys"
        
    else
        set_config_value "REMOTE_ENABLED" "false"
        log "${GREEN}✓ 远程备份已禁用${NC}"
    fi
    
    pause
}

configure_telegram() {
    show_header
    log "${CYAN}配置 Telegram Bot${NC}\n"
    
    echo "当前配置:"
    source "$CONFIG_FILE" 2>/dev/null || true
    echo "  Telegram: ${TELEGRAM_ENABLED:-false}"
    echo "  Bot Token: ${TELEGRAM_BOT_TOKEN:0:20}..."
    echo "  Chat ID: ${TELEGRAM_CHAT_ID}"
    echo ""
    
    read -p "是否启用 Telegram 通知? [y/N]: " enable_tg
    
    if [[ "$enable_tg" =~ ^[Yy]$ ]]; then
        echo ""
        log "${YELLOW}获取 Bot Token:${NC}"
        echo "  1. 在 Telegram 搜索 @BotFather"
        echo "  2. 发送 /newbot 创建新 Bot"
        echo "  3. 获取 Bot Token"
        echo ""
        
        read -p "输入 Bot Token: " bot_token
        
        echo ""
        log "${YELLOW}获取 Chat ID:${NC}"
        echo "  1. 向你的 Bot 发送任意消息"
        echo "  2. 访问: https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates"
        echo "  3. 找到 \"chat\":{\"id\":数字}"
        echo ""
        
        read -p "输入 Chat ID: " chat_id
        
        # 更新配置
        set_config_value "TELEGRAM_ENABLED" "true"
        set_config_value "TELEGRAM_BOT_TOKEN" "$bot_token"
        set_config_value "TELEGRAM_CHAT_ID" "$chat_id"
        
        log "${GREEN}✓ Telegram 配置已保存${NC}"
        
    else
        set_config_value "TELEGRAM_ENABLED" "false"
        log "${GREEN}✓ Telegram 通知已禁用${NC}"
    fi
    
    pause
}

configure_retention() {
    show_header
    log "${CYAN}配置保留策略${NC}\n"
    
    source "$CONFIG_FILE" 2>/dev/null || true
    
    echo "当前配置:"
    echo "  本地保留: ${LOCAL_KEEP_COUNT:-5} 个"
    echo "  远程保留: ${REMOTE_KEEP_DAYS:-30} 天"
    echo ""
    
    read -p "本地保留快照数量 [5]: " local_keep
    local_keep="${local_keep:-5}"
    
    read -p "远程保留天数 [30]: " remote_keep
    remote_keep="${remote_keep:-30}"
    
    set_config_value "LOCAL_KEEP_COUNT" "$local_keep"
    set_config_value "REMOTE_KEEP_DAYS" "$remote_keep"
    
    log "${GREEN}✓ 保留策略已更新${NC}"
    pause
}

view_config() {
    show_header
    log "${CYAN}当前配置${NC}\n"
    
    if [[ -f "$CONFIG_FILE" ]]; then
        cat "$CONFIG_FILE"
    else
        log "${RED}配置文件不存在${NC}"
    fi
    
    pause
}

edit_config_file() {
    show_header
    log "${CYAN}编辑配置文件${NC}\n"
    
    if command -v nano &>/dev/null; then
        nano "$CONFIG_FILE"
    elif command -v vi &>/dev/null; then
        vi "$CONFIG_FILE"
    else
        log "${RED}未找到文本编辑器${NC}"
    fi
    
    pause
}

restart_services() {
    show_header
    log "${CYAN}重启服务${NC}\n"
    
    log "重启 Telegram Bot..."
    systemctl restart snapsync-bot 2>/dev/null || log "${YELLOW}⚠ Bot 服务未运行${NC}"
    
    log "重启定时器..."
    systemctl restart snapsync-backup.timer 2>/dev/null || log "${YELLOW}⚠ 定时器未启用${NC}"
    
    log "${GREEN}✓ 服务已重启${NC}"
    pause
}

test_telegram() {
    show_header
    log "${CYAN}测试 Telegram 连接${NC}\n"
    
    if command -v telegram-test &>/dev/null; then
        telegram-test
    else
        log "${RED}未找到诊断工具${NC}"
    fi
    
    pause
}

# ===== 4. 查看快照列表 =====
list_snapshots() {
    show_header
    log "${CYAN}快照列表${NC}\n"
    
    source "$CONFIG_FILE" 2>/dev/null || true
    local backup_dir="${BACKUP_DIR:-/backups}"
    local snapshot_dir="$backup_dir/system_snapshots"
    
    if [[ ! -d "$snapshot_dir" ]]; then
        log "${YELLOW}快照目录不存在${NC}"
        pause
        return
    fi
    
    local snapshots=()
    while IFS= read -r -d '' file; do
        if [[ "$file" != *.sha256 ]]; then
            snapshots+=("$file")
        fi
    done < <(find "$snapshot_dir" -maxdepth 1 -name "*.tar*" -type f -print0 2>/dev/null | sort -zr)
    
    if [[ ${#snapshots[@]} -eq 0 ]]; then
        log "${YELLOW}未找到快照${NC}"
        pause
        return
    fi
    
    log "${GREEN}找到 ${#snapshots[@]} 个快照:${NC}\n"
    
    local idx=1
    for file in "${snapshots[@]}"; do
        local name=$(basename "$file")
        local size=$(stat -c%s "$file" 2>/dev/null || echo 0)
        local size_human=""
        
        if (( size >= 1073741824 )); then
            size_human="$(awk "BEGIN {printf \"%.2f\", $size/1073741824}")GB"
        elif (( size >= 1048576 )); then
            size_human="$(awk "BEGIN {printf \"%.2f\", $size/1048576}")MB"
        else
            size_human="$(awk "BEGIN {printf \"%.2f\", $size/1024}")KB"
        fi
        
        local date=$(date -r "$file" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "未知")
        
        echo -e "${CYAN}${idx})${NC} ${name}"
        echo "   大小: ${size_human}"
        echo "   时间: ${date}"
        
        if [[ -f "${file}.sha256" ]]; then
            echo "   状态: ✓ 已校验"
        else
            echo "   状态: ⚠ 无校验"
        fi
        echo ""
        
        ((idx++))
    done
    
    pause
}

# ===== 5. Bot 管理 =====
manage_telegram_bot() {
    while true; do
        show_header
        log "${CYAN}Telegram Bot 管理${NC}\n"
        
        local bot_status=$(systemctl is-active snapsync-bot 2>/dev/null || echo "inactive")
        local status_color="${RED}"
        [[ "$bot_status" == "active" ]] && status_color="${GREEN}"
        
        echo -e "Bot 状态: ${status_color}${bot_status}${NC}"
        echo ""
        
        echo -e "${YELLOW}Bot 管理${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${GREEN}1)${NC} 启动 Bot"
        echo -e "  ${GREEN}2)${NC} 停止 Bot"
        echo -e "  ${GREEN}3)${NC} 重启 Bot"
        echo -e "  ${GREEN}4)${NC} 查看 Bot 状态"
        echo -e "  ${GREEN}5)${NC} 查看 Bot 日志"
        echo -e "  ${GREEN}6)${NC} 启用开机自启"
        echo -e "  ${GREEN}7)${NC} 禁用开机自启"
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        
        read -p "请选择 [0-7]: " bot_choice
        
        case "$bot_choice" in
            1)
                systemctl start snapsync-bot
                log "${GREEN}✓ Bot 已启动${NC}"
                sleep 2
                ;;
            2)
                systemctl stop snapsync-bot
                log "${GREEN}✓ Bot 已停止${NC}"
                sleep 2
                ;;
            3)
                systemctl restart snapsync-bot
                log "${GREEN}✓ Bot 已重启${NC}"
                sleep 2
                ;;
            4)
                systemctl status snapsync-bot
                pause
                ;;
            5)
                tail -50 /var/log/snapsync/bot.log
                pause
                ;;
            6)
                systemctl enable snapsync-bot
                log "${GREEN}✓ 已启用开机自启${NC}"
                sleep 2
                ;;
            7)
                systemctl disable snapsync-bot
                log "${GREEN}✓ 已禁用开机自启${NC}"
                sleep 2
                ;;
            0) return ;;
            *) log "${RED}无效选择${NC}"; sleep 1 ;;
        esac
    done
}

# ===== 6. 清理快照 =====
clean_snapshots() {
    show_header
    log "${CYAN}清理旧快照${NC}\n"
    
    source "$CONFIG_FILE" 2>/dev/null || true
    local backup_dir="${BACKUP_DIR:-/backups}"
    local snapshot_dir="$backup_dir/system_snapshots"
    local keep_count="${LOCAL_KEEP_COUNT:-5}"
    
    local snapshots=()
    while IFS= read -r -d '' file; do
        if [[ "$file" != *.sha256 ]]; then
            snapshots+=("$file")
        fi
    done < <(find "$snapshot_dir" -maxdepth 1 -name "*.tar*" -type f -print0 2>/dev/null | sort -zr)
    
    local total=${#snapshots[@]}
    
    log "当前快照: ${total} 个"
    log "保留策略: 最新 ${keep_count} 个"
    echo ""
    
    if (( total <= keep_count )); then
        log "${GREEN}快照数量未超限，无需清理${NC}"
        pause
        return
    fi
    
    local to_delete=$((total - keep_count))
    log "${YELLOW}将删除 ${to_delete} 个旧快照${NC}"
    echo ""
    
    read -p "确认删除? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log "已取消"
        pause
        return
    fi
    
    local deleted=0
    for ((i=keep_count; i<total; i++)); do
        local file="${snapshots[$i]}"
        log "删除: $(basename "$file")"
        rm -f "$file" "${file}.sha256"
        ((deleted++))
    done
    
    log "${GREEN}✓ 已删除 ${deleted} 个快照${NC}"
    pause
}

# ===== 7. 查看日志 =====
view_logs() {
    while true; do
        show_header
        log "${CYAN}查看日志${NC}\n"
        
        echo -e "${YELLOW}日志选项${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${GREEN}1)${NC} 备份日志"
        echo -e "  ${GREEN}2)${NC} 恢复日志"
        echo -e "  ${GREEN}3)${NC} Bot 日志"
        echo -e "  ${GREEN}4)${NC} 主日志"
        echo -e "  ${GREEN}5)${NC} 实时监控备份日志"
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        
        read -p "请选择 [0-5]: " log_choice
        
        case "$log_choice" in
            1) tail -100 "$LOG_DIR/backup.log"; pause ;;
            2) tail -100 "$LOG_DIR/restore.log"; pause ;;
            3) tail -100 "$LOG_DIR/bot.log"; pause ;;
            4) tail -100 "$LOG_DIR/main.log"; pause ;;
            5) tail -f "$LOG_DIR/backup.log" ;;
            0) return ;;
            *) log "${RED}无效选择${NC}"; sleep 1 ;;
        esac
    done
}

# ===== 8. 系统信息 =====
show_system_info() {
    show_header
    log "${CYAN}系统信息${NC}\n"
    
    echo -e "${YELLOW}主机信息:${NC}"
    echo "  主机名: $(hostname)"
    echo "  系统: $(uname -s) $(uname -r)"
    echo "  运行时间: $(uptime -p 2>/dev/null || echo "未知")"
    echo ""
    
    echo -e "${YELLOW}磁盘信息:${NC}"
    df -h | grep -E '^/dev/|Filesystem'
    echo ""
    
    echo -e "${YELLOW}内存信息:${NC}"
    free -h
    echo ""
    
    source "$CONFIG_FILE" 2>/dev/null || true
    
    echo -e "${YELLOW}SnapSync 信息:${NC}"
    echo "  版本: v3.0"
    echo "  备份目录: ${BACKUP_DIR:-/backups}"
    echo "  Telegram: ${TELEGRAM_ENABLED:-false}"
    echo "  远程备份: ${REMOTE_ENABLED:-false}"
    echo ""
    
    pause
}

# ===== 9. 升级功能 =====
upgrade_snapsync() {
    show_header
    log "${CYAN}升级 SnapSync${NC}\n"
    
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}SnapSync 升级向导${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "当前版本: v${SNAPSYNC_VERSION}"
    echo ""
    
    # 检查网络连接
    log "检查网络连接..."
    if ! http_get --max-time 10 --head https://github.com &>/dev/null; then
        log "${RED}✗ 无法连接到 GitHub${NC}"
        echo ""
        echo "请检查网络连接或防火墙设置"
        pause
        return
    fi
    log "${GREEN}✓ 网络连接正常${NC}"
    echo ""
    
    # 检查 git 是否安装
    if ! command -v git &>/dev/null; then
        log "${RED}✗ 未安装 git${NC}"
        echo ""
        log "请先安装 git:"
        echo "  apt-get update && apt-get install -y git"
        pause
        return
    fi
    log "${GREEN}✓ git 已安装${NC}"
    echo ""
    
    # 查找源代码目录
    log "查找源代码目录..."
    local source_dirs=(
        "/root/SnapSync"
        "/root/snapsync"
        "$HOME/SnapSync"
        "$HOME/snapsync"
    )
    
    local found_dir=""
    for dir in "${source_dirs[@]}"; do
        if [[ -d "$dir/.git" ]]; then
            found_dir="$dir"
            log "${GREEN}✓ 找到源代码: $dir${NC}"
            break
        fi
    done
    
    # 如果没找到，使用默认位置
    if [[ -z "$found_dir" ]]; then
        log "${YELLOW}⚠ 未找到现有的源代码目录${NC}"
        echo ""
        echo "将在 /root/SnapSync 下载最新代码"
        found_dir="/root/SnapSync"
    fi
    echo ""
    
    # 确认升级
    log "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${YELLOW}升级计划:${NC}"
    echo "  1. 备份当前安装"
    echo "  2. 清理旧的源代码目录"
    echo "  3. 重新克隆最新代码"
    echo "  4. 运行安装脚本"
    echo "  5. 重启服务"
    echo ""
    echo "源代码位置: $found_dir"
    log "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "确认开始升级? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log "已取消"
        pause
        return
    fi
    
    echo ""
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${CYAN}开始升级...${NC}"
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # 1. 备份当前安装
    log "${YELLOW}[1/5]${NC} 备份当前版本..."
    local backup_dir="/opt/snapsync_backup_$(date +%Y%m%d_%H%M%S)"
    if cp -r "$INSTALL_DIR" "$backup_dir" 2>/dev/null; then
        log "${GREEN}  ✓ 已备份到: $backup_dir${NC}"
    else
        log "${YELLOW}  ⚠ 备份失败，但继续升级${NC}"
    fi
    echo ""
    
    # 2. 清理旧的源代码目录
    log "${YELLOW}[2/5]${NC} 清理旧源代码..."
    if [[ -d "$found_dir" ]]; then
        # 保存当前目录
        local original_dir="$(pwd)"
        
        # 如果当前在源代码目录中，先切换出去
        if [[ "$(pwd)" == "$found_dir"* ]]; then
            cd /root 2>/dev/null || cd / 2>/dev/null
            log "  → 已切换工作目录"
        fi
        
        # 删除源代码目录
        if rm -rf "$found_dir" 2>/dev/null; then
            log "${GREEN}  ✓ 已删除: $found_dir${NC}"
        else
            log "${RED}  ✗ 删除失败: $found_dir${NC}"
            log "${YELLOW}  请手动删除该目录后重试${NC}"
            pause
            return
        fi
    else
        log "${GREEN}  ✓ 无需清理${NC}"
    fi
    echo ""
    
    # 3. 克隆最新代码
    log "${YELLOW}[3/5]${NC} 下载最新代码..."
    local parent_dir="$(dirname "$found_dir")"
    cd "$parent_dir" || {
        log "${RED}  ✗ 无法切换到目录: $parent_dir${NC}"
        pause
        return
    }
    
    log "  从 GitHub 克隆仓库..."
    if git clone "${GITHUB_CLONE_URL}" "$(basename "$found_dir")" 2>&1 | tee -a "$LOG_DIR/main.log" | grep -E "(Cloning|Receiving|Resolving)" | while read line; do echo "    $line"; done; then
        log "${GREEN}  ✓ 代码下载完成${NC}"
    else
        log "${RED}  ✗ 克隆失败${NC}"
        echo ""
        log "如需回退:"
        log "  sudo cp -r $backup_dir/* $INSTALL_DIR/"
        pause
        return
    fi
    echo ""
    
    # 4. 运行安装脚本
    log "${YELLOW}[4/5]${NC} 运行安装脚本..."
    cd "$found_dir" || {
        log "${RED}  ✗ 无法进入目录: $found_dir${NC}"
        pause
        return
    }
    
    if [[ ! -f "install.sh" ]]; then
        log "${RED}  ✗ 找不到 install.sh${NC}"
        pause
        return
    fi
    
    log "  执行安装..."
    echo ""
    
    # 运行安装脚本（自动选择覆盖安装）
    if echo "1" | bash install.sh 2>&1 | tee -a "$LOG_DIR/main.log"; then
        log ""
        log "${GREEN}  ✓ 安装完成${NC}"
    else
        log ""
        log "${RED}  ✗ 安装失败${NC}"
        echo ""
        log "如需回退:"
        log "  sudo cp -r $backup_dir/* $INSTALL_DIR/"
        pause
        return
    fi
    echo ""
    
    # 5. 重启服务
    log "${YELLOW}[5/5]${NC} 重启服务..."
    systemctl daemon-reload 2>/dev/null || true
    systemctl restart snapsync-bot 2>/dev/null && log "  ✓ Bot 服务已重启" || log "  ⊙ Bot 服务未运行"
    systemctl restart snapsync-backup.timer 2>/dev/null && log "  ✓ 定时器已重启" || log "  ⊙ 定时器未启用"
    echo ""
    
    # 完成
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${GREEN}✓✓✓ 升级完成！✓✓✓${NC}"
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    log "升级成功！"
    log "源代码位置: $found_dir"
    log "备份位置: $backup_dir"
    echo ""
    
    log "${YELLOW}如需回退到旧版本:${NC}"
    log "  sudo cp -r $backup_dir/* $INSTALL_DIR/"
    log "  sudo systemctl daemon-reload"
    log "  sudo systemctl restart snapsync-bot snapsync-backup.timer"
    echo ""
    
    pause
}

# ===== 10. 完全卸载（修复版 - 彻底清理）=====
uninstall_snapsync() {
    show_header
    log "${RED}完全卸载 SnapSync${NC}\n"
    
    echo -e "${RED}╔════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║           ⚠️  警 告 ⚠️                    ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════╝${NC}"
    echo ""
    log "${YELLOW}此操作将删除：${NC}"
    echo "  ✓ 所有程序文件 (/opt/snapsync)"
    echo "  ✓ 所有配置文件 (/etc/snapsync)"
    echo "  ✓ 所有日志文件 (/var/log/snapsync)"
    echo "  ✓ 所有系统服务"
    echo "  ✓ 所有命令快捷方式"
    echo "  ? 备份文件 (询问)"
    echo "  ? 源代码目录 (询问)"
    echo ""
    
    # 第一次确认
    read -p "确认卸载 SnapSync? [y/N]: " confirm1
    
    if [[ ! "$confirm1" =~ ^[Yy]$ ]]; then
        log "已取消"
        pause
        return
    fi
    
    # 第二次确认（输入验证码）
    echo ""
    log "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${RED}最终确认: 请输入 'YES DELETE' 继续卸载${NC}"
    log "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -p "> " confirm2
    
    if [[ "$confirm2" != "YES DELETE" ]]; then
        log "已取消"
        pause
        return
    fi
    
    log "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${CYAN}开始卸载...${NC}"
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    # 1. 停止并禁用服务
    log "${YELLOW}[1/9] 停止服务...${NC}"
    systemctl stop snapsync-bot 2>/dev/null || true
    systemctl stop snapsync-backup.timer 2>/dev/null || true
    systemctl disable snapsync-bot 2>/dev/null || true
    systemctl disable snapsync-backup.timer 2>/dev/null || true
    log "${GREEN}  ✓ 服务已停止${NC}"
    
    # 2. 删除服务文件
    log "${YELLOW}[2/9] 删除服务文件...${NC}"
    rm -f /etc/systemd/system/snapsync-bot.service
    rm -f /etc/systemd/system/snapsync-backup.service
    rm -f /etc/systemd/system/snapsync-backup.timer
    systemctl daemon-reload
    log "${GREEN}  ✓ 服务文件已删除${NC}"
    
    # 3. 删除命令快捷方式
    log "${YELLOW}[3/9] 删除命令快捷方式...${NC}"
    rm -f /usr/local/bin/snapsync
    rm -f /usr/local/bin/snapsync-backup
    rm -f /usr/local/bin/snapsync-restore
    rm -f /usr/local/bin/telegram-test
    log "${GREEN}  ✓ 命令快捷方式已删除${NC}"
    
    # 4. 删除程序文件
    log "${YELLOW}[4/9] 删除程序文件...${NC}"
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        log "${GREEN}  ✓ 程序文件已删除: $INSTALL_DIR${NC}"
    else
        log "${YELLOW}  ⚠ 程序目录不存在${NC}"
    fi
    
    # 5. 询问是否删除配置
    echo ""
    log "${YELLOW}[5/9] 配置文件处理...${NC}"
    read -p "是否删除配置文件? [y/N]: " del_config
    if [[ "$del_config" =~ ^[Yy]$ ]]; then
        if [[ -d "$CONFIG_DIR" ]]; then
            rm -rf "$CONFIG_DIR"
            log "${GREEN}  ✓ 配置文件已删除: $CONFIG_DIR${NC}"
        fi
    else
        log "${YELLOW}  ⊙ 配置文件已保留: $CONFIG_DIR${NC}"
    fi
    
    # 6. 询问是否删除日志
    echo ""
    log "${YELLOW}[6/9] 日志文件处理...${NC}"
    read -p "是否删除日志文件? [y/N]: " del_logs
    if [[ "$del_logs" =~ ^[Yy]$ ]]; then
        if [[ -d "$LOG_DIR" ]]; then
            rm -rf "$LOG_DIR"
            log "${GREEN}  ✓ 日志文件已删除: $LOG_DIR${NC}"
        fi
    else
        log "${YELLOW}  ⊙ 日志文件已保留: $LOG_DIR${NC}"
    fi
    
    # 7. 询问是否删除备份
    echo ""
    log "${YELLOW}[7/9] 备份文件处理...${NC}"
    
    # 加载配置获取备份目录
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE" 2>/dev/null || true
    fi
    local backup_dir="${BACKUP_DIR:-/backups}"
    
    if [[ -d "$backup_dir/system_snapshots" ]]; then
        local snapshot_count=$(find "$backup_dir/system_snapshots" -name "*.tar*" -type f 2>/dev/null | wc -l)
        log "  发现 ${snapshot_count} 个备份文件"
        
        echo ""
        log "${RED}  ⚠️  警告: 删除备份将无法恢复系统！${NC}"
        read -p "是否删除所有备份? [y/N]: " del_backups
        if [[ "$del_backups" =~ ^[Yy]$ ]]; then
            rm -rf "$backup_dir/system_snapshots"
            log "${GREEN}  ✓ 备份文件已删除: $backup_dir/system_snapshots${NC}"
        else
            log "${YELLOW}  ⊙ 备份文件已保留: $backup_dir/system_snapshots${NC}"
        fi
    else
        log "${YELLOW}  ⚠ 未找到备份目录${NC}"
    fi
    
    # 8. 询问是否删除源代码目录（新增）
    echo ""
    log "${YELLOW}[8/9] 源代码目录处理...${NC}"
    
    # 检测可能的源代码目录
    local source_dirs=()
    
    # 常见的源代码位置
    [[ -d "/root/SnapSync" ]] && source_dirs+=("/root/SnapSync")
    [[ -d "/root/snapsync" ]] && source_dirs+=("/root/snapsync")
    [[ -d "$HOME/SnapSync" ]] && source_dirs+=("$HOME/SnapSync")
    [[ -d "$HOME/snapsync" ]] && source_dirs+=("$HOME/snapsync")
    
    # 查找当前目录是否为源代码目录
    if [[ -f "$(pwd)/install.sh" && -f "$(pwd)/snapsync.sh" ]]; then
        local current_dir="$(pwd)"
        # 检查是否已在列表中
        local already_added=0
        for dir in "${source_dirs[@]}"; do
            if [[ "$dir" == "$current_dir" ]]; then
                already_added=1
                break
            fi
        done
        [[ $already_added -eq 0 ]] && source_dirs+=("$current_dir")
    fi
    
    if [[ ${#source_dirs[@]} -gt 0 ]]; then
        log "  发现以下源代码目录:"
        for dir in "${source_dirs[@]}"; do
            echo "    • $dir"
        done
        echo ""
        
        read -p "是否删除这些源代码目录? [y/N]: " del_source
        if [[ "$del_source" =~ ^[Yy]$ ]]; then
            for dir in "${source_dirs[@]}"; do
                if [[ -d "$dir" ]]; then
                    # 如果当前在要删除的目录中，先切换到其他目录
                    if [[ "$(pwd)" == "$dir"* ]]; then
                        cd /root 2>/dev/null || cd / 2>/dev/null
                        log "  → 已切换工作目录"
                    fi
                    
                    rm -rf "$dir"
                    log "${GREEN}  ✓ 已删除: $dir${NC}"
                fi
            done
        else
            log "${YELLOW}  ⊙ 源代码目录已保留${NC}"
        fi
    else
        log "${YELLOW}  ⚠ 未找到源代码目录${NC}"
    fi
    
    # 9. 清理临时文件
    echo ""
    log "${YELLOW}[9/9] 清理临时文件...${NC}"
    rm -f /tmp/snapsync_* 2>/dev/null || true
    rm -f /tmp/local_snapshots_*.txt 2>/dev/null || true
    rm -f /tmp/remote_snapshots_*.txt 2>/dev/null || true
    rm -f /tmp/delete_snapshots_*.txt 2>/dev/null || true
    rm -f /tmp/restore_err.log 2>/dev/null || true
    log "${GREEN}  ✓ 临时文件已清理${NC}"
    
    # 完成
    echo ""
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${GREEN}✓✓✓ 卸载完成！✓✓✓${NC}"
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    log "已从系统中移除 SnapSync"
    echo ""
    
    log "${YELLOW}已删除：${NC}"
    echo "  ✓ 程序文件"
    echo "  ✓ 系统服务"
    echo "  ✓ 命令快捷方式"
    
    [[ "$del_config" =~ ^[Yy]$ ]] && echo "  ✓ 配置文件" || echo "  ⊙ 配置文件（保留）"
    [[ "$del_logs" =~ ^[Yy]$ ]] && echo "  ✓ 日志文件" || echo "  ⊙ 日志文件（保留）"
    [[ "$del_backups" =~ ^[Yy]$ ]] && echo "  ✓ 备份文件" || echo "  ⊙ 备份文件（保留）"
    [[ "$del_source" =~ ^[Yy]$ ]] && echo "  ✓ 源代码目录" || echo "  ⊙ 源代码目录（保留）"
    
    echo ""
    log "${CYAN}感谢使用 SnapSync！${NC}"
    echo ""
    
    pause
    
    # 退出脚本
    exit 0
}

# ===== 主程序 =====
main() {
    # 检查安装
    if [[ ! -d "$INSTALL_DIR" ]]; then
        log "${RED}错误: SnapSync 未正确安装${NC}"
        log "${YELLOW}请运行安装脚本: sudo bash install.sh${NC}"
        exit 1
    fi
    
    # 如果配置文件不存在，创建默认配置
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "${YELLOW}警告: 配置文件不存在，创建默认配置...${NC}"
        mkdir -p "$CONFIG_DIR"
        cat > "$CONFIG_FILE" << 'EOF'
#!/bin/bash
BACKUP_DIR="/backups"
TELEGRAM_ENABLED="false"
REMOTE_ENABLED="false"
LOCAL_KEEP_COUNT="5"
COMPRESSION_LEVEL="6"
PARALLEL_THREADS="auto"
EOF
        chmod 600 "$CONFIG_FILE"
    fi
    
    # 主循环
    while true; do
        show_main_menu
        read -p "请选择 [0-10]: " choice
        
        case "$choice" in
            1) create_snapshot ;;
            2) restore_snapshot ;;
            3) manage_config ;;
            4) list_snapshots ;;
            5) manage_telegram_bot ;;
            6) clean_snapshots ;;
            7) view_logs ;;
            8) show_system_info ;;
            9) upgrade_snapsync ;;
            10) uninstall_snapsync ;;
            0) log "${GREEN}感谢使用!${NC}"; exit 0 ;;
            *) log "${RED}无效选择${NC}"; sleep 1 ;;
        esac
    done
}

main "$@"
