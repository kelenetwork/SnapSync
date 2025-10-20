# SnapSync v3.0 🚀

<div align="center">

![Version](https://img.shields.io/badge/version-3.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Shell](https://img.shields.io/badge/shell-bash-yellow.svg)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey.svg)

**专业级 Linux 系统无损快照与恢复工具**

[功能特性](#-功能特性) • [快速开始](#-快速开始) • [使用指南](#-使用指南) • [Telegram Bot](#-telegram-bot) • [常见问题](#-常见问题)

</div>

---

## 📋 功能特性

### 🎯 核心功能
✅ **无损备份恢复** - 完整保留文件权限、ACL、扩展属性  
✅ **统一管理控制台** - 备份、恢复、配置一站式管理  
✅ **智能依赖检测** - 自动识别并安装所需依赖  
✅ **远程存储支持** - 可选上传至远程服务器  
✅ **Telegram Bot 控制** - 按钮式交互，远程管理快照  
✅ **完整卸载功能** - 彻底清理，无残留  
✅ **实时通知推送** - 每个关键步骤都有通知  

### ⚡ v3.0 新特性
- 🎮 **按钮式Bot交互** - 告别命令式，使用按钮操作
- 🔔 **完整通知系统** - 修复TG通知，支持所有场景
- 🗑️ **完全卸载** - 新增卸载功能，可选保留备份
- 🔧 **完整配置管理** - 所有配置项可视化修改
- 🤖 **Bot服务管理** - 启动、停止、重启、查看日志
- 📊 **实时日志监控** - 支持多种日志查看方式
- 🧪 **诊断工具** - 独立的TG连接测试工具

### 💪 技术特性
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

# 运行安装（自动检测并安装所有依赖）
sudo bash install.sh
```

### 系统要求

- **操作系统**: Ubuntu 18.04+ / Debian 9+ / CentOS 7+ / RHEL 7+
- **权限**: Root 或 sudo
- **磁盘空间**: 建议至少系统空间的 2 倍
- **网络**: (可选) 用于远程备份和 Telegram 通知

### 自动安装的依赖

**基础工具**: tar, gzip, curl, rsync, jq, bc  
**压缩工具**: pigz (多线程), bzip2, xz-utils  
**高级功能**: acl (ACL 支持), attr (扩展属性)  
**可选工具**: sshpass (密码认证), pv (进度显示)

---

## 📖 使用指南

### 主控制台

运行主脚本后，你将看到统一的管理菜单：

```bash
sudo snapsync
```

```
╔════════════════════════════════════════════╗
║       SnapSync v3.0 管理控制台            ║
╚════════════════════════════════════════════╝

主机: server-01 | 快照: 5 | 磁盘: 45%

1) 📸 创建系统快照
2) 🔄 恢复系统快照
3) ⚙️  配置管理
4) 📊 查看快照列表
5) 🤖 Telegram Bot 管理
6) 🗑️  清理旧快照
7) 📋 查看日志
8) ℹ️  系统信息
9) 🧹 完全卸载
0) 🚪 退出

