# Kindle KT6 原生翻页动画安全启用工具

为 **Kindle 基础款 2024（KT6）** 解锁亚马逊固件中已经存在、但默认隐藏的“翻页动画效果”开关。

本项目是对早期闭源修改器的安全重制：全部脚本均可审阅，先检查、再修改，并提供可验证的恢复路径。项目不包含来源不明的预编译二进制。

## 已验证环境

- 设备：Kindle（第 11 代）— 2024 年发布，KT6
- 序列号前缀：`G093KM`
- 固件：`5.18.6`
- 内部版本：`juno_1806`
- 越狱：Véra，带 Universal Hotfix / Scriptlet 支持

> 其他机型、序列号前缀或固件不要直接运行启用脚本。先运行只读检查；启用脚本本身也会严格拒绝未经验证的环境。

## 原理

Kindle 的 `/etc/deviceConfig.conf` 中，KT6 对应的 `[ri7]` 配置段包含：

```ini
swipeMode.available=false
```

工具将这一行改为：

```ini
swipeMode.available=true
```

随后原生阅读器的 `Aa → 更多` 页面会出现“翻页动画效果”开关。

## 安全设计

- 检查脚本完全不修改系统分区。
- 启用前要求存在与当前配置逐字节一致的 USB 外部备份。
- 只修改 `[ri7]` 内唯一的一条已知配置。
- 写入前验证解密、修改、重新加密和加密回读结果。
- 使用同文件系统临时文件并原子替换配置。
- 写入后再次解密、逐字节核验。
- 写入验证失败时自动回滚。
- 提供独立恢复脚本。
- 完成后将系统分区重新挂载为只读。

## 使用方法

### 1. 只读检查

将 [`scripts/check-compatibility.sh`](scripts/check-compatibility.sh) 复制到 Kindle 的 `documents` 文件夹，在书库中点击运行。

运行后检查 Kindle 根目录的 `KT6-animation-check.txt`。只有报告结尾为：

```text
RESULT: COMPATIBLE. Send this report back before enabling.
```

才可继续。此步骤还会在 Kindle 根目录创建：

```text
deviceConfig.conf.before-animation.encrypted.bak
```

把该备份额外复制到电脑长期保存。不要公开分享备份或完整设备序列号。

### 2. 启用动画

将 [`scripts/enable-animation.sh`](scripts/enable-animation.sh) 复制到 `documents`，在书库中运行。

先不要立即重启。连接电脑并打开 Kindle 根目录的 `KT6-animation-enable-result.txt`。只有看到以下内容才可重启：

```text
RESULT: SUCCESS - swipeMode.available=true is installed for [ri7].
```

重启后打开一本普通文字书，进入 `Aa → 更多 → 翻页动画效果` 并开启。

### 3. 恢复原配置

保持 Kindle 根目录中的加密备份不变，将 [`scripts/restore-animation.sh`](scripts/restore-animation.sh) 放入 `documents` 并运行。

检查 `KT6-animation-restore-result.txt`。看到 `RESULT: SUCCESS` 后手动重启。

## 重要警告

- 此操作会短暂挂载并修改 Kindle 系统分区，风险由使用者自行承担。
- 请保持电量在 50% 以上，操作过程中不要强制关机或拔电。
- 不要重复运行已成功的启用脚本。
- 不要手工编辑、改名或覆盖加密备份。
- 恢复出厂设置前，建议先关闭翻页动画开关并运行恢复脚本。
- 固件更新可能改变配置结构；更新后不要直接重复运行。
- 本工具不会安装或替代越狱；设备必须已经具有可用的 Véra / Universal Hotfix Scriptlet 执行环境。

## 清理

成功后可以删除检查、启用脚本及其报告。建议长期保留：

- `deviceConfig.conf.before-animation.encrypted.bak`
- `scripts/restore-animation.sh`

并在电脑上另存一份。

## 致谢

- 感谢原始思路和实机验证提供者：QQ `744846656`
- 小红书：`og`
- 感谢 Véra、Universal Hotfix、FBInk 与 Kindle Modding 社区的开发者和维护者

## 许可证

[MIT License](LICENSE)

