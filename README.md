## Xray 多节点管理器（v1.5）

支持 VLESS + REALITY、Shadowsocks 2022、A IP:端口 → B IP:端口 转发，以及**每个节点独立的累计流量配额**。

安装或更新脚本：

```bash
curl -fsSLo xray-manager.sh https://raw.githubusercontent.com/kentinya/Script-repository/main/xray-manager.sh
sudo bash xray-manager.sh
```

在菜单中选择 **14 查看流量统计**、**15 设置单节点流量额度**、**16 流量清零/恢复节点**。也支持命令行：

```bash
sudo bash xray-manager.sh quota-set my-node 10     # 总上传+下载限额 10 GiB
sudo bash xray-manager.sh quota-list           # 查看全部节点用量
sudo bash xray-manager.sh quota-reset my-node  # 用量归零并恢复节点
sudo bash xray-manager.sh quota-set my-node 0  # 取消限额
```

首次设置后脚本会创建 `xray-multi-traffic.timer`，每分钟通过 Xray StatsService 采样。达到限额后自动从服务配置移除对应节点的入站；配额与累计流量持久化保存，重启后不自动清零。REALITY、Shadowsocks 和本脚本建立的端口转发规则都支持独立额度。

**注意：** 这是分钟级的流量配额管理，不是硬实时限速；高吞吐量可能在下一次检测前超过额度，非正常的 Xray 重启可能遗漏最后一段未采样流量。节点禁用/恢复需要重启 Xray，其他节点现有连接可能暂时中断。统计为 Xray 内部流量，不等同于云厂商账单计费流量。若用于防止恶意刷流量，请同时配置云平台流量告警和防火墙。

## Realm转发脚本使用
### 功能
- 一键添加配置
- 一键安装、更新、删除Realm
- 支持安装包本地安装
- 查看存在的配置规则
- 支持tls,ws,wss加密
- 支持证书配置
- 启动与查看日志
### 安装脚本使用
``` bash
wget -N https://raw.githubusercontent.com/kentinya/Script-repository/refs/heads/main/Realm/realm_install.sh && chmod +x realm_install.sh
```
``` bash
bash realm_install.sh
```
### 添加tls
```bash
wget -N https://raw.githubusercontent.com/kentinya/Script-repository/refs/heads/main/Realm/realm_tls.sh && chmod +x realm_tls.sh
```
``` bash
bash realm_tls.sh
```
## 增加虚拟内存脚本
### 功能
- 增加VPS虚拟内存
### 使用
```bash
wget -N https://raw.githubusercontent.com/kentinya/Script-repository/main/addswap/addswap.sh && chmod +x addswap.sh
```
``` bash
bash addswap.sh
```

## ip2location判断ip
### 功能
- 判断ip

### 使用
```bash
wget -N https://raw.githubusercontent.com/kentinya/Script-repository/main/ip2location/checkip.sh && chmod +x checkip.sh
```
``` bash
bash checkip.sh
```
## 生成strm文件

### 功能
- 根据分类、文件路径和根路径自动生成strm文件到指定文件夹

### 使用
```bash
wget -N https://raw.githubusercontent.com/kentinya/Script-repository/main/creat_strm/create_strm.py && chmod +x create_strm.py
```
``` bash
python3 create_strm.py "保存路径" "内容路径" "分类"
```

## 修改strm内容

### 功能

-  修改strm文件内的路径

### 使用

```bash
wget -N https://raw.githubusercontent.com/kentinya/Script-repository/main/creat_strm/replace_str_in_strm.sh && chmod +x replace_str_in_strm.sh
```
```bash
bash replace_str_in_strm.sh
```

## gost转发脚本使用

### 安装
``` bash
wget -N https://raw.githubusercontent.com/kentinya/Script-repository/refs/heads/main/gost/gost_install.sh && chmod +x gost_install.sh
```
``` bash
bash gost_install.sh
```

### 节点

``` bash
wget -N https://raw.githubusercontent.com/kentinya/Script-repository/refs/heads/main/gost/add_gost.sh && chmod +x add_gost.sh
```
``` bash
bash add_gost.sh
```