请选择 [0-9]:
```

### 创建快照

**方式1: 使用控制台**
```bash
sudo snapsync
# 选择: 1) 创建系统快照
```

**方式2: 直接命令**
```bash
sudo snapsync-backup
```

**方式3: 通过Telegram Bot**
```
点击 [🔄 创建快照]
点击 [✅ 确认创建]
```

### 快照特性
- ✅ 保留完整的文件权限和所有权
- ✅ 保留 ACL (访问控制列表)
- ✅ 保留扩展属性 (xattr)
- ✅ 保留符号链接和硬链接
- ✅ 自动生成 SHA256 校验和
- ✅ 多线程压缩加速
- ✅ Telegram 实时通知

### 恢复快照

```bash
sudo snapsync
# 选择: 2) 恢复系统快照
```

**恢复模式:**
1. **🛡️ 智能恢复** - 保留网络和SSH配置（推荐）
2. **🔧 完全恢复** - 恢复所有内容（谨慎使用）

**恢复来源:**
1. **📁 本地恢复** - 从本地备份目录选择快照
2. **🌐 远程恢复** - 从远程服务器下载并恢复

---

## 🤖 Telegram Bot

### Bot 功能亮点

SnapSync v3.0 的 Telegram Bot 采用**完全按钮式交互**：

**✨ 按钮式操作**
- 📱 主菜单按钮导航
- ✅ 所有操作都有确认步骤
- 🔙 每个页面都有返回按钮
- 🎯 无需记忆命令

**📊 功能按钮**
- `[📊 系统状态]` - 查看系统和快照状态
- `[📋 快照列表]` - 列出所有快照
- `[🔄 创建快照]` - 创建新快照（带确认）
- `[🗑️ 删除快照]` - 删除指定快照（带确认）
- `[⚙️ 配置管理]` - 查看和修改配置
- `[📝 查看日志]` - 查看各类日志
- `[🔌 测试连接]` - 测试远程和TG连接

**🔔 实时通知**
- 📸 快照创建开始/完成通知
- ⬆️ 上传进度和结果通知
- ❌ 错误和警告提醒
- 💾 磁盘空间警告

**📌 通知格式**
每条通知都会显示主机名，方便识别：
```
🖥️ server-01
━━━━━━━━━━━━━━━━━━━━━━━
✅ 备份完成
📦 2.5GB | ⏱️ 245秒
```

### Bot 设置

**1. 创建 Telegram Bot:**
```
1. 在 Telegram 中找到 @BotFather
2. 发送 /newbot 创建新 bot
3. 获取 Bot Token
   格式: 110201543:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw
```

**2. 获取 Chat ID:**
```
1. 向你的 bot 发送任意消息
2. 访问: https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates
3. 找到 "chat":{"id":123456789}
```

**3. 配置 Bot:**
```bash
sudo snapsync
# 选择: 3) 配置管理
# 选择: 2) 修改 Telegram 配置

# 或者直接编辑
sudo nano /etc/snapsync/config.conf

TELEGRAM_ENABLED="true"
TELEGRAM_BOT_TOKEN="你的Bot Token"
TELEGRAM_CHAT_ID="你的Chat ID"
```

**4. 启动 Bot 服务:**
```bash
sudo systemctl enable snapsync-bot
sudo systemctl start snapsync-bot

# 检查状态
sudo systemctl status snapsync-bot
```

**5. 测试连接:**
```bash
# 方式1: 使用诊断工具
sudo telegram-test

# 方式2: 通过控制台
sudo snapsync
# 选择: 3) 配置管理
# 选择: 7) 测试 Telegram 连接
```

### Bot 使用示例

**查看状态:**
```
你: /start
Bot: [显示主菜单按钮]

你: 点击 [📊 系统状态]
Bot: 
🖥️ server-01
━━━━━━━━━━━━━━━━━━━━━━━
📊 系统状态

运行时间: up 15 days
负载: 0.45
快照: 5个
磁盘: 45%

[🔙 返回主菜单]
```

**创建快照:**
```
你: 点击 [🔄 创建快照]
Bot:
🔄 创建快照

即将创建系统快照

⚠️ 注意:
• 备份需要几分钟
• 期间勿关闭服务器

[✅ 确认创建] [❌ 取消]

你: 点击 [✅ 确认创建]
Bot: 🔄 备份进行中...

(几分钟后)
Bot: ✅ 快照创建成功
```

**删除快照:**
```
你: 点击 [🗑️ 删除快照]
Bot: 
选择要删除的快照:

[1. 01-15 03:00]
[2. 01-08 03:00]
[3. 01-01 03:00]
[🔙 返回]

你: 点击 [2. 01-08 03:00]
Bot:
🗑️ 确认删除

快照: system_snapshot_20250108030000.tar.gz
大小: 2.5GB
时间: 2025-01-08 03:00

⚠️ 此操作不可撤销！

[✅ 确认删除] [❌ 取消]

你: 点击 [✅ 确认删除]
Bot: ✅ 删除成功
```

**配置管理:**
```
你: 点击 [⚙️ 配置管理]
Bot:
⚙️ 配置管理

📦 本地保留: 5 个
🌐 远程保留: 30 天
⏰ 备份间隔: 7 天
🗜️ 压缩级别: 6

