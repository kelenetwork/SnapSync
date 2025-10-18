# SnapSync v3.0 🚀

<div align="center">

![Version](https://img.shields.io/badge/version-3.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Shell](https://img.shields.io/badge/shell-bash-yellow.svg)

**专业级 Linux 系统无损快照与恢复工具**

[功能特性](#-功能特性) • [快速开始](#-快速开始) • [使用指南](#-使用指南) • [Telegram Bot](#-telegram-bot) • [常见问题](#-常见问题)

</div>

---

## 📋 功能特性

### 核心功能
✅ **无损备份恢复** - 完整保留文件权限、ACL、扩展属性  
✅ **统一管理菜单** - 备份、恢复、配置一站式管理  
✅ **智能依赖检测** - 自动识别并安装所需依赖  
✅ **远程存储支持** - 可选上传至远程服务器  
✅ **Telegram Bot 控制** - 远程管理快照和配置  

### 技术特性
- **多线程压缩** - 使用 pigz 加速备份过程
- **完整性验证** - SHA256 校验确保数据安全
- **增量备份** - 支持基于时间戳的增量备份
- **断点续传** - rsync 确保大文件传输可靠性
- **资源智能调度** - 自动调整系统资源占用

---

## 🚀 快速开始

### 一键安装

```bash
# 克隆项目
git clone https://github.com/kelenetwork/SnapSync.git
cd SnapSync

# 赋予执行权限
chmod +x snapsync.sh

# 运行安装
sudo ./snapsync.sh
```

### 系统要求

- **操作系统**: Ubuntu 18.04+ / Debian 9+ / CentOS 7+ / RHEL 7+
- **权限**: Root 或 sudo
- **磁盘空间**: 建议至少系统空间的 2 倍
- **网络**: (可选) 用于远程备份和 Telegram 通知

### 自动安装的依赖

安装脚本会自动检测并安装以下工具：

**基础工具**: tar, gzip, curl, rsync, jq, bc  
**压缩工具**: pigz (多线程), bzip2, xz-utils  
**高级功能**: acl (ACL 支持), attr (扩展属性)  
**可选工具**: sshpass (密码认证), pv (进度显示)

---

## 📖 使用指南

### 主菜单

运行主脚本后，你将看到统一的管理菜单：

```bash
sudo ./snapsync.sh
```

```
╔════════════════════════════════════════════╗
║       SnapSync v3.0 管理控制台            ║
╚════════════════════════════════════════════╝

1) 📸 创建系统快照
2) 🔄 恢复系统快照
3) ⚙️  配置管理
4) 📊 查看快照列表
5) 🤖 Telegram Bot 设置
6) 🗑️  清理旧快照
7) ❓ 帮助文档
8) 🚪 退出

请选择操作 [1-8]:
```

### 创建快照

选择菜单项 `1` 创建快照：

1. **自动模式**: 直接创建快照并根据配置决定是否上传
2. **选择上传**: 可选择仅本地保存或同时上传到远程

```bash
📸 创建系统快照
━━━━━━━━━━━━━━━━━━━━━━━━━
是否上传到远程服务器？[Y/n]:
```

快照特性：
- ✅ 保留完整的文件权限和所有权
- ✅ 保留 ACL (访问控制列表)
- ✅ 保留扩展属性 (xattr)
- ✅ 保留符号链接和硬链接
- ✅ 自动生成 SHA256 校验和

### 恢复快照

选择菜单项 `2` 恢复系统：

1. **本地恢复**: 从本地备份目录选择快照
2. **远程恢复**: 从远程服务器下载并恢复

```bash
🔄 系统恢复
━━━━━━━━━━━━━━━━━━━━━━━━━
可用快照:
1) system_snapshot_20250118.tar.gz (2.5GB, 2025-01-18 10:30)
2) system_snapshot_20250117.tar.gz (2.4GB, 2025-01-17 08:15)

恢复模式:
1) 🛡️ 智能恢复 - 保留网络和SSH配置
2) 🔧 完全恢复 - 恢复所有内容

请选择快照 [1-2]:
```

### 配置管理

选择菜单项 `3` 管理配置：

```bash
⚙️ 配置管理
━━━━━━━━━━━━━━━━━━━━━━━━━
1) 修改远程服务器配置
2) 修改 Telegram 配置
3) 修改保留策略
4) 修改定时任务
5) 查看当前配置
6) 返回主菜单

请选择 [1-6]:
```

配置文件位置: `/etc/snapsync/config.conf`

---

## 🤖 Telegram Bot

### Bot 功能

SnapSync 的 Telegram Bot 不仅用于通知，还能远程管理：

**通知功能**:
- 📸 快照创建开始/完成通知
- ⬆️ 上传进度和结果通知
- ❌ 错误和警告提醒
- 📊 定期状态报告

**控制功能**:
- `/status` - 查看系统状态
- `/list` - 列出所有快照
- `/create` - 创建新快照
- `/delete <id>` - 删除指定快照
- `/config` - 查看配置
- `/setconfig <key> <value>` - 修改配置
- `/help` - 查看帮助

### Bot 设置

1. **创建 Telegram Bot**:
   - 在 Telegram 中找到 @BotFather
   - 发送 `/newbot` 创建新 bot
   - 获取 Bot Token

2. **获取 Chat ID**:
   - 向你的 bot 发送任意消息
   - 访问 `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
   - 在返回的 JSON 中找到 `chat.id`

3. **配置 Bot**:
   ```bash
   sudo ./snapsync.sh
   # 选择: 5) Telegram Bot 设置
   ```

4. **启动 Bot 服务**:
   ```bash
   systemctl enable snapsync-bot
   systemctl start snapsync-bot
   ```

### Bot 使用示例

```
你: /status
Bot: 
📊 系统状态
━━━━━━━━━━━━━━━━
主机: server-01
快照总数: 5 个
最新快照: system_snapshot_20250118.tar.gz
快照大小: 2.5GB
磁盘使用: 45%
下次备份: 2025-01-19 10:00

你: /list
Bot:
📋 快照列表
━━━━━━━━━━━━━━━━
1. system_snapshot_20250118.tar.gz
   大小: 2.5GB | 2025-01-18 10:30
   
2. system_snapshot_20250117.tar.gz
   大小: 2.4GB | 2025-01-17 08:15

你: /delete 2
Bot: 
🗑️ 快照删除确认
确认删除快照 system_snapshot_20250117.tar.gz?
回复 /confirm_delete_2 确认删除

你: /confirm_delete_2
Bot: ✅ 快照已删除
```

---

## 📂 目录结构

```
/etc/snapsync/              # 配置目录
├── config.conf             # 主配置文件
└── bot_config.conf         # Bot 配置文件

/var/log/snapsync/          # 日志目录
├── backup.log              # 备份日志
├── restore.log             # 恢复日志
└── bot.log                 # Bot 日志

/opt/snapsync/              # 程序目录
├── snapsync.sh             # 主脚本
├── modules/                # 功能模块
│   ├── backup.sh
│   ├── restore.sh
│   ├── config.sh
│   └── telegram.sh
└── bot/                    # Bot 服务
    └── telegram_bot.sh

<本地备份目录>/             # 默认 /backups
├── system_snapshots/       # 快照文件
├── metadata/               # 元数据
└── checksums/              # 校验和
```

---

## ⚙️ 配置说明

### 主配置文件

`/etc/snapsync/config.conf`:

```bash
# Telegram 配置
TELEGRAM_BOT_TOKEN="your_bot_token_here"
TELEGRAM_CHAT_ID="your_chat_id_here"

# 远程服务器配置
REMOTE_ENABLED="true"
REMOTE_HOST="192.168.1.100"
REMOTE_USER="root"
REMOTE_PORT="22"
REMOTE_PATH="/backups/server-01"

# 备份配置
BACKUP_DIR="/backups"
COMPRESSION_LEVEL="6"
PARALLEL_THREADS="auto"

# 保留策略
LOCAL_KEEP_COUNT="5"
REMOTE_KEEP_DAYS="30"

# 定时任务
AUTO_BACKUP_ENABLED="true"
BACKUP_INTERVAL="7d"
BACKUP_TIME="03:00"
```

### 修改配置

**方法 1 - 通过菜单**:
```bash
sudo ./snapsync.sh
# 选择: 3) 配置管理
```

**方法 2 - 编辑文件**:
```bash
sudo nano /etc/snapsync/config.conf
# 修改后重启服务
sudo systemctl restart snapsync.timer
```

**方法 3 - 通过 Telegram Bot**:
```
/setconfig BACKUP_INTERVAL 3d
```

---

## 🔧 高级功能

### 手动触发备份

```bash
# 立即创建快照（使用配置的上传设置）
sudo systemctl start snapsync-backup

# 或通过主脚本
sudo ./snapsync.sh
# 选择: 1) 创建系统快照
```

### 查看日志

```bash
# 备份日志
tail -f /var/log/snapsync/backup.log

# 恢复日志
tail -f /var/log/snapsync/restore.log

# Bot 日志
tail -f /var/log/snapsync/bot.log
```

### 定时任务管理

```bash
# 查看状态
systemctl status snapsync.timer

# 查看下次运行时间
systemctl list-timers snapsync.timer

# 禁用自动备份
systemctl disable snapsync.timer

# 启用自动备份
systemctl enable snapsync.timer
```

### 快照清理

```bash
# 通过菜单清理
sudo ./snapsync.sh
# 选择: 6) 清理旧快照

# 手动清理本地
find /backups/system_snapshots -name "*.tar.gz" -mtime +30 -delete

# 通过 Telegram Bot
/delete <snapshot_id>
```

---

## 🛠️ 故障排除

### 常见问题

**问题: 权限不足**
```bash
错误: 请使用 root 权限运行
解决: sudo ./snapsync.sh
```

**问题: SSH 连接失败**
```bash
错误: 无法连接远程服务器
解决: 
1. 检查 SSH 配置: ssh user@host -p port
2. 确认密钥或密码正确
3. 检查防火墙设置
```

**问题: 磁盘空间不足**
```bash
错误: 磁盘空间不足
解决:
1. 清理旧快照
2. 增加磁盘空间
3. 修改 BACKUP_DIR 到更大的分区
```

**问题: Telegram 通知失败**
```bash
错误: Telegram 通知发送失败
解决:
1. 验证 Bot Token 和 Chat ID
2. 检查网络连接
3. 测试: curl https://api.telegram.org/bot<TOKEN>/getMe
```

### 日志分析

```bash
# 查看最近的错误
grep ERROR /var/log/snapsync/backup.log | tail -20

# 查看特定时间段的日志
grep "2025-01-18" /var/log/snapsync/backup.log

# 查看成功的备份
grep "备份完成" /var/log/snapsync/backup.log
```

### 恢复测试

建议在虚拟机或测试环境中验证恢复流程：

```bash
# 1. 创建测试快照
sudo ./snapsync.sh
# 选择: 1) 创建系统快照

# 2. 记录系统状态
df -h > /tmp/before_restore.txt
ls -la /etc > /tmp/etc_before.txt

# 3. 执行恢复测试
sudo ./snapsync.sh
# 选择: 2) 恢复系统快照

# 4. 验证恢复结果
diff /tmp/before_restore.txt <(df -h)
```

---

## 📊 性能优化

### 压缩级别调整

```bash
# 更快的备份（压缩率低）
COMPRESSION_LEVEL="1"

# 平衡模式（推荐）
COMPRESSION_LEVEL="6"

# 更高压缩率（速度慢）
COMPRESSION_LEVEL="9"
```

### 并行线程

```bash
# 自动检测（推荐）
PARALLEL_THREADS="auto"

# 手动指定
PARALLEL_THREADS="4"
```

### 排除目录

编辑备份脚本的排除列表以加快速度：

```bash
# 在 /opt/snapsync/modules/backup.sh 中添加
EXCLUDE_DIRS+=(
    "var/cache/apt"
    "var/tmp"
    "home/*/.cache"
)
```

---

## 🔐 安全建议

1. **保护配置文件**:
   ```bash
   chmod 600 /etc/snapsync/config.conf
   ```

2. **使用 SSH 密钥认证**:
   ```bash
   ssh-keygen -t ed25519
   ssh-copy-id user@remote-host
   ```

3. **加密敏感数据**:
   ```bash
   # 使用 gpg 加密快照
   gpg --encrypt --recipient your@email.com snapshot.tar.gz
   ```

4. **定期验证备份**:
   ```bash
   # 验证校验和
   sha256sum -c snapshot.tar.gz.sha256
   ```

---

## 🔄 更新日志

### v3.0 (2025-01-18)
- ✨ 统一管理菜单系统
- 🤖 增强 Telegram Bot 控制功能
- 🔧 自动依赖检测和安装
- 📸 简化快照创建流程
- 🛡️ 默认无损备份恢复
- 📊 改进配置管理界面

### v2.5 (2024-12-15)
- 增量备份支持
- ACL 和扩展属性保留
- 多线程压缩优化
- 完整性验证机制

---

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

1. Fork 项目
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

---

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情

---

## 📞 支持

- 🐛 问题反馈: [GitHub Issues](https://github.com/kelenetwork/snapsync/issues)
- 💬 讨论交流: [GitHub Discussions](https://github.com/kelenetwork/snapsync/discussions)
- 📧 邮件支持: snapsync-support@kele.my
- 📖 文档: [Wiki](https://github.com/kelenetwork/snapsync/wiki)

---

<div align="center">

**SnapSync v3.0** - 让系统快照变得简单、安全、可靠

Made with ❤️ by [Kele Network](https://github.com/kelenetwork)

[⬆ 回到顶部](#snapsync-v30-)

</div>
