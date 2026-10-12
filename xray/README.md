# Xray Multi 多节点管理器使用说明（v1.5）

> 适用脚本：[xray-manager.sh](./xray-manager.sh)｜仓库首页：[README](../README.md)
>
> 这是本仓库脚本的操作指南，不是 Xray-core 官方安装文档。请留意下文各节的安全提示与使用限制。

## 1. 功能概览

- 安装、更新、卸载由本脚本管理的 Xray，使用独立的 `xray-multi.service`。
- 创建、查看、删除 **VLESS + Vision + REALITY** 节点。
- 创建、查看、删除 **Shadowsocks 2022** 节点（TCP + UDP）。
- 显示节点分享链接、终端二维码，生成 PNG 二维码。
- 创建 **A 服务器 IP:端口 → B 服务器 IP/域名:端口** 的 TCP、UDP 或 TCP+UDP 转发规则；转发由独立 **GOST v3** 服务承担，不再进入 Xray inbounds。
- 给每个 Xray 代理节点单独设置 **累计上传 + 下载流量配额**，到额自动停用，支持清零恢复；GOST 转发不使用 Xray StatsService，因此当前不参与此配额。
- REALITY 支持随机 SNI 候选、TLS 检测、按 VPS 出口地理位置偏好选取和 Cloudflare 网段排除；支持回落连接限速加固。
- 彩色交互菜单；交互式文字输入支持方向键、Home/End 编辑。

**注意**：端口转发不是加密隧道；单节点流量配额也不是实时带宽限速。安全组、防火墙、服务器流量告警仍需自行配置。

## 2. 运行环境

- Linux，且 **systemd 正常运行**；需要 `root` 权限。
- 建议 Debian 12、Ubuntu 22.04 及以上、Rocky Linux 9；脚本也包含其他部分发行版包管理器适配，但未保证全部发行版。
- VPS 可以访问 GitHub（下载 Xray 与 GOST 正式版）、域名 DNS 和所选 REALITY 伪装目标。
- 脚本会尝试自动安装缺少的依赖，包括 `curl`、`unzip`、`openssl`、`python3`、`qrencode`、`iproute2`、`util-linux` 等。
- 云平台安全组和系统防火墙需要放通你实际选择的监听端口；转发还需要确保 B 服务器允许来自 A 的连接。

此工具不自动导入或接管原有 `/usr/local/etc/xray` 配置，也不会替换已有 `xray.service`。不要把它当作现有 Xray 配置的迁移工具。

## 3. 下载和启动

SSH 登录服务器后执行：

~~~bash
curl -fsSLo xray-manager.sh https://raw.githubusercontent.com/kentinya/Script-repository/main/xray/xray-manager.sh
sudo bash xray-manager.sh
~~~

第一次打开菜单，输入 `01` 安装 Xray。程序会从 Xray-core 官方 GitHub Release 获取正式版并校验 SHA256，随后创建并启动 `xray-multi.service`。

以后再次管理，切换到保存脚本的目录并执行：

~~~bash
sudo bash xray-manager.sh
~~~

查看命令说明（无需事先安装 Xray）：

~~~bash
bash xray-manager.sh help
~~~

**更新管理脚本**：重新下载上方的 `xray-manager.sh` 即可获取仓库中的最新脚本。**更新 Xray 内核**：菜单选择 `02`，或执行 `sudo bash xray-manager.sh update`。两者不是一回事。已安装的流量采样定时器会保留脚本副本，更新管理脚本后建议再次通过 `quota-set` 设置已有额度，以同步其运行副本。

## 4. 菜单速查

| 菜单 | 功能 |
| --- | --- |
| `01` / `02` | 安装 / 更新 Xray |
| `03` | 新建 VLESS + REALITY |
| `04` | 新建 Shadowsocks 2022 |
| `05` | 查看代理节点列表 |
| `06` | 查看分享链接 / 二维码 |
| `07` | 删除指定代理节点 |
| `08` / `09` | 查看服务状态 / 重启服务 |
| `10` | REALITY 未认证回落限速加固 |
| `11` / `12` / `13` | 新增 / 查看 / 删除 GOST 端口转发规则 |
| `14` | 查看节点与转发规则累计流量 |
| `15` | 设置单节点流量配额 |
| `16` | 清零流量，恢复因超额停用的节点 |
| `00` | 卸载本工具及所有托管数据（危险） |
| `17` | 检测现有 REALITY 节点 SNI / 目标可用性（只读） |
| `Q` | 退出 |

菜单选择后回车。可输入 `3` 或 `03`；普通文字输入支持 `←`、`→`、Home、End、Backspace、Delete。带 `[默认值]` 的提示可直接回车使用默认值。