[📦 快照保留策略]
[⏰ 备份计划]
[🗜️ 压缩级别]
[🌐 远程备份]
[🔙 返回]
```

### 管理多台服务器

**方案 1: 使用不同的 Bot（推荐）**

每台服务器创建独立的 Bot：
```bash
# 服务器 A
Bot: @ServerA_SnapSync_Bot
Chat ID: 你的Chat ID

# 服务器 B  
Bot: @ServerB_SnapSync_Bot
Chat ID: 你的Chat ID
```

优点：
- ✅ 消息完全隔离，不会混淆
- ✅ 可独立管理每台服务器
- ✅ 按钮操作准确对应服务器

**方案 2: 使用相同 Bot 不同 Chat**

一个 Bot，但使用不同的聊天（需要 Telegram 群组或频道）：
```bash
# 服务器 A
TELEGRAM_CHAT_ID="-1001234567890"  # 群组A

# 服务器 B
TELEGRAM_CHAT_ID="-1009876543210"  # 群组B
```

优点：
- ✅ 只需管理一个 Bot
- ✅ 消息通过不同群组隔离

**方案 3: 共用 Bot 和 Chat（不推荐）**

多台服务器使用相同的 Bot Token 和 Chat ID：
- ⚠️ 所有服务器的消息混在一起
- ⚠️ 按钮操作可能触发错误的服务器
- ⚠️ 难以区分消息来源（仅靠主机名区分）

**最佳实践建议：**
- 如果只有 2-3 台服务器，使用方案1（独立Bot）
- 如果服务器较多（5台以上），使用方案2（群组隔离）
- 避免使用方案3，除非仅用于接收通知

---

## ⚙️ 配置管理

### 完整的配置选项

```bash
sudo snapsync
# 选择: 3) 配置管理
```

**可管理项目：**
1. **修改远程服务器配置** - 服务器地址、端口、路径等
2. **修改 Telegram 配置** - Bot Token、Chat ID等
3. **修改保留策略** - 本地/远程保留数量
4. **查看当前配置** - 显示所有配置项
5. **编辑配置文件** - 直接编辑配置文件
6. **重启服务** - 重启所有相关服务
7. **测试 Telegram 连接** - 验证TG配置

### 配置文件位置

**主配置文件:** `/etc/snapsync/config.conf`

```bash
# Telegram 配置
TELEGRAM_ENABLED="true"
TELEGRAM_BOT_TOKEN="你的Bot Token"
TELEGRAM_CHAT_ID="你的Chat ID"

# 远程备份配置
REMOTE_ENABLED="true"
REMOTE_HOST="192.168.1.100"
REMOTE_USER="root"
REMOTE_PORT="22"
REMOTE_PATH="/backups/server-01"
REMOTE_KEEP_DAYS="30"

# 本地备份配置
BACKUP_DIR="/backups"
COMPRESSION_LEVEL="6"
PARALLEL_THREADS="auto"
LOCAL_KEEP_COUNT="5"

# 定时任务配置
AUTO_BACKUP_ENABLED="true"
BACKUP_INTERVAL_DAYS="7"
BACKUP_TIME="03:00"

# 高级配置
ENABLE_ACL="true"
ENABLE_XATTR="true"
ENABLE_VERIFICATION="true"
```

---

## 📂 目录结构

```
/opt/snapsync/              # 程序目录
├── snapsync.sh             # 主脚本
├── modules/                # 功能模块
│   ├── backup.sh           # 备份模块
│   ├── restore.sh          # 恢复模块
│   └── config.sh           # 配置模块
└── bot/                    # Bot 服务
    └── telegram_bot.sh     # Bot脚本

/etc/snapsync/              # 配置目录
└── config.conf             # 主配置文件

/var/log/snapsync/          # 日志目录
├── backup.log              # 备份日志
├── restore.log             # 恢复日志
├── bot.log                 # Bot日志
└── main.log                # 主日志

/backups/                   # 备份目录（可配置）
├── system_snapshots/       # 快照文件
├── metadata/               # 元数据
└── checksums/              # 校验和
```

---

## 🔧 高级功能

### 手动触发备份

```bash
# 立即创建快照
sudo snapsync-backup

# 或通过控制台
sudo snapsync
# 选择: 1) 创建系统快照
```

### 查看日志

```bash
# 方式1: 通过控制台
sudo snapsync
# 选择: 7) 查看日志

