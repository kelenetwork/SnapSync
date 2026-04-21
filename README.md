# SnapSync

SnapSync 是一个面向 Linux 服务器的系统快照、恢复与远程备份工具。

它提供统一的 Bash 控制台、可选的 Telegram Bot、远程 rsync 归档、定时备份、完整性校验，以及一套已经落地的脚本安全加固策略，适合单机 VPS、家庭服务器和轻量运维场景。

## 适用场景

- 需要为 Linux 系统做整机级快照备份
- 需要在本地和远程之间保留多份快照
- 需要在故障时快速恢复系统文件
- 需要通过 Telegram 接收通知或远程触发常用操作
- 希望用纯 Bash 方案部署，尽量少依赖外部运行时

## 当前版本重点

当前仓库中的脚本已经包含一轮安全与稳定性优化，README 也按这些变更重新整理：

- 关键脚本统一启用了 `set -euo pipefail`
- 补充了 `IFS=$'\n\t'` 和 `umask 077`
- 关键 HTTP 调用统一走带 `--fail` 的 `curl` 封装
- 配置写入改为安全替换，避免直接 `sed` 插值带来的注入风险
- Telegram Bot 的状态文件改为随机临时目录，避免固定 `/tmp/...` 路径
- 备份与恢复流程都显式记录关键管道退出码，降低“错误被吞掉”的风险
- 远程恢复和远程上传前增加 SSH 私钥权限校验
- Telegram 诊断输出不再直接暴露完整 token

## 功能概览

- 本地系统快照创建
- 快照 SHA256 校验文件生成与恢复前校验
- 远程服务器归档上传
- 远程快照下载后恢复
- 智能恢复与完全恢复两种模式
- Telegram 通知
- Telegram Bot 按钮式交互
- 快照保留策略管理
- 系统日志查看
- 内置升级与完整卸载入口

## 仓库文件

当前仓库核心文件如下：

```text
SnapSync/
├── install.sh
├── snapsync.sh
├── backup.sh
├── restore.sh
├── telegram_bot.sh
├── telegram-test.sh
└── README.md
```

安装后默认布局如下：

```text
/opt/snapsync/
├── snapsync.sh
├── modules/
│   ├── backup.sh
│   └── restore.sh
└── bot/
    └── telegram_bot.sh

/etc/snapsync/config.conf
/var/log/snapsync/
```

## 系统要求

- Linux 发行版，优先面向 Debian / Ubuntu / CentOS / RHEL 系
- `root` 权限或可用 `sudo`
- 建议至少预留接近系统数据量的空闲磁盘空间
- 需要远程备份时，远端机器需可通过 SSH 访问
- 需要 Telegram 功能时，本机需能访问 `https://api.telegram.org`

## 安装

```bash
git clone https://github.com/kelenetwork/SnapSync.git
cd SnapSync
sudo bash install.sh
```

安装脚本会自动：

- 检测系统类型
- 安装基础依赖
- 创建程序目录、配置目录和日志目录
- 生成命令快捷方式
- 创建 `systemd` 服务与定时器
- 通过交互式向导写入 `/etc/snapsync/config.conf`

## 安装后的命令

安装完成后可直接使用这些命令：

```bash
sudo snapsync
sudo snapsync-backup
sudo snapsync-restore
sudo telegram-test
```

它们分别对应：

- `snapsync`: 主控制台
- `snapsync-backup`: 直接执行备份
- `snapsync-restore`: 直接进入恢复流程
- `telegram-test`: Telegram 诊断工具

## 主控制台

主控制台入口：

```bash
sudo snapsync
```

当前菜单与脚本一致：

```text
1)  创建系统快照
2)  恢复系统快照
3)  配置管理
4)  查看快照列表
5)  Telegram Bot 管理
6)  清理旧快照
7)  查看日志
8)  系统信息
9)  升级到最新版本
10) 完全卸载
0)  退出
```

## 备份流程

### 直接执行备份

```bash
sudo snapsync-backup
```

### 备份特性

- 优先使用 `pigz` 进行多线程压缩，缺失时回退到 `gzip`
- 默认生成 `system_snapshot_YYYYMMDDHHMMSS.tar.gz`
- 备份结束后可生成 `.sha256` 校验文件
- 可根据配置保留最近若干本地快照
- 远程备份启用时，可上传到远程服务器

### 备份前检查

备份脚本会做一些基础保护：

- 检查配置文件语法
- 检查备份目录所在分区可用空间
- 根据系统大小粗略估算所需空间
- 检查是否已有备份任务在运行
- 在开启远程上传时检查 SSH 私钥是否存在且权限为 `600` 或 `400`

### 远程上传

