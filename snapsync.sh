#!/bin/bash

# SnapSync v3.0 - 主控制脚本（修复版）
# 修复：
# 1. 主菜单显示问题 - 增加错误处理
# 2. 快照数量统计更健壮
# 3. 磁盘使用率获取更安全

set -euo pipefail

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

show_header() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${CYAN}       SnapSync v3.0 管理控制台            ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
    echo ""
}

show_status_bar() {
    # 修复：增加错误处理和默认值
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
    echo -e "  ${GREEN}9)${NC} 🧹 完全卸载"
    echo -e "  ${RED}0)${NC} 🚪 退出"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# [其他函数保持不变，只在文件末尾添加]

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
EOF
        chmod 600 "$CONFIG_FILE"
    fi
    
    # 主循环
    while true; do
        show_main_menu
        read -p "请选择 [0-9]: " choice
        
        case "$choice" in
            1) create_snapshot ;;
            2) restore_snapshot ;;
            3) manage_config ;;
            4) list_snapshots ;;
            5) manage_telegram_bot ;;
            6) clean_snapshots ;;
            7) view_logs ;;
            8) show_system_info ;;
            9) uninstall_snapsync ;;
            0) log "${GREEN}感谢使用!${NC}"; exit 0 ;;
            *) log "${RED}无效选择${NC}"; sleep 1 ;;
        esac
    done
}

main "$@"
