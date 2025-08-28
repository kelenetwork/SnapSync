# SnapSync

一个 Linux 系统自动快照与远程备份工具，支持本地归档、远端同步，并通过 Telegram 机器人实时通知。

## ✨ 功能特性
- 定时执行系统快照（systemd timer）
- 本地目录归档与压缩
- 远端服务器增量同步（基于 rsync）
- 磁盘空间阈值监控，超限提醒
- Telegram Bot 通知（备份成功/失败/告警）
- 支持自定义备份保留天数与频率

## 📦 安装与使用

1. 克隆或下载脚本：
   ```bash
   git clone https://github.com/kelenetwork/SnapSync.git
   cd SnapSync
   chmod +x system_snapshot.sh
   ```

2. 编辑脚本，填写必要配置：
   ```bash
   # Telegram 配置
   BOT_TOKEN="你的BotToken"
   CHAT_ID="你的ChatID"

   # 远程服务器配置
   TARGET_IP="远端服务器IP"
   TARGET_USER="root"
   SSH_PORT="22"
   TARGET_BASE_DIR="/root/Remote_backup"
   REMOTE_DIR_NAME=""

   # 本地目录
   BACKUP_DIR="/backups"
   ```

3. 运行脚本：
   ```bash
   ./system_snapshot.sh
   ```

4. 查看日志：
   ```bash
   journalctl -u system-snapshot.service -f
   ```

## ⚙️ 配置参数说明
- `BACKUP_INTERVAL_DAYS`：备份间隔天数（默认 5）
- `LOCAL_SNAPSHOT_KEEP`：本地保留快照数量（默认 2）
- `REMOTE_SNAPSHOT_DAYS`：远端快照保留天数（默认 15）
- `DISK_SPACE_THRESHOLD`：磁盘空间阈值（百分比，默认 85）
- `MEMORY_THRESHOLD`：内存使用率阈值（百分比，默认 80）

## 📡 Telegram 通知
脚本会在以下情况通过 Telegram 推送消息：
- 备份成功
- 备份失败
- 磁盘/内存超阈值
- 网络/远端连接失败

## 📝 License
MIT License
