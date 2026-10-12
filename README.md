## Xray 多节点管理器（v1.5）

支持 VLESS + REALITY、Shadowsocks 2022、TCP / UDP 端口转发，以及各节点独立的累计流量配额。

**📘 [Xray 脚本完整使用说明（安装、菜单、节点、转发、流量限制、故障排查）](docs/xray-manager.md)**

快速开始：

~~~bash
curl -fsSLo xray-manager.sh https://raw.githubusercontent.com/kentinya/Script-repository/main/xray-manager.sh
sudo bash xray-manager.sh
~~~

首次启动选择 `01` 安装 Xray；以后运行同一脚本即可进入交互菜单。想直接查看命令行用法，可执行 `bash xray-manager.sh help`。

> 提示：流量配额为分钟级累计上/下行限额，不是硬实时限速；请同时做好防火墙和云平台流量告警。当前 REALITY TLS 目标检测还存在版本判断问题，详见[使用说明中的注意事项](docs/xray-manager.md#5-新建-vless--reality-节点)。

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
