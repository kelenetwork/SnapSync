#!/bin/bash

# SnapSync - Telegram 通知诊断工具
# 帮助排查为什么没有收到通知

set -euo pipefail

# ===== 颜色定义 =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

CONFIG_FILE="/etc/snapsync/config.conf"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  Telegram 通知诊断工具${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ===== 步骤1: 检查配置文件 =====
echo -e "${YELLOW}步骤1: 检查配置文件${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}✗ 配置文件不存在: $CONFIG_FILE${NC}"
    echo "  请先运行: sudo bash install.sh"
    exit 1
else
    echo -e "${GREEN}✓ 配置文件存在${NC}"
fi

# 加载配置
source "$CONFIG_FILE"
echo ""

# ===== 步骤2: 检查配置项 =====
echo -e "${YELLOW}步骤2: 检查Telegram配置${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -n "TELEGRAM_ENABLED: "
if [[ "${TELEGRAM_ENABLED}" == "Y" || "${TELEGRAM_ENABLED}" == "true" ]]; then
    echo -e "${GREEN}${TELEGRAM_ENABLED}${NC}"
else
    echo -e "${RED}${TELEGRAM_ENABLED}${NC}"
    echo -e "${RED}✗ Telegram未启用！${NC}"
    echo ""
    echo "修复方法:"
    echo "  sudo nano /etc/snapsync/config.conf"
    echo "  修改: TELEGRAM_ENABLED=\"true\""
    exit 1
fi

echo -n "TELEGRAM_BOT_TOKEN: "
if [[ -z "${TELEGRAM_BOT_TOKEN}" ]]; then
    echo -e "${RED}未设置${NC}"
    echo -e "${RED}✗ Bot Token未配置！${NC}"
    exit 1
else
    echo -e "${GREEN}${TELEGRAM_BOT_TOKEN:0:20}...${NC} (${#TELEGRAM_BOT_TOKEN}字符)"
fi

echo -n "TELEGRAM_CHAT_ID: "
if [[ -z "${TELEGRAM_CHAT_ID}" ]]; then
    echo -e "${RED}未设置${NC}"
    echo -e "${RED}✗ Chat ID未配置！${NC}"
    exit 1
else
    echo -e "${GREEN}${TELEGRAM_CHAT_ID}${NC}"
fi

echo ""

# ===== 步骤3: 测试网络连接 =====
echo -e "${YELLOW}步骤3: 测试网络连接${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -n "测试 Telegram API 可达性... "
if curl -sS -m 10 https://api.telegram.org &>/dev/null; then
    echo -e "${GREEN}✓ 可访问${NC}"
else
    echo -e "${RED}✗ 无法访问${NC}"
    echo ""
    echo "网络问题！可能的原因:"
    echo "  1. 服务器无法访问 Telegram"
    echo "  2. 防火墙阻止"
    echo "  3. 需要代理"
    exit 1
fi

echo ""

# ===== 步骤4: 测试Bot API =====
echo -e "${YELLOW}步骤4: 测试Bot API${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "调用 getMe API..."
response=$(curl -sS -m 10 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe")

if echo "$response" | grep -q '"ok":true'; then
    echo -e "${GREEN}✓ Bot API 响应正常${NC}"
    
    # 提取Bot信息
    bot_username=$(echo "$response" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
    bot_firstname=$(echo "$response" | grep -o '"first_name":"[^"]*"' | cut -d'"' -f4)
    
    echo "  Bot 用户名: @${bot_username}"
    echo "  Bot 名称: ${bot_firstname}"
else
    echo -e "${RED}✗ Bot API 响应失败${NC}"
    echo ""
    echo "响应内容:"
    echo "$response"
    echo ""
    echo "可能的原因:"
    echo "  1. Bot Token 错误"
    echo "  2. Bot 已被删除"
    exit 1
fi

echo ""

# ===== 步骤5: 测试发送消息 =====
echo -e "${YELLOW}步骤5: 测试发送消息${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_message="🔍 <b>Telegram 诊断测试</b>

✅ 如果你看到这条消息，说明配置正确！

🖥️ 主机: $(hostname)
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')

<i>这是诊断工具自动发送的测试消息</i>"

echo "正在发送测试消息到 Chat ID: ${TELEGRAM_CHAT_ID}..."
send_response=$(curl -sS -m 15 -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${test_message}" \
    -d "parse_mode=HTML")

if echo "$send_response" | grep -q '"ok":true'; then
    echo -e "${GREEN}✓ 测试消息发送成功！${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓✓✓ 所有检查通过！✓✓✓${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "请检查 Telegram 是否收到测试消息"
    echo ""
    echo "如果收到消息，说明配置完全正确！"
    echo "如果没收到，可能是："
    echo "  1. Chat ID 错误"
    echo "  2. 需要先向 Bot 发送 /start"
    echo ""
else
    echo -e "${RED}✗ 发送消息失败${NC}"
    echo ""
    echo "响应内容:"
    echo "$send_response"
    echo ""
    
    # 分析错误
    if echo "$send_response" | grep -q "chat not found"; then
        echo "错误原因: Chat ID 不存在或错误"
        echo ""
        echo "解决方法:"
        echo "  1. 先在 Telegram 向 Bot 发送 /start"
        echo "  2. 重新获取 Chat ID:"
        echo "     访问: https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates"
        echo "     找到 chat.id 字段"
    elif echo "$send_response" | grep -q "bot was blocked"; then
        echo "错误原因: Bot 被用户屏蔽"
        echo ""
        echo "解决方法:"
        echo "  在 Telegram 中解除对 Bot 的屏蔽"
    else
        echo "未知错误，请检查上述响应内容"
    fi
    exit 1
fi

echo ""

# ===== 步骤6: 检查备份脚本 =====
echo -e "${YELLOW}步骤6: 检查备份脚本${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

BACKUP_SCRIPT="/opt/snapsync/modules/backup.sh"

if [[ ! -f "$BACKUP_SCRIPT" ]]; then
    echo -e "${RED}✗ 备份脚本不存在${NC}"
    exit 1
fi

# 检查是否有send_telegram函数
if grep -q "send_telegram" "$BACKUP_SCRIPT"; then
    echo -e "${GREEN}✓ 备份脚本包含通知函数${NC}"
else
    echo -e "${RED}✗ 备份脚本缺少通知函数${NC}"
    echo "  需要更新 backup.sh 到最新版本"
fi

# 检查是否调用通知
if grep -q 'send_telegram.*开始备份' "$BACKUP_SCRIPT"; then
    echo -e "${GREEN}✓ 备份脚本会发送开始通知${NC}"
else
    echo -e "${YELLOW}⚠ 备份脚本可能不会发送开始通知${NC}"
fi

if grep -q 'send_telegram.*备份完成' "$BACKUP_SCRIPT"; then
    echo -e "${GREEN}✓ 备份脚本会发送完成通知${NC}"
else
    echo -e "${YELLOW}⚠ 备份脚本可能不会发送完成通知${NC}"
fi

echo ""

# ===== 总结 =====
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  诊断完成${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "下一步:"
echo "  1. 确认收到测试消息"
echo "  2. 运行一次备份测试:"
echo "     ${GREEN}sudo snapsync-backup${NC}"
echo "  3. 检查是否收到备份通知"
echo ""
echo "如果仍然没有通知，查看日志:"
echo "  ${CYAN}sudo tail -f /var/log/snapsync/backup.log | grep TG${NC}"
echo ""
