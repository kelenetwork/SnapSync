#!/bin/bash

# SnapSync v3.0 - Bot服务修复脚本

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  SnapSync Bot 服务修复工具${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 需要 root 权限${NC}"
    exit 1
fi

CONFIG_FILE="/etc/snapsync/config.conf"
BOT_SCRIPT="/opt/snapsync/bot/telegram_bot.sh"
SERVICE_FILE="/etc/systemd/system/snapsync-bot.service"

# 1. 检查配置
echo -e "${YELLOW}[1/6] 检查配置${NC}"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}✗ 配置文件不存在${NC}"
    exit 1
fi

source "$CONFIG_FILE"

tg_enabled=$(echo "${TELEGRAM_ENABLED:-false}" | tr '[:upper:]' '[:lower:]')
if [[ "$tg_enabled" != "y" && "$tg_enabled" != "yes" && "$tg_enabled" != "true" ]]; then
    echo -e "${RED}✗ Telegram未启用${NC}"
    echo "请编辑: sudo nano $CONFIG_FILE"
    echo "设置: TELEGRAM_ENABLED=\"true\""
    exit 1
fi

echo -e "${GREEN}✓ 配置检查通过${NC}"

# 2. 检查Bot脚本
echo -e "${YELLOW}[2/6] 检查Bot脚本${NC}"
if [[ ! -f "$BOT_SCRIPT" ]]; then
    echo -e "${RED}✗ Bot脚本不存在${NC}"
    exit 1
fi

chmod +x "$BOT_SCRIPT"
echo -e "${GREEN}✓ Bot脚本权限已修复${NC}"

# 3. 安装依赖
echo -e "${YELLOW}[3/6] 检查依赖${NC}"
if ! command -v jq &>/dev/null; then
    echo "安装 jq..."
    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y jq
    elif command -v yum &>/dev/null; then
        yum install -y jq
    fi
fi
echo -e "${GREEN}✓ 依赖已安装${NC}"

# 4. 重建服务
echo -e "${YELLOW}[4/6] 重建systemd服务${NC}"
systemctl stop snapsync-bot.service 2>/dev/null || true

cat > "$SERVICE_FILE" << 'EOF'
[Unit]
Description=SnapSync Telegram Bot
Documentation=https://github.com/kelenetwork/snapsync
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/snapsync/bot/telegram_bot.sh
Restart=always
RestartSec=10
User=root
StandardOutput=append:/var/log/snapsync/bot.log
StandardError=append:/var/log/snapsync/bot.log
NoNewPrivileges=false
PrivateTmp=false
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

mkdir -p /var/log/snapsync
chmod 755 /var/log/snapsync

systemctl daemon-reload
echo -e "${GREEN}✓ 服务文件已创建${NC}"

# 5. 启动服务
echo -e "${YELLOW}[5/6] 启动服务${NC}"
systemctl enable snapsync-bot.service
systemctl start snapsync-bot.service
sleep 3

# 6. 验证
echo -e "${YELLOW}[6/6] 验证状态${NC}"
if systemctl is-active snapsync-bot.service &>/dev/null; then
    echo -e "${GREEN}✓ Bot服务运行中${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ 修复完成！${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "下一步："
    echo "  1. 在Telegram发送: /start"
    echo "  2. 查看日志: sudo tail -f /var/log/snapsync/bot.log"
    echo ""
else
    echo -e "${RED}✗ Bot服务启动失败${NC}"
    echo ""
    echo "查看日志:"
    journalctl -u snapsync-bot -n 50 --no-pager
    exit 1
fi