# 方式2: 直接查看
sudo tail -f /var/log/snapsync/backup.log

# 方式3: 实时监控
sudo snapsync
# 7) 查看日志 -> 5) 实时监控备份日志
```

### 定时任务管理

```bash
# 查看状态
systemctl status snapsync-backup.timer

# 查看下次运行时间
systemctl list-timers snapsync-backup.timer

# 禁用自动备份
systemctl disable snapsync-backup.timer

# 启用自动备份
systemctl enable snapsync-backup.timer
```

### 清理快照

```bash
# 通过控制台
sudo snapsync
# 选择: 6) 清理旧快照

# 手动清理（保留最新5个）
find /backups/system_snapshots -name "*.tar.gz" | sort -r | tail -n +6 | xargs rm -f
```

### 完全卸载

```bash
sudo snapsync
# 选择: 9) 完全卸载

# 卸载将删除：
# • 所有程序文件
# • 配置文件（可选）
# • 日志文件（可选）
# • 系统服务
# • 命令快捷方式
# • 源代码目录（可选）
# 
# 备份文件会询问是否保留
```

---

## 🛠️ 故障排除

### TG通知不工作

**使用诊断工具:**
```bash
sudo telegram-test
```

诊断工具会自动检查：
- ✅ 配置文件是否存在
- ✅ TG配置是否正确
- ✅ 网络连接是否正常
- ✅ Bot API是否可用
- ✅ 发送测试消息

**常见问题:**

1. **TELEGRAM_ENABLED未启用**
```bash
sudo nano /etc/snapsync/config.conf
# 改为: TELEGRAM_ENABLED="true"
```

2. **Bot Token或Chat ID错误**
```bash
# 测试Token
curl -sS "https://api.telegram.org/bot<YOUR_TOKEN>/getMe"

# 重新获取Chat ID
# 向Bot发送消息后访问：
https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates
```

3. **网络问题**
```bash
# 测试连接
curl -sS https://api.telegram.org

# 如无法访问，可能需要代理
```

### Bot无响应

```bash
# 检查服务状态
sudo systemctl status snapsync-bot

# 查看日志
sudo tail -50 /var/log/snapsync/bot.log

# 重启服务
sudo systemctl restart snapsync-bot

# 在Telegram重新发送 /start
```

### 删除快照按钮无响应

```bash
# 查看Bot日志寻找错误
sudo tail -100 /var/log/snapsync/bot.log | grep -i "delete\|删除"

# 检查快照目录权限
ls -la /backups/system_snapshots/

# 检查临时文件
ls -la /tmp/snapshots_*.txt

# 重启Bot服务
sudo systemctl restart snapsync-bot
```

### SSH连接失败

```bash
# 测试连接
ssh -i /root/.ssh/id_ed25519 root@远程IP -p 端口

# 检查密钥权限
chmod 700 /root/.ssh
chmod 600 /root/.ssh/id_ed25519

# 查看错误日志
tail -f /var/log/snapsync/backup.log
```

### rsync 命令未找到

**错误信息：**
```bash
bash: line 1: rsync: command not found
rsync: connection unexpectedly closed (0 bytes received so far) [sender]
rsync error: error in rsync protocol data stream (code 12)
```

**原因分析：**

SnapSync 在上传快照时会使用 `rsync` 命令同步文件到远程服务器，但远程主机上没有安装 `rsync`，导致传输中断。

**🔍 错误原因分析**
- 你本地（执行 SnapSync 的机器）有 `rsync`，但远程服务器（你通过 SSH 上传到的那台）缺少 `rsync`
- `rsync` 是 SnapSync 的核心同步工具，必须两边都装

**✅ 解决方法**

在**远程服务器**上执行以下命令安装：

**对于如果是 Debian / Ubuntu 系列:**
```bash
sudo apt-get update
sudo apt-get install -y rsync
```

**或如果远程是 RedHat / CentOS:**
```bash
sudo yum install -y rsync
```

**安装完成后，你可以在远程主机上验证：**
```bash
rsync --version
```

如果显示版本信息，说明安装成功。然后重新执行 SnapSync 的上传操作即可。

---

## 📊 性能优化

### 调整压缩级别

```bash
sudo nano /etc/snapsync/config.conf

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