远程上传依赖 `rsync + SSH`，默认使用：

- 远端目录：`${REMOTE_PATH}/system_snapshots`
- 认证方式：SSH 公钥
- 传输方式：`rsync --partial --progress`

如果启用了远程保留策略，上传完成后会在远端清理超出保留天数的旧快照。

## 恢复流程

恢复入口：

```bash
sudo snapsync-restore
```

或者通过主控制台进入。

### 恢复来源

- 本地恢复：从本地快照目录选择
- 远程恢复：先从远程服务器下载，再进入恢复

### 恢复模式

- 智能恢复：恢复系统文件，但优先保留网络、SSH 等关键配置，适合远程服务器
- 完全恢复：按快照内容完整恢复，风险更高

### 恢复保护

恢复脚本当前包含这些保护措施：

- 恢复前校验快照文件是否存在、是否为空
- 若存在 `.sha256`，会先做完整性校验
- 智能恢复模式下会先临时备份 `/etc/network`、`/etc/netplan`、`/etc/ssh`、`/root/.ssh` 等关键配置
- 解压与 `tar` 恢复过程会显式捕获管道退出码
- 远程下载同样要求 SSH 私钥权限安全

## Telegram 通知

启用后，SnapSync 会在这些关键节点发送通知：

- 开始备份
- 备份完成
- 备份失败
- 开始上传
- 上传完成
- 上传失败
- 开始下载远程快照
- 下载完成
- 下载失败
- 开始恢复
- 恢复完成
- 恢复失败

配置项位于 `/etc/snapsync/config.conf`：

```bash
TELEGRAM_ENABLED="true"
TELEGRAM_BOT_TOKEN="123456:token"
TELEGRAM_CHAT_ID="123456789"
```

## Telegram Bot

### Bot 作用

`telegram_bot.sh` 是一个常驻服务，提供按钮式交互。它适合做轻量操作和状态查看，不适合完全替代交互式恢复。

### Bot 支持的主要动作

- 查看系统状态
- 查看快照列表
- 触发备份
- 查看恢复指引
- 删除快照
- 查看日志
- 修改部分配置
- 测试远程连接和 Telegram API

### Bot 服务管理

```bash
sudo systemctl status snapsync-bot
sudo systemctl restart snapsync-bot
sudo systemctl enable snapsync-bot
sudo systemctl disable snapsync-bot
```

### Telegram 诊断

当通知或 Bot 有问题时，优先使用：

```bash
sudo telegram-test
```

诊断脚本会检查：

- 配置文件是否存在
- `TELEGRAM_ENABLED` 是否启用
- Bot Token 和 Chat ID 是否配置
- Telegram API 是否可达
- `getMe` 是否返回成功
- 能否向当前 Chat 发送测试消息

当前版本里，诊断输出已经对 token 做了脱敏显示。

## 配置文件

配置文件默认位置：

```bash
/etc/snapsync/config.conf
```

典型配置示例：

```bash
#!/bin/bash

TELEGRAM_ENABLED="false"
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

REMOTE_ENABLED="false"
REMOTE_HOST=""
REMOTE_USER="root"
REMOTE_PORT="22"
REMOTE_PATH="/backups"
REMOTE_KEEP_DAYS="30"

BACKUP_DIR="/backups"
COMPRESSION_LEVEL="6"
PARALLEL_THREADS="auto"
LOCAL_KEEP_COUNT="5"

AUTO_BACKUP_ENABLED="false"
BACKUP_INTERVAL_DAYS="7"
BACKUP_TIME="03:00"

ENABLE_ACL="true"
ENABLE_XATTR="true"
ENABLE_VERIFICATION="true"
DISK_THRESHOLD="90"
HOSTNAME="server-01"
```

## 定时备份

安装脚本会创建：

- `snapsync-backup.service`
- `snapsync-backup.timer`

查看状态：

```bash
sudo systemctl status snapsync-backup.timer
sudo systemctl list-timers snapsync-backup.timer
```

当前定时器由安装脚本根据 `BACKUP_INTERVAL_DAYS` 写入：

- `1` -> `daily`
- `7` -> `weekly`
- `30` -> `monthly`

如果你改了配置文件中的周期，通常还需要重新安装或重新生成定时器配置，当前版本并不会自动把任意时间表达式同步回 `systemd`。

## 日志

默认日志目录：

```text
/var/log/snapsync/
├── backup.log
├── restore.log
├── bot.log
└── main.log
```

常用查看方式：

```bash
sudo tail -f /var/log/snapsync/backup.log
sudo tail -f /var/log/snapsync/restore.log
sudo tail -f /var/log/snapsync/bot.log
sudo tail -f /var/log/snapsync/main.log
```

