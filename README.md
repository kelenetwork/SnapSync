# ✨ SnapSync v2.4 Ultimate

[![Version](https://img.shields.io/badge/version-v2.4--ultimate-blue)]()
[![Platform](https://img.shields.io/badge/platform-Linux-green)]()
[![License](https://img.shields.io/badge/license-MIT-orange)]()

🚀 一套面向 Linux 的 **系统快照备份与恢复工具**，支持本地/远端存储、自动清理、systemd 定时任务与 Telegram 通知。

---

## 📂 目录结构

```
.
├─ SnapSync                 # 安装与初始化向导（执行一次即可）
├─ remote_restore           # 恢复脚本
└─ README.md
# 安装后自动生成：
/etc/system_snapshot/config.conf
/usr/local/sbin/system_snapshot.sh
/var/log/system_snapshot/{install,snapshot,debug,restore}.log
/etc/systemd/system/system-snapshot.{service,timer}
```

---

## ⚙️ 安装与初始化

```bash
git clone https://github.com/kelenetwork/SnapSync.git
cd SnapSync
chmod +x SnapSync remote_restore
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

MIT（可根据需要更改）

---

## 🙏 致谢

感谢使用本项目。如果你在使用中遇到问题或有改进建议，欢迎提交 Issue / PR。
