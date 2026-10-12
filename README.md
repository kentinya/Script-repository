# Script Repository

Linux / VPS 实用脚本合集。各工具的使用方法与注意事项请查看对应目录下的 README。

| 工具 | 主要用途 | 使用说明 |
| --- | --- | --- |
| **[Xray Multi](xray/)** | Xray 安装、REALITY / Shadowsocks 节点、GOST TCP/UDP 转发、Xray 节点累计流量配额 | [Xray 说明](xray/README.md) |
| **[addswap](addswap/)** | 交互式创建 Swap 文件并写入开机挂载配置 | [Swap 说明](addswap/README.md) |
| **[ip2location](ip2location/)** | 查询本机公网 IPv4 / IPv6 的地理位置、ASN 和代理标记 | [IP 查询说明](ip2location/README.md) |

## 快速使用

**Xray Multi（需要 root）：**

```bash
curl -fL -o xray-manager.sh https://raw.githubusercontent.com/kentinya/Script-repository/main/xray/xray-manager.sh
sudo bash xray-manager.sh
```

**Swap 文件创建（需要 root；运行前请阅读覆盖文件与 /etc/fstab 的注意事项）：**

```bash
curl -fL -o addswap.sh https://raw.githubusercontent.com/kentinya/Script-repository/main/addswap/addswap.sh
sudo bash addswap.sh
```

**IP2Location 查询（需要 curl、jq 及 IPv4/IPv6 连通性）：**

```bash
curl -fL -o checkip.sh https://raw.githubusercontent.com/kentinya/Script-repository/main/ip2location/checkip.sh
bash checkip.sh
```

> 使用脚本前请阅读各目录的说明。尤其是 Swap 脚本会覆盖指定目标文件并追加 `/etc/fstab`，请勿未经检查直接重复运行。
