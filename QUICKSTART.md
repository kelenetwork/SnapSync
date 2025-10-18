# SnapSync v3.0 快速入门指南 ⚡

## 5 分钟快速部署

### 第一步：安装 SnapSync

```bash
# 下载项目
git clone https://github.com/kelenetwork/SnapSync.git
cd SnapSync

# 运行安装脚本
sudo bash install.sh
```

安装脚本会自动：
- ✅ 检测系统并安装所有依赖
- ✅ 引导你完成配置向导
- ✅ 设置 SSH 密钥（如果需要远程备份）
- ✅ 创建系统服务和定时任务

### 第二步：首次备份

安装完成后，立即创建第一个快照：

```bash
sudo snapsync
# 或直接运行
sudo snapsync-backup
```

在菜单中选择 `1) 创建系统快照`，等待完成。

### 第三步：验证备份

```bash
# 查看快照列表
sudo snapsync
# 选择: 4) 查看快照列表

# 或使用命令
ls -lh /backups/system_snapshots/
```

---

## Telegram Bot 快速设置 🤖

### 1. 创建 Telegram Bot

1. 在 Telegram 中找到 [@BotFather](https://t.me/botfather)
2. 发送 `/newbot` 并按提示操作
3. 获得 Bot Token (格式: `110201543:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw`)

### 2. 获取 Chat ID

1. 向你的 bot 发送任意消息
2. 访问：`https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
3. 找到 `"chat":{"id":123456789}`

### 3. 配置并启动

在安装时输入 Bot Token 和 Chat ID，或手动编辑：

```bash
sudo nano /etc/snapsync/config.conf

# 修改以下行
TELEGRAM_ENABLED="true"
TELEGRAM_BOT_TOKEN="你的Bot Token"
TELEGRAM_CHAT_ID="你的Chat ID"

# 重启 Bot 服务
sudo systemctl restart snapsync-bot
```

### 4. 测试 Bot

在 Telegram 中发送 `/start` 给你的 bot，应该收到欢迎消息。

**常用命令：**
- `/status` - 查看系统状态
- `/list` - 列出快照
- `/create` - 创建快照
- `/help` - 查看帮助

---

## 远程备份设置 🌐

### SSH 密钥方式（推荐）

安装向导会自动生成密钥并提示你添加到远程服务器。

**手动设置：**

```bash
# 1. 生成密钥（如果没有）
ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519

# 2. 复制公钥到远程服务器
ssh-copy-id -i /root/.ssh/id_ed25519.pub root@远程IP

# 3. 测试连接
ssh -i /root/.ssh/id_ed25519 root@远程IP
```

### 配置远程路径

```bash
sudo nano /etc/snapsync/config.conf

# 修改以下行
REMOTE_ENABLED="true"
REMOTE_HOST="192.168.1.100"
REMOTE_USER="root"
REMOTE_PORT="22"
REMOTE_PATH="/backups/server-01"
```

---

## 常见任务示例 📝

### 立即创建备份

```bash
# 方式 1: 使用控制台
sudo snapsync
# 选择: 1) 创建系统快照

# 方式 2: 直接命令
sudo snapsync-backup

# 方式 3: 通过 Telegram
# 发送: /create
```

### 恢复系统

```bash
# 打开控制台
sudo snapsync
# 选择: 2) 恢复系统快照

# 选择恢复方式:
# 1) 本地恢复 - 从本地备份
# 2) 远程恢复 - 从远程服务器下载

# 选择恢复模式:
# 1) 智能恢复 - 保留网络配置（推荐）
# 2) 完全恢复 - 恢复所有内容
```

### 查看和删除快照

```bash
# 查看本地快照
ls -lh /backups/system_snapshots/

# 通过控制台删除
sudo snapsync
# 选择: 6) 清理旧快照

# 通过 Telegram 删除
# 发送: /list
# 发送: /delete 2  (删除编号 2 的快照)
```

### 修改配置

```bash
# 方式 1: 通过控制台
sudo snapsync
# 选择: 3) 配置管理

# 方式 2: 编辑配置文件
sudo nano /etc/snapsync/config.conf

# 方式 3: 通过 Telegram
# 发送: /setconfig LOCAL_KEEP_COUNT 10
```

### 查看日志

```bash
# 备份日志
tail -f /var/log/snapsync/backup.log

# 恢复日志
tail -f /var/log/snapsync/restore.log

# Bot 日志
tail -f /var/log/snapsync/bot.log

# 或通过 Telegram
# 发送: /logs
```

---

## 定时任务管理 ⏰

### 查看定时任务状态

```bash
# 查看下次运行时间
systemctl list-timers snapsync-backup.timer

# 查看服务状态
systemctl status snapsync-backup.timer
systemctl status snapsync-backup.service
```

### 修改备份时间

```bash
# 编辑配置
sudo nano /etc/snapsync/config.conf

# 修改 BACKUP_TIME（24小时制）
BACKUP_TIME="03:00"  # 每天凌晨3点

# 重新加载配置
sudo systemctl daemon-reload
sudo systemctl restart snapsync-backup.timer
```

### 修改备份间隔

```bash
# 编辑配置
sudo nano /etc/snapsync/config.conf

# 修改间隔天数
BACKUP_INTERVAL_DAYS="7"  # 每7天备份一次

# 重新加载
sudo systemctl daemon-reload
sudo systemctl restart snapsync-backup.timer
```

### 手动触发备份

```bash
# 立即执行一次备份（不影响定时任务）
sudo systemctl start snapsync-backup.service
```

---

## 故障排除 🔧

### 问题：备份失败，磁盘空间不足

```bash
# 检查磁盘空间
df -h /backups

# 清理旧快照
sudo snapsync
# 选择: 6) 清理旧快照

# 或手动删除
sudo rm /backups/system_snapshots/system_snapshot_20250101*.tar.gz
```

### 问题：SSH 连接失败

```bash
# 测试连接
ssh -i /root/.ssh/id_ed25519 root@远程IP

# 检查密钥权限
chmod 700 /root/.ssh
chmod 600 /root/.ssh/id_ed25519

# 查看错误日志
tail -f /var/log/snapsync/backup.log
```

### 问题：Telegram Bot 无响应

```bash
# 检查服务状态
sudo systemctl status snapsync-bot

# 重启服务
sudo systemctl restart snapsync-bot

# 查看日志
sudo journalctl -u snapsync-bot -f

# 测试 API
curl "https://api.telegram.org/bot你的Token/getMe"
```

### 问题：恢复后网络无法连接

如果使用了"完全恢复"模式，网络配置可能被覆盖：

```bash
# 检查网络配置
ip addr show
cat /etc/network/interfaces  # Debian/Ubuntu
cat /etc/netplan/*.yaml      # Ubuntu 18.04+

# 恢复网络配置
sudo systemctl restart networking  # Debian/Ubuntu
sudo netplan apply                 # Ubuntu 18.04+

# 如果仍无法连接，重新配置网络或重启
sudo reboot
```

---

## 最佳实践 ✨

### 1. 定期验证备份

每月至少验证一次备份完整性：

```bash
# 检查校验和
cd /backups/system_snapshots
sha256sum -c *.sha256

# 或通过脚本
for file in *.tar.gz; do
    if [[ -f "$file.sha256" ]]; then
        sha256sum -c "$file.sha256" && echo "✓ $file"
    fi
done
```

### 2. 测试恢复流程

在虚拟机或测试服务器上定期测试恢复：

```bash
# 1. 创建虚拟机（与生产环境相同版本）
# 2. 复制快照到虚拟机
# 3. 执行恢复测试
# 4. 验证服务和数据
```

### 3. 监控存储空间

设置磁盘空间告警：

```bash
# 添加到 crontab
0 */6 * * * df -h /backups | awk 'NR==2 {if(int($5)>80) system("echo 磁盘空间不足: "$5" | mail -s 警告 admin@example.com")}'
```

### 4. 异地备份

将重要快照复制到异地存储：

```bash
# 复制到其他服务器
rsync -avz /backups/system_snapshots/ user@备份服务器:/remote/backups/

# 或上传到云存储（需安装 rclone）
rclone sync /backups/system_snapshots/ remote:bucket/backups/
```

### 5. 备份配置文件

定期备份 SnapSync 配置：

```bash
# 备份配置
sudo cp /etc/snapsync/config.conf /etc/snapsync/config.conf.backup

# 或提交到 Git
cd /etc/snapsync
git init
git add config.conf
git commit -m "Backup config"
```

---

## 性能优化 ⚡

### 调整压缩级别

```bash
# 编辑配置
sudo nano /etc/snapsync/config.conf

# 压缩级别 (1=最快/最低, 9=最慢/最高)
COMPRESSION_LEVEL="6"  # 平衡（推荐）
COMPRESSION_LEVEL="1"  # 快速备份
COMPRESSION_LEVEL="9"  # 最大压缩
```

### 并行线程设置

```bash
# 自动检测 CPU 核心数（推荐）
PARALLEL_THREADS="auto"

# 或手动指定
PARALLEL_THREADS="4"
```

### 排除不必要的目录

编辑 `/opt/snapsync/modules/backup.sh`，在排除列表中添加：

```bash
exclude_patterns=(
    # 默认排除...
    "var/log/*"           # 日志文件
    "home/*/.cache/*"     # 用户缓存
    "var/cache/*"         # 系统缓存
    # 添加你的排除项
)
```

---

## 下一步 🚀

- 📖 阅读完整 [README](README.md) 了解所有功能
- 🤖 探索 [Telegram Bot 高级功能](README.md#-telegram-bot)
- 🔐 查看 [安全建议](README.md#-安全建议)
- 💡 参考 [最佳实践](README.md#-最佳实践)

---

## 获取帮助 📞

- 🐛 [提交 Issue](https://github.com/kelenetwork/snapsync/issues)
- 💬 [讨论区](https://github.com/kelenetwork/snapsync/discussions)
- 📧 邮件: snapsync-support@kele.my

---

<div align="center">

**祝你使用愉快！** 🎉

如果觉得 SnapSync 有用，请给我们一个 ⭐ Star

</div>
