# IP2Location 公网 IP 地理信息查询脚本

> 对应脚本：[checkip.sh](./checkip.sh) · [返回仓库首页](../README.md)

## 功能

查询**运行脚本的服务器**当前出口公网 IPv4、IPv6，并调用 [IP2Location.io](https://www.ip2location.io/) 接口读取对应地址的地理与网络信息。

脚本实际展示如下字段：

| 字段 | 含义 |
| --- | --- |
| IP 地址 | IPv4 和 IPv6 出口地址 |
| 国家、地区、城市 | IP 地理位置数据库返回的结果 |
| ASN、AS | 自治系统号及自治系统名称/描述（取决于 API 响应） |
| Proxy | API 返回的 `is_proxy` 值 |

此工具**只用于查询**，不会修改本机 IP、路由、DNS 或网络配置。IP 地理定位信息仅供参考，不保证与服务器物理位置完全一致。

## 环境要求

- Linux / Bash 环境。
- 安装 `curl` 和 `jq`。
- 服务器能分别通过 **IPv4 和 IPv6** 访问 `ifconfig.me`，并能通过 HTTPS 访问 `api.ip2location.io`。
- 脚本不需要 root 权限。

在 Debian / Ubuntu 上可使用：

```bash
sudo apt-get update
sudo apt-get install -y curl jq
```

## 下载与运行

```bash
curl -fL -o checkip.sh https://raw.githubusercontent.com/kentinya/Script-repository/main/ip2location/checkip.sh
bash checkip.sh
```

也可以先在服务器上检查两个协议栈是否能获取出口地址：

```bash
curl -4 https://ifconfig.me
curl -6 https://ifconfig.me
```

成功时会分别输出 IPv4 和 IPv6 的地理位置、ASN/AS 及 Proxy 字段。脚本没有交互参数，也不支持在命令行指定要查询的任意 IP。

## 查询流程与局限

1. 分别执行 `curl -4 ifconfig.me` 和 `curl -6 ifconfig.me` 获取本机出口地址。
2. **任意一个地址为空，都会退出**。因此仅有 IPv4 的服务器，或仅有 IPv6 的服务器，可能无法正常运行此版本脚本。
3. 通过 IP2Location.io 查询两个地址，并使用 `jq` 读取 `country_name`、`region_name`、`city_name`、`asn`、`as`、`is_proxy` 字段。
4. **脚本内直接写有 API Key**。这意味着使用情况可能受该密钥的状态、访问额度及服务商策略影响。不要把个人密钥、完整 API 响应或敏感网络信息公开发到 Issue；如需使用自己的 Key，应在本地编辑脚本并妥善保管。
5. 请求未设置严格的 HTTP 状态检查及字段校验；即使响应表示 API 报错，`jq` 仍可能输出 `null`。`null` 不代表“此 IP 不存在”。

**隐私提示：** 执行脚本会让 `ifconfig.me` 获得出口 IP，并将所查 IP 提供给 IP2Location.io。请确认这符合你的使用场景。

## 常见问题

**提示无法获取 IPv4 / IPv6**：运行 `curl -4 https://ifconfig.me` 与 `curl -6 https://ifconfig.me` 单独检查；确认对应网络协议栈、DNS 和出站连接正常。此版本不支持忽略缺失的协议栈后继续查询另一个地址。

**提示 `jq: command not found`**：安装 `jq` 后重新运行。

**结果为 `null` 或错误信息**：可能是接口配额不足、密钥失效、字段未提供或网络请求失败。请检查 IP2Location.io 的 API 响应与服务状态，但不要公开泄露个人密钥。

**IP 地区与预期不同**：数据库、代理/隧道、Anycast 与运营商路由等均可能导致出口 IP 的定位与实际机器所在地区不一致。
