# SnapSync v2.5 增强版系统恢复工具

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Version](https://img.shields.io/badge/version-2.5-green.svg)
![Shell](https://img.shields.io/badge/shell-bash-yellow.svg)

一个功能强大、安全可靠的 Linux 系统快照恢复工具，支持多种恢复模式和高级特性。

## 📋 目录
- [特性概述](#-特性概述)
- [系统要求](#-系统要求)
- [安装指南](#-安装指南)
- [配置说明](#-配置说明)
- [使用方法](#-使用方法)
- [恢复模式](#-恢复模式)
- [高级特性](#-高级特性)
- [故障排除](#-故障排除)
- [最佳实践](#-最佳实践)
- [更新日志](#-更新日志)
- [路线图](#-路线图)
- [详细使用示例](#-详细使用示例)
- [高级配置](#-高级配置)
- [故障恢复手册](#-故障恢复手册)
- [测试与API](#-测试与api)
- [安全审计](#-安全审计)
- [致谢](#-致谢)

---

## 🚀 特性概述

### 核心功能
- **多种恢复方式**：本地快照、远程下载、手动指定文件
- **智能恢复模式**：标准、完全、选择性恢复
- **多格式支持**：.tar.gz、.tar.bz2、.tar.xz、.tar
- **完整性验证**：SHA256 校验和自动验证
- **配置保留**：智能保留网络、SSH 等关键配置

### 增强特性
- **ACL 权限恢复**
- **扩展属性恢复**
- **进度显示**
- **Telegram 通知**
- **错误回滚机制**

### 安全特性
- **多重确认**
- **运行时检查**
- **权限验证**
- **配置备份**

---

## 🔧 系统要求

### 必需组件
- bash (>= 4.0)
- tar / gzip / bzip2 / xz-utils
- curl / ssh / systemctl
- root 权限

### 可选增强组件
- acl、attr、bc、pv

### 支持的发行版
- ✅ Ubuntu 18.04+
- ✅ Debian 9+
- ✅ CentOS 7+
- ✅ RHEL 7+
- ✅ Rocky Linux 8+
- ✅ Arch Linux

---

## 📦 安装指南

### 方法一：直接下载
```bash
wget https://raw.githubusercontent.com/your-repo/snapsync/main/remote_restore.sh
chmod +x remote_restore.sh
sudo ./remote_restore.sh
```

### 方法二：Git 克隆
```bash
git clone https://github.com/kelenetwork/SnapSync.git
cd SnapSync
chmod +x SnapSync remote_restore
sudo ./remote_restore.sh
```

### 安装依赖（Ubuntu/Debian）
```bash
sudo apt update
sudo apt install -y tar gzip bzip2 xz-utils curl openssh-client acl attr bc
```

### 安装依赖（CentOS/RHEL）
```bash
sudo yum install -y tar gzip bzip2 xz curl openssh-clients acl attr bc
```

---

## ⚙️ 配置说明

首次运行会在 `/etc/snapsync/config.conf` 生成配置：
```bash
TARGET_IP="192.168.1.100"
TARGET_USER="root"
SSH_PORT="22"
REMOTE_BASE_PATH="/opt/system_backups"
BACKUP_DIR="/opt/system_backups"
TELEGRAM_BOT_TOKEN="your_bot_token"
TELEGRAM_CHAT_ID="your_chat_id"
VERIFY_CHECKSUMS="true"
PRESERVE_ACL="true"
PRESERVE_XATTR="true"
DEBUG_MODE="false"
```

---

## 📖 使用方法

### 基本用法
```bash
sudo ./remote_restore.sh       # 交互式恢复
./remote_restore.sh --help     # 查看帮助
./remote_restore.sh --check    # 检查系统状态
./remote_restore.sh --config   # 查看配置
```

### 恢复流程
1. 选择恢复方式：本地 / 远程 / 手动指定
2. 选择恢复模式：标准 / 完全 / 选择性
3. 确认并执行，实时显示进度

---

## 🔄 恢复模式

- **标准模式**（推荐）：保留网络、SSH、主机名等配置  
- **完全模式**（谨慎）：覆盖所有文件，适合灾难恢复  
- **选择性模式**：仅恢复指定目录（如 `/home`、`/etc` 等）

---

## 🌟 高级特性

- ACL & 扩展属性恢复  
- 校验和完整性验证  
- 实时进度监控  
- Telegram 通知推送

---

## 🔍 故障排除

- 权限不足 → 使用 `sudo`  
- 网络错误 → 测试 SSH 连接  
- 磁盘空间不足 → 清理临时文件或扩容  
- 快照损坏 → 校验或重新下载

日志位置：  
- 主日志 `/var/log/system_snapshot/restore.log`  
- 调试日志 `/var/log/system_snapshot/restore_debug.log`  

---

## 💡 最佳实践

- 恢复前确认快照完整性  
- 确保磁盘空间 & 网络稳定  
- 在测试环境验证流程  
- 配置 Telegram 通知监控恢复状态  

---

## 📊 路线图

### v2.6
- [ ] GUI 界面
- [ ] 增量恢复
- [ ] 多目标并行恢复
- [ ] 云存储集成
- [ ] 恢复策略模板
- [ ] 性能基准工具

### v3.0
- [ ] 容器化部署
- [ ] REST API
- [ ] Web 管理界面
- [ ] 集群恢复
- [ ] AI 辅助诊断

---

## 📚 详细使用示例

### 示例1：标准生产恢复
```bash
sudo ./remote_restore.sh
选择：2（远程下载）
选择快照：system_snapshot_xxx.tar.gz
选择模式：1（标准恢复）
输入：yes
```

### 示例2：选择性恢复
```bash
sudo ./remote_restore.sh
选择：1（本地快照恢复）
选择模式：3（选择性恢复）
勾选 /var/www /etc/mysql /var/lib/mysql
```

### 示例3：灾难恢复
```bash
sudo ./remote_restore.sh
选择：2（远程下载最新快照）
选择模式：2（完全恢复）
输入：yes → CONFIRM → yes
```

---

## 🔧 高级配置

- **SSH 密钥认证**：支持免密登录  
- **自定义保留路径**：通过 `PRESERVE_PATHS` 设置  
- **排除规则**：通过 `EXCLUDE_PATTERNS` 配置  
- **性能调优**：支持并行压缩、网络优化参数

---

## 📋 故障恢复手册

- 网络中断 → 断点续传 `rsync --partial`  
- 磁盘不足 → 清理临时文件 & 扩容  
- 恢复失败 → 使用回滚点 `/var/backups/system_config_backup_*`  

---

## 🧪 测试与 API

- **单元测试**：`./tests/run_tests.sh`  
- **集成测试**：`./tests/e2e/test_complete_restore.sh`  
- **API**：
  - `execute_standard_restore`  
  - `execute_selective_restore`  
  - `verify_snapshot_integrity`  

---

## 🔒 安全审计

- 权限检查：`./security/audit_permissions.sh`  
- 配置安全：`./security/check_config_security.sh`  
- 漏洞扫描：`./security/vulnerability_scan.sh`  

---

## 🎉 致谢

感谢所有为 **SnapSync** 做出贡献的开发者和用户！  
特别感谢核心团队、测试用户、开源社区反馈，以及 Linux 发行版维护者。  

---

- 🐛 问题反馈：[GitHub Issues](https://github.com/kelenetwork/snapsync/issues)  
- 💬 讨论交流：[GitHub Discussions](https://github.com/kelenetwork/snapsync/discussions)  
- 📧 邮件支持：snapsync-support@kele.my  

<div align="center">
  <p><strong>SnapSync - 让系统恢复变得简单可靠</strong></p>
  <p>
    <a href="https://github.com/kelenetwork/snapsync">GitHub 仓库</a> •
    <a href="https://github.com/kelenetwork/snapsync/wiki">文档</a> •
    <a href="https://github.com/kelenetwork/snapsync/GitHub">下载</a>
  </p>
  <p><sub>© 2024 SnapSync Development Team. MIT License.</sub></p>
</div>
