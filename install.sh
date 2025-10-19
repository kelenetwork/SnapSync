#!/bin/bash

# SnapSync v3.0 安装脚本 - 修复版
# 修复：
# 1. 依赖包名适配不同系统
# 2. 更智能的包安装逻辑
# 3. 跳过失败的可选包

set -euo pipefail

# ===== 颜色定义 =====
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# ===== 路径定义 =====
INSTALL_DIR="/opt/snapsync"
CONFIG_DIR="/etc/snapsync"
LOG_DIR="/var/log/snapsync"
DEFAULT_BACKUP_DIR="/backups"

# 记录安装源路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ===== 权限检查 =====
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 需要 root 权限${NC}"
    echo -e "${YELLOW}使用: sudo bash $0${NC}"
    exit 1
fi

# ===== 工具函数 =====
log() {
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    echo -e "$(date '+%F %T') $*" | tee -a "$LOG_DIR/install.log"
}

# ===== 检测系统并适配包名 =====
detect_system() {
    log "${CYAN}检测系统信息...${NC}"
    
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_NAME="$ID"
        OS_VERSION="${VERSION_ID:-unknown}"
        log "${GREEN}系统: ${PRETTY_NAME:-$ID}${NC}"
    else
        log "${RED}无法检测系统版本${NC}"
        exit 1
    fi
    
    # 检测包管理器
    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt-get"
        PKG_UPDATE="apt-get update -qq"
        PKG_INSTALL="apt-get install -y -qq"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
        PKG_UPDATE="yum makecache -q"
        PKG_INSTALL="yum install -y -q"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
        PKG_UPDATE="dnf makecache -q"
        PKG_INSTALL="dnf install -y -q"
    else
        log "${RED}错误: 未检测到支持的包管理器${NC}"
        exit 1
    fi
    
    log "${GREEN}包管理器: $PKG_MANAGER${NC}\n"
}

# ===== 安装单个包（修复版）=====
install_package() {
    local pkg="$1"
    local is_optional="${2:-no}"
    
    # 检查是否已安装
    if command -v "$pkg" &>/dev/null; then
        log "  ${GREEN}✓ $pkg${NC} (已存在)"
        return 0
    fi
    
    # 尝试从已安装包中查找
    if dpkg -l 2>/dev/null | grep -q "^ii  $pkg "; then
        log "  ${GREEN}✓ $pkg${NC} (已安装)"
        return 0
    fi
    
    if rpm -q "$pkg" &>/dev/null 2>&1; then
        log "  ${GREEN}✓ $pkg${NC} (已安装)"
        return 0
    fi
    
    # 尝试安装
    log "  安装 $pkg..."
    if eval "$PKG_INSTALL $pkg" >/dev/null 2>&1; then
        log "  ${GREEN}✓ $pkg${NC}"
        return 0
    else
        if [[ "$is_optional" == "yes" ]]; then
            log "  ${YELLOW}⚠ 跳过 $pkg (可选)${NC}"
            return 0
        else
            log "  ${RED}✗ $pkg 安装失败${NC}"
            return 1
        fi
    fi
}

# ===== 安装依赖（修复版）=====
install_dependencies() {
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${CYAN}安装系统依赖${NC}"
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    log "${YELLOW}更新包列表...${NC}"
    eval "$PKG_UPDATE" >/dev/null 2>&1 || log "${YELLOW}⚠ 更新失败，继续${NC}"
    
    # 基础工具（必须安装）
    log "\n${YELLOW}安装基础工具...${NC}"
    
    # 根据系统类型定义包名映射
    declare -A pkg_map
    
    if [[ "$PKG_MANAGER" == "apt-get" ]]; then
        # Debian/Ubuntu 系统
        pkg_map=(
            ["ssh"]="openssh-client"
            ["tar"]="tar"
            ["gzip"]="gzip"
            ["curl"]="curl"
            ["rsync"]="rsync"
            ["jq"]="jq"
            ["bc"]="bc"
            ["find"]="findutils"
        )
    else
        # CentOS/RHEL 系统
        pkg_map=(
            ["ssh"]="openssh-clients"
            ["tar"]="tar"
            ["gzip"]="gzip"
            ["curl"]="curl"
            ["rsync"]="rsync"
            ["jq"]="jq"
            ["bc"]="bc"
            ["find"]="findutils"
        )
    fi
    
    # 安装必需包
    for cmd in ssh tar gzip curl rsync jq bc find; do
        if ! command -v "$cmd" &>/dev/null; then
            local pkg_name="${pkg_map[$cmd]:-$cmd}"
            install_package "$pkg_name" "no" || {
                log "${RED}关键包 $pkg_name 安装失败${NC}"
                # 尝试备选包名
                if [[ "$cmd" == "ssh" ]]; then
                    install_package "openssh" "no" || true
                fi
            }
        else
            log "  ${GREEN}✓ $cmd${NC} (已存在)"
        fi
    done
    
    # 可选工具
    log "\n${YELLOW}安装增强工具...${NC}"
    
    local optional_pkgs="pigz acl attr pv bzip2 xz-utils"
    
    # CentOS/RHEL 使用 xz 而非 xz-utils
    if [[ "$PKG_MANAGER" != "apt-get" ]]; then
        optional_pkgs="pigz acl attr pv bzip2 xz"
    fi
    
    for pkg in $optional_pkgs; do
        install_package "$pkg" "yes"
    done
    
    log "\n${GREEN}✓ 依赖安装完成${NC}\n"
}

# [保留原有的其他函数...]

# 这里只展示关键修复，其他函数保持不变
