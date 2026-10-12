# Swap 文件创建脚本使用说明

> 对应脚本：[addswap.sh](./addswap.sh) · [返回仓库首页](../README.md)

## 功能

在 Linux 服务器上交互式创建并启用一个 **Swap（交换空间）文件**，将其路径写入 `/etc/fstab`，使系统重启后尝试继续启用该 Swap 文件。

脚本的实际行为：

1. 检查是否以 root 身份执行。
2. 询问 Swap 大小（**MB**），直接回车默认 **1024 MB**。
3. 询问 Swap 文件路径，直接回车默认 **`/swapfile`**。
4. 使用 `dd` 将零数据写入目标文件，随后执行 `chmod 600`、`mkswap`、`swapon`。
5. 执行 `swapon -s` 显示交换空间，并向 `/etc/fstab` **追加**一条开机挂载记录。

此脚本是**新建 Swap 文件**的工具，不是内存扩容工具，也不包含更新、删除、去重或自动回滚功能。

## 运行条件与准备

- Linux 主机，具有 root 权限；需有 `dd`、`chmod`、`mkswap`、`swapon` 等命令。
- 磁盘剩余空间须大于计划创建的文件大小。建议先运行 `df -h /` 和 `free -h`。
- Swap 文件应放在支持 Swap 文件的本地文件系统上；部分文件系统（例如特定配置的 Btrfs/CoW 文件）还需要额外处理。
- **运行前检查目标路径是否已存在，先备份 `/etc/fstab`。** 尤其不要在已有 Swap 文件上再次运行而不检查。

备份挂载配置的示例：

```bash
sudo cp -a /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d-%H%M%S)"
swapon --show
df -h /
```

## 下载与使用

```bash
curl -fL -o addswap.sh https://raw.githubusercontent.com/kentinya/Script-repository/main/addswap/addswap.sh
sudo bash addswap.sh
```

交互示例（方括号中为默认值）：

```text
请输入交换文件大小 (MB) [默认: 1024MB]: 2048
请输入交换文件路径 [默认: /swapfile]: /swapfile
```

上例请求创建一个约 **2048 MiB** 的 `/swapfile`。如果直接按回车，则会选择默认的 1024 MB 和 `/swapfile`。脚本不校验输入是否为正整数，也不检查路径是否安全，因此必须自行确认。

## 检查是否成功

```bash
swapon --show
free -h
grep -n '/swapfile' /etc/fstab
```

请确认 Swap 已激活，并且 `/etc/fstab` 中只有**预期的挂载条目**。Swap 容量不等于物理内存，频繁交换到磁盘会影响性能。

## 停用与删除（手动操作）

**脚本没有卸载功能。** 如需手动移除某个 Swap 文件，先确认当前空闲内存足以容纳被换出的页面，以免 `swapoff` 失败或触发内存不足：

```bash
sudo swapoff /swapfile
sudoedit /etc/fstab
```

在编辑器中只删除与你准备移除的 Swap 文件**对应的行**，保存后再次核对 `swapon --show`；确认不再使用该文件时，才执行：

```bash
sudo rm -- /swapfile
```

如果创建时改用了其他路径，应将上方的 `/swapfile` 替换成实际路径。

## 重要限制与故障排查

- **不要直接重复运行**：`dd` 会覆盖目标路径的已有内容，脚本还会重复向 `/etc/fstab` 追加行，可能破坏已有 Swap 配置。
- 脚本未启用 `set -e`，也未检查全部子命令返回值；即使 `dd`、`mkswap` 或 `swapon` 失败，仍可能继续执行并写入 `/etc/fstab`。请务必核查结果。
- `swapon failed: Invalid argument` 可能表示文件系统不支持当前 Swap 文件形式；请检查文件系统类型与内核要求。
- `No space left on device` 说明空间不足；先解决磁盘问题并检查残留文件，**不要假设脚本已回滚**。
- 修改 `/etc/fstab` 或删除 Swap 文件前请确认路径，避免影响其他挂载和正在使用的交换空间。
