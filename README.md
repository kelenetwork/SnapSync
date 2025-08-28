# SnapSync v2.4 Ultimate

一套面向 Linux 的**系统快照备份与恢复**解决方案：

- `SnapSync`：**交互式安装与初始化向导**  
  - 自动检查/安装依赖  
  - 采集配置（Telegram、远端、保留策略、定时周期等）  
  - 生成配置与主备份脚本  
  - 配置 SSH 密钥（兼容 Dropbear）  
  - 测试 Telegram 通知  
  - 配置 systemd **定时任务**（首次 1 小时后，之后每 N 天执行）  
  - 可选择**立即执行一次快照**  
- `/usr/local/sbin/system_snapshot.sh`：**主备份脚本**（由 `SnapSync` 自动生成）  
  - 创建系统快照（`tar.gz`，优先 `pigz` 压缩，回退 `gzip`）  
  - 本地保留/清理  
  - 远端上传（优先 `rsync`，失败回退 `scp`）  
  - 远端目录自动选择（优先 `/mnt/wd/Remote_backup`）  
  - 上传前空间检查、上传后统计  
  - Telegram 分阶段通知  
- `remote_restore`：**恢复脚本**  
  - 支持本地 / 远端两种恢复方式  
  - **标准恢复**（保留网络/SSH 等关键配置）与**完全恢复**模式  
  - 恢复后可选重启  

---

## 目录结构

```
.
├─ SnapSync                 # 安装与初始化向导（执行一次即可）
├─ remote_restore           # 恢复脚本
└─ README.md
# 安装后自动生成：
/etc/system_snapshot/config.conf
/usr/local/sbin/system_snapshot.sh
/var/log/system_snapshot/{install,snapshot,debug,restore}.log
/etc/systemd/system/system-snapshot.service
/etc/systemd/system/system-snapshot.timer
```

---

## 安装与初始化

```bash
git clone https://github.com/kelenetwork/SnapSync.git
cd SnapSync
chmod +x SnapSync remote_restore
./SnapSync
```

安装过程会引导你配置：  

- **Telegram**：`BOT_TOKEN`, `CHAT_ID`  
- **远端服务器**：`TARGET_IP`, `TARGET_USER`(默认 root), `SSH_PORT`  
- **远端目录**：`TARGET_BASE_DIR`（默认 `/mnt/wd/Remote_backup`），`REMOTE_DIR_NAME`（默认本机 hostname）  
- **本地备份**：`BACKUP_DIR`（默认 `/backups`）  
- **保留策略**：`LOCAL_SNAPSHOT_KEEP`，`REMOTE_SNAPSHOT_DAYS`  
- **定时周期**：`BACKUP_INTERVAL_DAYS`（默认 5 天），是否立即执行一次  

---

## 手动运行

```bash
/usr/local/sbin/system_snapshot.sh
```

无需参数，行为由 `/etc/system_snapshot/config.conf` 控制。

---

## 定时任务管理

```bash
systemctl status system-snapshot.timer
systemctl start system-snapshot.service
systemctl disable --now system-snapshot.timer
```

---

## 恢复快照

```bash
cd ~/SnapSync
chmod +x remote_restore
./remote_restore
```

交互式流程：  

1. 选择恢复方式  
   - **本地恢复**：从 `$BACKUP_DIR` 中选择快照  
   - **远程恢复**：连接远端 `$TARGET_BASE_DIR/$REMOTE_DIR_NAME/system_snapshots` 下载快照  
2. 选择恢复模式  
   - **标准恢复**：保留网络/SSH/主机名/DNS 等关键配置  
   - **完全恢复**：恢复所有文件（仅排除虚拟文件系统与备份目录）  
3. 恢复完成后可选立即重启  

---

## 配置文件

路径：`/etc/system_snapshot/config.conf`  

包含：  
- `BOT_TOKEN`, `CHAT_ID`  
- `TARGET_IP`, `TARGET_USER`, `SSH_PORT`, `TARGET_BASE_DIR`, `REMOTE_DIR_NAME`  
- `BACKUP_DIR`  
- `LOCAL_SNAPSHOT_KEEP`, `REMOTE_SNAPSHOT_DAYS`, `BACKUP_INTERVAL_DAYS`  
- `DISK_SPACE_THRESHOLD`, `MAX_RETRY_ATTEMPTS`, `LOAD_THRESHOLD_MULTIPLIER`, `MEMORY_THRESHOLD`  
- 日志路径  

---

## 日志

- 安装日志：`/var/log/system_snapshot/install.log`  
- 快照日志：`/var/log/system_snapshot/snapshot.log`  
- 恢复日志：`/var/log/system_snapshot/restore.log`  
- 调试日志：`/var/log/system_snapshot/debug.log`  

---

## 卸载/清理

```bash
systemctl disable --now system-snapshot.timer
rm -f /etc/systemd/system/system-snapshot.{service,timer}
systemctl daemon-reload

rm -f /usr/local/sbin/system_snapshot.sh
rm -rf /etc/system_snapshot
rm -rf /var/log/system_snapshot
```

---

## 安全提示

- 恢复操作会覆盖系统文件，请谨慎执行  
- 标准恢复推荐用于生产环境，可避免恢复后失联  
- 建议在测试机先完整演练恢复流程  

---

## 许可证

根据你的意愿选择（MIT / Apache-2.0 / GPL-3.0 / All Rights Reserved）。

---

## 致谢

感谢使用本项目。如果你在使用中遇到问题或有改进建议，欢迎提交 Issue / PR。
