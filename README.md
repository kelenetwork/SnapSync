# SnapSync v2.5 增强版系统恢复工具

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Version](https://img.shields.io/badge/version-2.5-green.svg)
![Shell](https://img.shields.io/badge/shell-bash-yellow.svg)

一个功能强大、安全可靠的Linux系统快照恢复工具，支持多种恢复模式和高级特性。

---

## 🚀 特性概述

### 核心功能
- **多种恢复方式**：本地快照、远程下载、手动指定文件
- **智能恢复模式**：标准、完全、选择性恢复
- **多格式支持**：.tar.gz、.tar.bz2、.tar.xz、.tar
- **完整性验证**：SHA256校验和自动验证
- **配置保留**：智能保留网络、SSH等关键配置

### 增强特性
- **ACL权限恢复**：完整的访问控制列表支持
- **扩展属性恢复**：保留文件的扩展属性
- **进度显示**：实时进度监控和系统状态显示
- **Telegram通知**：关键操作的即时推送通知
- **错误恢复**：完善的错误处理和回滚机制

### 安全特性
- **多重确认**：防止误操作的多层确认机制
- **运行时检查**：容器环境、文件系统类型检测
- **权限验证**：确保具备必要的系统权限
- **配置备份**：自动备份当前系统配置

## 🔧 系统要求

### 必需组件
```bash
# 基础工具
- bash (>= 4.0)
- tar
- gzip/bzip2/xz-utils
- curl
- ssh (用于远程恢复)
- systemctl

# 权限要求
- root 权限
---
## 📂 目录结构


.
├─ SnapSync                 # 安装与初始化向导（执行一次即可）
├─ remote_restore           # 恢复脚本
└─ README.md
```
# 安装后自动生成：
/etc/system_snapshot/config.conf
/usr/local/sbin/system_snapshot.sh
/var/log/system_snapshot/{install,snapshot,debug,restore}.log
/etc/systemd/system/system-snapshot.{service,timer}


---

## ⚙️ 安装与初始化

```bash
git clone https://github.com/kelenetwork/SnapSync.git
```
```bash
cd SnapSync
chmod +x SnapSync remote_restore
```
```bash
./SnapSync
```

👉 安装过程会引导你配置：
- 📱 **Telegram**：`BOT_TOKEN`, `CHAT_ID`  
- 🌐 **远端服务器**：`TARGET_IP`, `TARGET_USER`, `SSH_PORT`  
- 📁 **存储目录**：`TARGET_BASE_DIR`（默认 `/mnt/wd/Remote_backup`），`REMOTE_DIR_NAME`  
- 💾 **本地目录**：`BACKUP_DIR`（默认 `/backups`）  
- ♻️ **保留策略**：`LOCAL_SNAPSHOT_KEEP`, `REMOTE_SNAPSHOT_DAYS`  
- ⏰ **定时周期**：`BACKUP_INTERVAL_DAYS`  

---

## 💻 手动运行

```bash
/usr/local/sbin/system_snapshot.sh
```

---

## ⏲️ 定时任务管理

```bash
systemctl status system-snapshot.timer
systemctl start system-snapshot.service
systemctl disable --now system-snapshot.timer
```

---

## 🛠️ 恢复快照

```bash
cd ~/SnapSync
chmod +x remote_restore
./remote_restore
```

交互式流程：  
1️⃣ 选择恢复方式（本地 / 远端）  
2️⃣ 选择恢复模式（标准 / 完全）  
3️⃣ 恢复完成后可选 **立即重启**  

---

## 📑 配置文件

路径：`/etc/system_snapshot/config.conf`  
包含：
- `BOT_TOKEN`, `CHAT_ID`  
- `TARGET_IP`, `TARGET_USER`, `SSH_PORT`, `TARGET_BASE_DIR`, `REMOTE_DIR_NAME`  
- `BACKUP_DIR`  
- `LOCAL_SNAPSHOT_KEEP`, `REMOTE_SNAPSHOT_DAYS`, `BACKUP_INTERVAL_DAYS`  
- `DISK_SPACE_THRESHOLD`, `MAX_RETRY_ATTEMPTS`, `LOAD_THRESHOLD_MULTIPLIER`, `MEMORY_THRESHOLD`  

---

## 📜 日志

- 📝 安装日志：`/var/log/system_snapshot/install.log`  
- 📦 快照日志：`/var/log/system_snapshot/snapshot.log`  
- 🔄 恢复日志：`/var/log/system_snapshot/restore.log`  
- 🐞 调试日志：`/var/log/system_snapshot/debug.log`  

---

## 🧹 卸载/清理

```bash
systemctl disable --now system-snapshot.timer
rm -f /etc/systemd/system/system-snapshot.{service,timer}
systemctl daemon-reload

rm -f /usr/local/sbin/system_snapshot.sh
rm -rf /etc/system_snapshot
rm -rf /var/log/system_snapshot
```

---

## ⚠️ 安全提示

- 恢复操作会 **覆盖系统文件**，请谨慎执行  
- 标准恢复推荐用于生产环境，可避免恢复后失联  
- 建议在测试机完整演练恢复流程  

---

## 📄 许可证

MIT

---

## 🙏 致谢

感谢使用本项目。如果你在使用中遇到问题或有改进建议，欢迎提交 Issue / PR。