## 5. 新建 VLESS + REALITY 节点

1. 选择 `03`（或 `sudo bash xray-manager.sh add-reality`）。
2. 填写节点名称（字母、数字、`_`、`-`，最长 48 字符），例如 `reality-hk`。
3. 填写监听端口，默认 `443`；要确保未被其他服务占用。
4. 填写用于客户端分享链接的服务器公网 IP 或域名；脚本会尝试获取公网 IPv4 作为默认值。
5. **REALITY 伪装目标 SNI**：默认输入 `random` 进行自动选择；也可以输入手工指定的真实域名。
6. **REALITY 目标地址**：通常直接回车，采用 `所选SNI:443`；例如 `www.example.com:443`。目标域名必须真实可用，不能只因示例而原样照抄。
7. 脚本验证配置后生成 UUID、密钥、Short ID，输出 `vless://` 分享链接和二维码。
8. 在客户端导入链接，并在安全组 / 防火墙放行服务端对应 **TCP** 端口。

### REALITY 随机 SNI 的选择逻辑

- 根据 VPS 的公网出口 IP 查询 ASN、国家/地区、大洲，并优先选择较接近的候选目标；地理定位不是精确保证。
- 候选域名需要通过 DNS、TLS 1.3、HTTP/2（h2）等检查。
- 对 DNS 解析到的 Cloudflare 已知 IP 网段及识别到的 Cloudflare ASN 13335 做排除；无法保证未来 DNS、CDN、Anycast 或流量风险完全不变。
- TLS/DNS 初筛之后，**对优先候选依次执行真实 Xray VLESS + REALITY + Vision 本机连接自检**：仅监听 `127.0.0.1`，通过 SOCKS5 连续两次往返本机测试数据。失败自动尝试下一个候选（最多 6 个），全部失败则不创建节点，原有节点不变。
- 手动 SNI 或修改 REALITY 目标地址时也会执行相同的真实连接检测，有助于排除普通 HTTPS 正常而 REALITY 握手失败的目标。
- 默认随机候选池已移除曾在部分版本/地区触发 REALITY 握手问题的 `www.microsoft.com`，详见 [Xray-core #6356](https://github.com/XTLS/Xray-core/issues/6356)。
- 临时实例不修改当前 Xray 服务，但会进行少量对外 TLS 流量；**通过本机测试仍无法保证公网线路、其他客户端版本、未来 DNS 或目标站点一直可用**。
- 可以按需要建立 `/etc/xray-multi/reality-targets.txt`：每行一个域名，也可以在前面注明两字母国家代码，`#` 为注释。例如：

~~~text
# 根据实际机房和可达性维护候选
DE www.example.de
JP www.example.jp
www.example.org
~~~

上面是**格式示例**，不是已验证可用的伪装站点。存在自定义文件时，随机候选来自该文件，而非默认内置池。需要临时强制使用参考国家代码时：

~~~bash
XRAY_GEO_COUNTRY=DE sudo -E bash xray-manager.sh add-reality
~~~

> **REALITY 目标检测说明**：先通过 TLS 1.3/h2 检测，再通过真实 Xray REALITY 握手及本机数据往返检测。如果仍失败，检查服务器 DNS、出站 443、目标证书兼容性，以及 Cloudflare IP/ASN 排除。

**防滥用建议**：不要把 Cloudflare 排除当成“不会被刷流量”的保证。限制公网暴露、监测出站流量，并在云平台配置告警或硬性流量控制。`10` 或 `harden` 只针对未认证回落连接设置限速，不限制正常节点带宽，也不能防止所有滥用。

### 检查已经创建的 REALITY 节点

如果旧节点偶尔连接失败，可以使用菜单 `17`，也可以运行：

~~~bash
sudo bash xray-manager.sh reality-check reality-hk
~~~

该命令读取节点当前的 SNI 与 REALITY 目标，先执行 TLS + Cloudflare 检测，再做两次本机 REALITY 数据往返测试。**不会修改或重启原有服务**。如果旧节点实测失败，可新建节点，确认连接后更新客户端分享链接，再删除旧节点。新建节点会生成新 UUID、密钥和 Short ID，旧连接不会自动迁移。

检查通过也不能保证旧客户端可用；请同时核实公网端口、安全组、防火墙、客户端版本及两端系统时间。

## 6. 新建 Shadowsocks 2022 节点

1. 选择 `04`（或运行 `sudo bash xray-manager.sh add-ss`）。
2. 输入节点名称、监听端口（默认 `8388`）及分享链接中的公网 IP / 域名。
3. 选择加密方式：`2022-blake3-aes-128-gcm`（默认）、`2022-blake3-aes-256-gcm` 或 `2022-blake3-chacha20-poly1305`。
4. 脚本自动生成密码，配置 **TCP + UDP** 入站并展示 `ss://` 分享链接及二维码。
5. 在云安全组和本机防火墙同时放行所选端口的 **TCP、UDP**。

分享链接、二维码包含访问凭据；请勿发布到公开页面。

## 7. A → B 端口转发（GOST）

适用场景：客户端连接 **A 服务器的监听端口**，A 再把 TCP 或 UDP 流量转发到 **B 服务器的目标端口**。不需要在 B 上运行本管理脚本（但 B 的服务必须可达）。

从当前版本开始，端口转发**不再使用 Xray 的 `tunnel/dokodemo-door` 入站**。脚本会从 GOST 官方 Release 安装 GOST v3 到自己的目录，并使用独立的 `xray-multi-forward.service` 运行转发；Xray 的 `xray-multi.service` 只负责代理节点和 StatsService。这样转发异常不会与 Xray 主进程共享连接和内存。

选择菜单 `11`（或 `sudo bash xray-manager.sh forward-add`），依次填写：

| 字段 | 示例 | 说明 |
| --- | --- | --- |
| 规则名称 | `to-backend` | 在本工具内唯一 |
| A 监听 IPv4 | `0.0.0.0` | 所有 IPv4 网卡；也可填 A 的实际本机 IPv4 |
| A 监听端口 | `10086` | 客户端连接的端口 |
| B 目标 IP / 域名 | `198.51.100.20` | 文档示例 IP，实际请填 B 的真实地址 |
| B 目标端口 | `443` | B 的服务端口 |
| 协议 | `1` / `2` / `3` | TCP / UDP / TCP+UDP |

保存后，规则仍保存在 `/var/lib/xray-multi/nodes.json`，但脚本会生成 `/etc/xray-multi/gost-forward.json`，由 GOST 监听 A 端口并直连 B。查看转发菜单选 `12`，删除选 `13`（需输入 `YES` 确认）。

如果数据库中已有旧版 Xray 转发规则，执行一次 `install` / `update` 会把这些规则从 Xray 配置移除并迁移到 GOST 服务，规则名称、监听地址、目标地址和协议保持不变。

**转发说明**：这不是 VPN/加密隧道，B 通常看到的是 A 的出口 IP，而非客户端原始 IP。`0.0.0.0` 会监听全部 IPv4 网卡，建议限制允许访问 A 的源地址，避免成为公开转发入口。需要放行 A 的监听端口，同时保证 B 接受来自 A 的请求。

## 8. 单节点累计流量配额

适用于 REALITY、Shadowsocks 2022 等 **Xray 代理节点**。每个节点单独累计**上传 + 下载**，额度单位为 **GiB（1 GiB = 1024³ 字节）**，支持小数。GOST 转发不通过 Xray StatsService，因此当前不支持这里的累计配额。

~~~bash
# 查看各条目的上传/下载、累计用量、额度和状态
sudo bash xray-manager.sh quota-list

# 给名为 reality-hk 的节点设置总量 10 GiB
sudo bash xray-manager.sh quota-set reality-hk 10

# 设为 0 表示取消配额
sudo bash xray-manager.sh quota-set reality-hk 0

# 清零已有流量记录；达到限额停用的节点也可因此恢复
sudo bash xray-manager.sh quota-reset reality-hk
~~~

首次设置额度后会安装、启用 `xray-multi-traffic.timer`，大约**每分钟**通过 Xray StatsService 采样一次。累计流量保存在单独文件中，正常服务重启不会自动清零；达到限额后，脚本会从 Xray 生效配置中移除对应入站，之后可通过清零、提高额度或取消额度恢复。

**限额与统计的重要边界**：

- 这是**分钟级累计配额**，不是硬实时限速。流量峰值可能在下一次检测之前超过设定值。
- Xray 意外终止或统计采样失败时，最后一段流量可能被漏计。
- 配额自动停用或恢复时会重启 `xray-multi`，其他节点的现有连接可能暂时中断。
- 统计的是 Xray 内部入站字节，不等同于 VPS 厂商账单计费流量，也不包含全部网络开销。
- 不要仅依靠此功能对抗恶意刷流量；同时配置云厂商流量告警、防火墙和预算保护。

## 9. 常用命令汇总

以下命令均在保存脚本的目录执行：

~~~bash
sudo bash xray-manager.sh install         # 安装 / 更新 Xray
sudo bash xray-manager.sh add-reality     # 新建 REALITY
sudo bash xray-manager.sh reality-check reality-hk  # 检查旧节点 SNI
sudo bash xray-manager.sh add-ss          # 新建 Shadowsocks 2022
sudo bash xray-manager.sh list            # 列出代理节点
sudo bash xray-manager.sh show reality-hk # 节点分享链接、二维码
sudo bash xray-manager.sh delete          # 交互删除代理节点
sudo bash xray-manager.sh status          # 状态、节点和转发规则
sudo bash xray-manager.sh restart         # 重启服务
sudo bash xray-manager.sh harden          # 已有 REALITY 回落限速加固
sudo bash xray-manager.sh forward-add     # 交互添加转发
sudo bash xray-manager.sh forward-list    # 查看转发规则
sudo bash xray-manager.sh forward-delete  # 交互删除转发
sudo bash xray-manager.sh quota-list      # 查看流量
sudo bash xray-manager.sh traffic-check   # 立即采样、执行配额检查
bash xray-manager.sh help                 # 命令行帮助
~~~

## 10. 文件与服务位置

| 路径 / 服务名 | 用途 |
| --- | --- |
| `/usr/local/bin/xray` | 脚本安装的 Xray 可执行文件 |
| `/usr/local/lib/xray-multi/gost` | 本工具私有的 GOST v3 可执行文件 |
| `/etc/xray-multi/config.json` | 生效的 Xray 合并配置（不含端口转发） |
| `/etc/xray-multi/gost-forward.json` | GOST 端口转发配置 |
| `/etc/xray-multi/reality-targets.txt` | 可选的随机 SNI 候选池 |
| `/var/lib/xray-multi/nodes.json` | 节点、转发及密钥数据库 |
| `/var/lib/xray-multi/traffic.json` | 持久化累计流量 |
| `/var/lib/xray-multi/qrcodes/` | 分享二维码 PNG |
| `xray-multi.service` | 本工具管理的 Xray 代理服务 |
| `xray-multi-forward.service` | 本工具管理的 GOST 端口转发服务 |
| `xray-multi-traffic.timer` | Xray 节点配额采样定时器（设置额度后启用） |

数据库、二维码及密钥仅应由管理员读取；**不要公开上传配置、流量文件或二维码**。

## 11. 故障排查

**客户端无法连接**：先运行以下命令查看服务和监听端口，再检查云平台安全组、本机防火墙、服务器公网 IP/域名，以及客户端协议设置。

~~~bash
sudo systemctl status xray-multi --no-pager
sudo systemctl status xray-multi-forward --no-pager
sudo journalctl -u xray-multi -n 100 --no-pager
sudo journalctl -u xray-multi-forward -n 100 --no-pager
sudo ss -lntup
~~~

**配置校验失败**：脚本会先测试候选 JSON，失败时保留原有节点配置。可查看终端中的 Xray 错误输出；不要通过手动覆盖在线 `config.json` 来绕过校验。

**REALITY 随机 SNI 报错**：普通 TLS 能连接并不保证 REALITY 一定能使用；脚本现在会跳过本机 REALITY 实测失败的候选。请检查 DNS、VPS 出站 443、TLS 1.3/h2、证书兼容性与 Cloudflare 排除。使用自定义域名时，需要是实际可达且受支持的 HTTPS 站点。

**流量统计不更新**：先查看 Xray 服务及定时器运行情况：

~~~bash
sudo systemctl status xray-multi-traffic.timer --no-pager
sudo journalctl -u xray-multi-traffic.service -n 100 --no-pager
sudo bash xray-manager.sh traffic-check
~~~

**端口转发不通**：先检查 `xray-multi-forward.service` 和 `/etc/xray-multi/gost-forward.json`，再确认 A 实际监听地址、A 入站防火墙、B 的目标服务及 B 对 A 出口 IP 的访问权限；UDP 应使用 UDP 测试工具确认，不能只用 TCP 连接测试代替。转发已与 Xray 主进程分离，不要再到 Xray `inbounds` 中寻找 `forward-*`。

## 12. 卸载

运行交互菜单并输入 `00`，或执行：

~~~bash
sudo bash xray-manager.sh uninstall
~~~

按提示输入 **`REMOVE`** 才会继续。卸载会清除本脚本管理的全部节点、转发规则、Xray/GOST 配置、二维码、流量记录及相关 systemd 服务，并删除本工具私有的 GOST 二进制；不可恢复。若脚本检测到其他正在使用 Xray 的服务，或二进制文件不是由本工具标记安装，可能保留 `/usr/local/bin/xray` 以避免影响其他程序。

**建议在卸载或迁移前备份重要资料**，并确保备份文件的访问权限安全。