## 安全说明

这轮重写 README 的重点之一，就是把当前脚本里的安全设计说清楚：

### 1. 严格模式

核心脚本启用了：

```bash
set -euo pipefail
IFS=$'\n\t'
```

这能减少未定义变量、命令失败被忽略、空白分割异常等常见 Bash 问题。

### 2. 临时文件权限

脚本统一启用了：

```bash
umask 077
```

并通过 `mktemp` 创建临时文件或目录，避免固定路径和宽权限带来的泄漏风险。

### 3. HTTP 失败即失败

与 Telegram 和网络检查相关的调用不再直接裸用 `curl`，而是统一走带这些选项的封装：

```bash
curl -sS --fail --connect-timeout 10 --max-time 30
```

这样 HTTP 404/500 不会再被当成“脚本成功执行”。

### 4. 配置写入安全

配置更新不再通过直接插值的 `sed -i "s|...|$user_input|"` 实现，而是用安全替换逻辑写回配置文件，降低了因为特殊字符造成的配置破坏或注入风险。

### 5. SSH 私钥权限校验

在远程上传和远程恢复前，脚本会检查：

- 私钥是否存在
- 权限是否为 `600` 或 `400`

不满足条件时会直接拒绝继续操作。

## 常用操作

### 1. 首次安装后创建快照

```bash
sudo snapsync-backup
```

### 2. 查看当前快照

```bash
sudo snapsync
```

然后选择 `4) 查看快照列表`。

### 3. 配置远程备份

```bash
sudo snapsync
```

然后进入：

```text
3) 配置管理
1) 修改远程服务器配置
```

### 4. 测试 Telegram

```bash
sudo telegram-test
```

### 5. 从远程快照恢复

```bash
sudo snapsync-restore
```

然后选择：

```text
2) 远程恢复
```

## 故障排查

### Telegram 不工作

按顺序检查：

```bash
sudo telegram-test
sudo tail -100 /var/log/snapsync/backup.log
sudo tail -100 /var/log/snapsync/bot.log
```

常见原因：

- `TELEGRAM_ENABLED` 不是 `true`
- Bot Token 或 Chat ID 错误
- 服务器无法访问 Telegram API
- Bot 服务未启动

### SSH 远程失败

先确认：

```bash
ls -l /root/.ssh/id_ed25519
ssh -i /root/.ssh/id_ed25519 -p 22 user@host
```

再看日志：

```bash
sudo tail -100 /var/log/snapsync/backup.log
sudo tail -100 /var/log/snapsync/restore.log
```

### 远程服务器缺少 rsync

如果上传或下载时提示 `rsync` 相关错误，需要在远程服务器补装：

Debian / Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y rsync
```

RHEL / CentOS:

```bash
sudo yum install -y rsync
```

### 恢复后建议动作

恢复完成后，尤其是完全恢复模式，建议尽快：

- 检查网络是否正常
- 检查 SSH 能否登录
- 检查关键服务是否能启动
- 视情况执行 `sudo reboot`

## 当前已知限制

为避免 README 继续“写得太满”，这里把当前仓库中仍然值得注意的点直接列出来：

- 当前还是多脚本分散结构，尚未抽成公共 `lib/`
- `systemd timer` 的时间表达式还比较基础，不能完整映射 `HH:MM`
- 安装脚本里仍保留了对 `config.sh` 的复制逻辑，但当前仓库并没有这个文件
- 尚未引入 CI、`shellcheck` 工作流和自动化测试

## 建议使用方式

- 生产环境优先使用 `智能恢复`
- 开启远程备份时优先使用独立的 SSH 密钥
- 至少保留一份异地快照
- 升级脚本前先保留最近一次本地快照
- 定期在测试环境演练恢复

## 开发与贡献

如果你要继续改这个项目，建议优先做这几件事：

- 抽取公共库，减少重复函数
- 加入 `shellcheck`
- 增加简单的回归测试
- 补充配置版本迁移能力
- 进一步整理目录结构

常规贡献流程：

```bash
git checkout -b feature/your-change
git commit -m "feat: describe your change"
git push origin feature/your-change
```

## 许可证

仓库当前 README 历史上声明为 MIT，但实际仓库里暂未看到明确的 `LICENSE` 文件；如果准备长期维护，建议尽快补齐。

## 支持

- Issues: <https://github.com/kelenetwork/SnapSync/issues>
- Repository: <https://github.com/kelenetwork/SnapSync>

---

如果你正在直接使用这个仓库中的当前代码，建议先跑一次安装、一次本地备份、一次 Telegram 诊断，再决定是否在生产环境启用远程上传与恢复流程。