编辑 `/opt/snapsync/modules/backup.sh`，在排除列表中添加：

```bash
exclude_patterns=(
    # 默认排除...
    "var/cache/apt"
    "var/tmp"
    "home/*/.cache"
    # 添加你的排除项
)
```

---

## 🔐 安全建议

1. **保护配置文件**
```bash
chmod 600 /etc/snapsync/config.conf
```

2. **使用 SSH 密钥认证**
```bash
ssh-keygen -t ed25519
ssh-copy-id user@remote-host
```

3. **加密敏感数据**
```bash
# 使用 gpg 加密快照
gpg --encrypt --recipient your@email.com snapshot.tar.gz
```

4. **定期验证备份**
```bash
# 验证校验和
cd /backups/system_snapshots
sha256sum -c *.sha256
```

---

## 📝 更新日志

### v3.0 (2025-01-18)

**🎮 用户体验**
- ✨ Bot完全重构为按钮式交互
- ✨ 新增完全卸载功能（支持清理源代码目录）
- ✨ 完整的配置管理界面
- ✨ 优化主机名显示

**🔔 通知系统**
- ✅ 修复TG通知功能
- ✅ 新增详细的通知内容
- ✅ 每个关键步骤都有通知
- ✅ 创建独立诊断工具

**🛠️ 功能完善**
- ✅ 实现所有菜单功能
- ✅ Bot服务管理
- ✅ 多种日志查看方式
- ✅ 系统信息展示
- ✅ 删除快照功能优化（修复无响应问题）

**🐛 Bug修复**
- ✅ 修复readonly变量冲突
- ✅ 修复命令未找到问题
- ✅ 修复配置加载错误
- ✅ 修复权限问题
- ✅ 修复删除快照按钮无响应
- ✅ 修复远程快照下载路径处理

### v2.5 (2024-12-15)
- 增量备份支持
- ACL 和扩展属性保留
- 多线程压缩优化
- 完整性验证机制

---

## 💡 最佳实践

### 1. 定期验证备份

```bash
# 每月至少验证一次
cd /backups/system_snapshots
for file in *.tar.gz; do
    [[ -f "$file.sha256" ]] && sha256sum -c "$file.sha256"
done
```

### 2. 测试恢复流程

在虚拟机或测试服务器上定期测试恢复：
1. 创建虚拟机（与生产环境相同版本）
2. 复制快照到虚拟机
3. 执行恢复测试
4. 验证服务和数据

### 3. 监控存储空间

```bash
# 定期检查磁盘空间
df -h /backups

# 设置自动清理
sudo snapsync
# 6) 清理旧快照
```

### 4. 异地备份

```bash
# 启用远程备份
sudo snapsync
# 3) 配置管理 -> 1) 修改远程服务器配置

# 或复制到其他位置
rsync -avz /backups/system_snapshots/ backup-server:/remote/backups/
```

### 5. 管理多台服务器

```bash
# 方案1：为每个VPS创建独立Bot（推荐）
# 在BotFather中创建多个Bot
@VPS1_Bot, @VPS2_Bot, @VPS3_Bot

# 方案2：使用群组隔离
# 创建不同的Telegram群组，每个VPS使用不同群组的Chat ID

# 设置唯一主机名便于识别
sudo hostnamectl set-hostname vps-tokyo
sudo hostnamectl set-hostname vps-singapore
```

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
- 📧 邮件支持: admin@kele.my
- 📖 完整文档: [Wiki](https://github.com/kelenetwork/snapsync/wiki)

---

## 🌟 致谢

感谢所有贡献者和用户的支持！

**特别感谢:**
- 所有提交 Issue 和 PR 的贡献者
- 在生产环境中使用并反馈问题的用户
- 开源社区的各种工具和库

---

<div align="center">

**SnapSync v3.0** - 让系统快照变得简单、安全、可靠

Made with ❤️ by [Kele Network](https://github.com/kelenetwork)

[![Star](https://img.shields.io/github/stars/kelenetwork/snapsync?style=social)](https://github.com/kelenetwork/snapsync)
[![Fork](https://img.shields.io/github/forks/kelenetwork/snapsync?style=social)](https://github.com/kelenetwork/snapsync/fork)

[⬆ 回到顶部](#snapsync-v30-)

</div>
