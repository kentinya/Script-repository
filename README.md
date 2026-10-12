# Script Repository

## Xray 多节点管理器（v1.5）

支持 VLESS + Vision + REALITY、Shadowsocks 2022、TCP / UDP 端口转发，以及每个节点独立的累计流量配额。

- [Xray 脚本与测试（xray/）](xray/)
- **[Xray 详细使用说明](xray/README.md)**（安装、菜单、节点、随机 SNI、端口转发、流量配额、排错与卸载）

快速安装及启动：

```bash
curl -fsSLo xray-manager.sh https://raw.githubusercontent.com/kentinya/Script-repository/main/xray/xray-manager.sh
sudo bash xray-manager.sh
```

首次打开菜单选择 **01** 安装 Xray；再次管理可运行 `sudo bash xray-manager.sh`。使用 `bash xray-manager.sh help` 查看命令行帮助。

> 单节点流量配额是分钟级累计上/下行额度，不是硬实时限速。请同时配置防火墙及云平台流量告警。

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
