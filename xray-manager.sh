#!/usr/bin/env bash
# Xray 多节点管理器 v1.3：VLESS + Vision + REALITY / Shadowsocks 2022
# 支持 Linux + systemd，建议 Debian 12 / Ubuntu 22.04+ / Rocky Linux 9。
# 使用：sudo bash xray-manager.sh    或 sudo bash xray-manager.sh help
set -Eeuo pipefail
umask 077

APP='xray-multi'
BIN='/usr/local/bin/xray'
CONF_DIR='/etc/xray-multi'
CONFIG="$CONF_DIR/config.json"
DATA_DIR='/var/lib/xray-multi'
DB="$DATA_DIR/nodes.json"
QR_DIR="$DATA_DIR/qrcodes"
UNIT='/etc/systemd/system/xray-multi.service'
SERVICE='xray-multi.service'
RUN_USER='xraymulti'
MARKER="$DATA_DIR/installed-by-xray-multi"

# 终端视觉风格参考 Gum：强调色、分组、状态提示；不依赖额外 TUI 程序。
# 非交互环境、TERM=dumb、NO_COLOR 自动禁用 ANSI 控制符。
UI_RESET='' UI_BOLD='' UI_ACCENT='' UI_PURPLE='' UI_OK='' UI_WARN='' UI_BAD='' UI_DIM=''
if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && ! -v NO_COLOR ]]; then
  UI_RESET=$'\033[0m'     UI_BOLD=$'\033[1m'
  UI_ACCENT=$'\033[38;5;45m' UI_PURPLE=$'\033[38;5;141m'
  UI_OK=$'\033[38;5;78m' UI_WARN=$'\033[38;5;214m'
  UI_BAD=$'\033[38;5;203m' UI_DIM=$'\033[38;5;245m'
fi

say() {
  printf '\n%s  ◆ %s%s\n%s  ───────────────────────────────────────────────────────────%s\n' \
    "$UI_ACCENT$UI_BOLD" "$*" "$UI_RESET" "$UI_DIM" "$UI_RESET"
}
info() { printf '%s  ✓ %s%s\n' "$UI_OK" "$*" "$UI_RESET"; }
warn() { printf '%s  ! %s%s\n' "$UI_WARN" "$*" "$UI_RESET" >&2; }
die()  { printf '%s  ✗ %s%s\n' "$UI_BAD" "$*" "$UI_RESET" >&2; exit 1; }

# read -e 使用 Bash Readline：左右移动光标、Home/End、Delete、退格等。
# 普通 read 会把方向键的 ESC 序列当成文本，导致 ^[[D / ^[[C 等乱码。
# 默认值只显示在提示里；直接回车采用默认值，便于覆盖或留空。
ui_read() {
  local __var="$1" __prompt="$2" __value=''
  if [[ -t 0 ]]; then
    IFS= read -e -r -p "$__prompt" __value || return 1
  else
    IFS= read -r -p "$__prompt" __value || return 1
  fi
  printf -v "$__var" '%s' "$__value"
}

ui_pause() {
  local ignored
  if [[ -t 0 ]]; then
    ui_read ignored "  按 Enter 返回菜单… " || return 1
  else
    ui_read ignored '  按 Enter 返回菜单… ' || return 1
  fi
}

ui_section() {
  printf '\n%s  ── %s ────────────────────────────────────────────────────%s\n' \
    "$UI_PURPLE" "$1" "$UI_RESET"
}

ui_item() {
  local code="$1" label="$2"
  printf '  %s[%s]%s  %s\n' "$UI_ACCENT" "$code" "$UI_RESET" "$label"
}

ui_home() {
  local svc_text='尚未安装' svc_color="$UI_DIM" total=0 version='未安装'
  if [[ -f "$UNIT" ]]; then
    if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
      svc_text='运行中' svc_color="$UI_OK"
    else
      svc_text='未运行' svc_color="$UI_BAD"
    fi
  fi
  if [[ -f "$DB" ]] && command -v python3 >/dev/null 2>&1; then
    total="$(python3 - "$DB" <<'PY_NODE_COUNT'
import json,sys
try:
    with open(sys.argv[1],encoding='utf8') as f:
        print(len(json.load(f).get('nodes', [])))
except (OSError,ValueError,TypeError):
    print('?')
PY_NODE_COUNT
)"
  fi
  if [[ -x "$BIN" ]]; then
    version="$("$BIN" version 2>/dev/null | head -n1 | awk '{print $2}' || true)"
    version="${version:-未知版本}"
  fi
  if [[ -t 1 && -n "$UI_ACCENT" ]]; then
    printf '\033[2J\033[H'
  fi
  printf '%s' "$UI_ACCENT"
  cat <<'EOF_UI_BANNER'
  ╭──────────────────────────────────────────────────────────────╮
  │  ◆  X R A Y   M U L T I                            v1.3     │
  │     多协议 · 多节点 · 一站式安全管理                          │
  ╰──────────────────────────────────────────────────────────────╯
EOF_UI_BANNER
  printf '%s' "$UI_RESET"
  printf '  %s●%s 服务 %s%s%s    %s●%s 节点 %s%s%s    %s●%s Xray %s\n' \
    "$svc_color" "$UI_RESET" "$svc_color" "$svc_text" "$UI_RESET" \
    "$UI_ACCENT" "$UI_RESET" "$UI_BOLD" "$total" "$UI_RESET" \
    "$UI_ACCENT" "$UI_RESET" "$version"
  ui_section '基础维护'
  printf '  %s[01]%s  安装 Xray                 %s[02]%s  更新 Xray\n' \
    "$UI_ACCENT" "$UI_RESET" "$UI_ACCENT" "$UI_RESET"
  ui_section '节点管理'
  printf '  %s[03]%s  新建 VLESS · REALITY       %s[04]%s  新建 Shadowsocks 2022\n' \
    "$UI_ACCENT" "$UI_RESET" "$UI_ACCENT" "$UI_RESET"
  printf '  %s[05]%s  节点列表                  %s[06]%s  分享链接 / 二维码\n' \
    "$UI_ACCENT" "$UI_RESET" "$UI_ACCENT" "$UI_RESET"
  ui_item '07' '删除指定节点'
  ui_section '服务与安全'
  printf '  %s[08]%s  查看服务状态              %s[09]%s  重启 Xray 服务\n' \
    "$UI_ACCENT" "$UI_RESET" "$UI_ACCENT" "$UI_RESET"
  ui_item '10' 'REALITY 回落限速加固'
  ui_section '退出与卸载'
  printf '  %s[00]%s  卸载与删除全部节点 %s(危险)%s    %s[Q]%s   退出\n' \
    "$UI_BAD" "$UI_RESET" "$UI_BAD" "$UI_RESET" "$UI_ACCENT" "$UI_RESET"
  printf '\n%s  提示：输入编号后回车 · 文字输入支持 ← → / Home / End 编辑%s\n\n' \
    "$UI_DIM" "$UI_RESET"

}
check_root() {
  [[ "$(id -u)" -eq 0 ]] || die '请使用 root 执行，例如：sudo bash xray-manager.sh'
  [[ "$(uname -s)" == Linux ]] || die '仅支持 Linux。'
  [[ -d /run/systemd/system ]] || die '本脚本要求 systemd 已正常运行。'
}

install_packages() {
  local missing=() p
  for p in curl unzip openssl python3 qrencode ss; do
    command -v "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  ((${#missing[@]} == 0)) && return 0
  info "安装所需依赖：${missing[*]}"
  if command -v apt-get >/dev/null 2>&1; then
    local packages=(curl unzip openssl python3 qrencode iproute2)
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl unzip openssl python3 qrencode iproute
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl unzip openssl python3 qrencode iproute
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm --needed curl unzip openssl python qrencode iproute2
  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install curl unzip openssl python3 qrencode iproute2
  else
    die '不支持当前发行版的软件包管理器，请手动安装 curl unzip openssl python3 qrencode iproute2。'
  fi
  for p in curl unzip openssl python3 qrencode ss; do
    command -v "$p" >/dev/null 2>&1 || die "依赖安装失败：$p"
  done
}

arch_name() {
  case "$(uname -m)" in
    x86_64|amd64) echo 64 ;;
    i386|i686) echo 32 ;;
    aarch64|arm64) echo arm64-v8a ;;
    armv7l|armv7) echo arm32-v7a ;;
    armv6l) echo arm32-v6 ;;
    s390x|ppc64le|riscv64) uname -m ;;
    *) die "不支持的 CPU 架构：$(uname -m)" ;;
  esac
}

create_layout() {
  if ! id "$RUN_USER" >/dev/null 2>&1; then
    useradd --system --user-group --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin "$RUN_USER" \
      || die '创建 Xray 运行用户失败。'
  fi
  install -d -m 750 -o root -g "$RUN_USER" "$CONF_DIR"
  install -d -m 700 -o root -g root "$DATA_DIR" "$QR_DIR"
  if [[ ! -f "$DB" ]]; then
    printf '{"nodes":[]}\n' >"$DB"
    chmod 600 "$DB"
  fi
  if [[ ! -f "$CONFIG" ]]; then
    printf '{"log":{"loglevel":"warning"},"inbounds":[],"outbounds":[{"protocol":"freedom","tag":"direct"}]}\n' >"$CONFIG"
    chown root:"$RUN_USER" "$CONFIG"
    chmod 640 "$CONFIG"
  fi
}

write_unit() {
  cat >"$UNIT" <<'EOF'
[Unit]
Description=Xray Multi-Protocol Manager
Documentation=https://github.com/XTLS/Xray-core
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=xraymulti
Group=xraymulti
ExecStart=/usr/local/bin/xray run -config /etc/xray-multi/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 "$UNIT"
  systemctl daemon-reload
}

install_xray() {
  install_packages
  local arch release_url latest zip_url dgst_url temp expected actual
  arch="$(arch_name)"
  release_url='https://api.github.com/repos/XTLS/Xray-core/releases/latest'
  say '获取 Xray 官方最新正式版……'
  latest="$(curl -fsSL --retry 3 --connect-timeout 15 --max-time 40 "$release_url" \
    | python3 -c 'import json,sys;print(json.load(sys.stdin)["tag_name"])')" \
    || die '获取 GitHub 版本失败。'
  [[ "$latest" =~ ^v[0-9][0-9A-Za-z.+-]*$ ]] || die "异常版本号：$latest"
  temp="$(mktemp -d)"
  trap '[[ -n "${temp:-}" ]] && rm -rf -- "$temp"' EXIT
  zip_url="https://github.com/XTLS/Xray-core/releases/download/${latest}/Xray-linux-${arch}.zip"
  dgst_url="${zip_url}.dgst"
  info "下载 ${latest} (${arch})"
  curl -fLsS --retry 3 --connect-timeout 15 --max-time 240 -o "$temp/xray.zip" "$zip_url" || die '下载 Xray 失败。'
  curl -fLsS --retry 3 --connect-timeout 15 --max-time 40 -o "$temp/xray.dgst" "$dgst_url" || die '下载 SHA256 校验信息失败。'
  expected="$(python3 - "$temp/xray.dgst" <<'PY'
import re,sys
text=open(sys.argv[1],encoding='utf-8',errors='replace').read()
m=re.search(r'(?im)(?:SHA2?-?256)\s*=\s*([a-f0-9]{64})',text)
print(m.group(1).lower() if m else '')
PY
)"
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || die '无法读取官方 SHA256，停止安装。'
  actual="$(sha256sum "$temp/xray.zip" | awk '{print $1}')"
  [[ "$expected" == "$actual" ]] || die 'Xray 安装包 SHA256 校验失败！'
  unzip -q "$temp/xray.zip" xray -d "$temp" || die '解压 Xray 可执行文件失败。'
  "$temp/xray" version >/dev/null || die '新版本 Xray 无法在本机运行。'
  # 备份现有可执行文件，防止新版本异常导致无法回滚。
  local old_bin=''
  if [[ -e "$BIN" ]]; then
    old_bin="$temp/xray.old"
    cp -p "$BIN" "$old_bin"
  fi
  install -m 755 "$temp/xray" "$BIN"
  create_layout
  touch "$MARKER"
  chmod 600 "$MARKER"
  write_unit
  if [[ -s "$DB" ]] && ! "$BIN" run -test -config "$CONFIG"; then
    if [[ -n "$old_bin" ]]; then install -m 755 "$old_bin" "$BIN"; else rm -f "$BIN"; fi
    die '升级后的 Xray 无法校验现有配置，已恢复旧程序。'
  fi
  systemctl enable "$SERVICE" >/dev/null
  if ! systemctl restart "$SERVICE"; then
    if [[ -n "$old_bin" ]]; then
      install -m 755 "$old_bin" "$BIN"
      systemctl restart "$SERVICE" || true
    fi
    die '服务启动失败，请执行 journalctl -u xray-multi -n 50 查看原因。'
  fi
  info "Xray ${latest} 已安装/更新，服务 ${SERVICE} 运行中。"
  rm -rf -- "$temp"
  trap - EXIT
}

require_installed() {
  [[ -x "$BIN" && -f "$DB" && -f "$UNIT" ]] || {
    warn '尚未完成初始化，开始安装 Xray……'
    install_xray
  }
}

ask() {
  # ask VAR "提示" "默认值"；支持通过 Readline 原位修改输入。
  local var="$1" prompt="$2" fallback="${3:-}" val=''
  if [[ -n "$fallback" ]]; then
    ui_read val "  › ${prompt} [${fallback}]: " \
      || die '输入已取消。'
    val="${val:-$fallback}"
  else
    ui_read val "  › ${prompt}: " || die '输入已取消。'
  fi
  printf -v "$var" '%s' "$val"
}

valid_name() { [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,47}$ ]]; }
valid_port() { [[ "$1" =~ ^[0-9]{1,5}$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535)); }
valid_host() {
  # 域名 / IPv4 / IPv6；不允许包含 URL、路径、空格、冒号端口。
  python3 - "$1" <<'PY'
import ipaddress,re,sys
h=sys.argv[1]
try:
    ipaddress.ip_address(h); sys.exit(0)
except ValueError: pass
if len(h)>253 or not re.fullmatch(r'[A-Za-z0-9.-]+',h) or '..' in h or h.startswith('-') or h.endswith('-'):
    sys.exit(1)
if not all(len(x)<=63 and x and not x.startswith('-') and not x.endswith('-') for x in h.split('.')):
    sys.exit(1)
PY
}
valid_sni() {
  [[ "$1" != *:* ]] && valid_host "$1" && [[ "$1" == *.* ]]
}

port_available() {
  local port="$1" name="$2"
  # 已由本工具管理的监听端口，双协议均不允许同端口复用。
  python3 - "$DB" "$port" "$name" <<'PY'
import json,sys
with open(sys.argv[1]) as f: d=json.load(f)
assert all(int(n['port'])!=int(sys.argv[2]) for n in d['nodes']), '该端口已被其他 Xray 节点使用'
assert all(n['name']!=sys.argv[3] for n in d['nodes']), '节点名称已存在'
PY
  # 排除系统中其他进程已绑定的 TCP / UDP 端口。
  if ss -H -lntu 2>/dev/null | awk '{print $5}' | grep -Eq "(^|[^0-9])[:.]${port}$"; then
    die "端口 $port 已被其他程序占用。"
  fi
}

public_address() {
  local guessed
  guessed="$(curl -4fsS --connect-timeout 4 --max-time 7 https://api.ipify.org 2>/dev/null || true)"
  printf '%s' "$guessed"
}

ask_base() {
  local preferred="${1:-443}" guess
  guess="$(public_address)"
  ask NODE_NAME '节点名称（字母、数字、下划线、短横线）' ''
  valid_name "$NODE_NAME" || die '节点名称不合法。'
  ask NODE_PORT '监听端口' "$preferred"
  valid_port "$NODE_PORT" || die '端口必须是 1-65535。'
  NODE_PORT="$((10#$NODE_PORT))"
  port_available "$NODE_PORT" "$NODE_NAME"
  ask NODE_HOST '服务器公网 IP 或域名（用于分享链接）' "$guess"
  valid_host "$NODE_HOST" || die '无效 IP 或域名。'
}

# 生成变更候选数据及 Xray 整体配置，不直接覆盖线上文件。
make_candidate() {
  local action="$1" name="$2" kind="${3:-}" port="${4:-}" host="${5:-}" \
        uuid="${6:-}" priv="${7:-}" pub="${8:-}" sid="${9:-}" \
        sni="${10:-}" dest="${11:-}" method="${12:-}" psk="${13:-}"
  local candidate_db="$DATA_DIR/.nodes.pending.json" candidate_config="$CONF_DIR/.config.pending.json"
  rm -f "$candidate_db" "$candidate_config"
  python3 - "$DB" "$candidate_db" "$candidate_config" \
    "$action" "$name" "$kind" "$port" "$host" "$uuid" "$priv" "$pub" \
    "$sid" "$sni" "$dest" "$method" "$psk" <<'PY'
import json,sys,os
(db_path,new_db,new_conf,action,name,kind,port,host,uuid,priv,pub,sid,sni,dest,method,psk)=sys.argv[1:]
with open(db_path,encoding='utf-8') as f:
    db=json.load(f)
nodes=db['nodes']
if action=='add':
    if any(n['name']==name or n['port']==int(port) for n in nodes):
        raise ValueError('节点名称或监听端口已存在')
    node=dict(name=name,kind=kind,port=int(port),host=host)
    if kind=='reality':
        node.update(uuid=uuid,private_key=priv,public_key=pub,short_id=sid,sni=sni,dest=dest)
    elif kind=='ss2022':
        node.update(method=method,password=psk)
    else: raise ValueError('不支持的协议类型')
    nodes.append(node)
elif action=='delete':
    if not any(n['name']==name for n in nodes): raise ValueError('找不到指定节点')
    db['nodes']=[n for n in nodes if n['name']!=name]
    nodes=db['nodes']
elif action=='harden':
    pass
else: raise ValueError('无效操作')
import secrets
for n in nodes:
    if n['kind']=='reality' and 'fallback_limit' not in n:
        # 对每个节点持久化不同的限速数值，避免统一参数形成固定特征。
        up=(24+secrets.randbelow(25))*1024
        down=(48+secrets.randbelow(49))*1024
        n['fallback_limit']={
            'upload':{'afterBytes':(16+secrets.randbelow(49))*1024,
                      'bytesPerSec':up,'burstBytesPerSec':up*2},
            'download':{'afterBytes':(32+secrets.randbelow(97))*1024,
                        'bytesPerSec':down,'burstBytesPerSec':down*2}
        }
inbounds=[]
for n in nodes:
    if n['kind']=='reality':
        inbounds.append({
            'tag':'reality-'+n['name'], 'listen':'0.0.0.0', 'port':n['port'],
            'protocol':'vless',
            'settings':{'clients':[{'id':n['uuid'],'flow':'xtls-rprx-vision'}], 'decryption':'none'},
            'streamSettings':{'network':'tcp','security':'reality','realitySettings':{
                'target':n['dest'],'serverNames':[n['sni']],
                'privateKey':n['private_key'],'shortIds':[n['short_id']],
                'limitFallbackUpload':n['fallback_limit']['upload'],
                'limitFallbackDownload':n['fallback_limit']['download']
            }},
            'sniffing':{'enabled':True,'destOverride':['http','tls','quic'],'routeOnly':True}
        })
    else:
        inbounds.append({
            'tag':'ss2022-'+n['name'], 'listen':'0.0.0.0', 'port':n['port'],
            'protocol':'shadowsocks', 'settings':{
                'method':n['method'],'password':n['password'],'network':'tcp,udp'
            }
        })
conf={'log':{'loglevel':'warning'},'inbounds':inbounds,
      'outbounds':[{'protocol':'freedom','tag':'direct'}, {'protocol':'blackhole','tag':'block'}]}
for path,data in [(new_db,db),(new_conf,conf)]:
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w',encoding='utf-8') as f:
        json.dump(data,f,ensure_ascii=False,indent=2)
        f.write('\n')
PY
}

apply_candidate() {
  local staged_db="$DATA_DIR/.nodes.pending.json" staged_config="$CONF_DIR/.config.pending.json"
  local old_db="$DATA_DIR/.nodes.rollback" old_config="$DATA_DIR/.config.rollback"
  [[ -s "$staged_db" && -s "$staged_config" ]] || die '候选配置文件丢失。'
  if ! "$BIN" run -test -format json -config "$staged_config"; then
    rm -f "$staged_db" "$staged_config"
    die 'Xray 配置校验失败：未修改原来的节点。'
  fi
  cp -p "$DB" "$old_db"
  cp -p "$CONFIG" "$old_config"
  chown root:"$RUN_USER" "$staged_config"
  chmod 640 "$staged_config"
  chmod 600 "$staged_db"
  mv -f "$staged_db" "$DB"
  mv -f "$staged_config" "$CONFIG"
  if ! systemctl restart "$SERVICE" || ! { sleep 1; systemctl is-active --quiet "$SERVICE"; }; then
    warn '服务重启失败，恢复原有配置。'
    cp -p "$old_db" "$DB"
    cp -p "$old_config" "$CONFIG"
    systemctl restart "$SERVICE" || warn '旧服务恢复也失败，请检查系统日志。'
    rm -f "$old_db" "$old_config"
    return 1
  fi
  rm -f "$old_db" "$old_config"
  return 0
}

# REALITY 目标检测器：仅使用标准 Python 库，无需额外 Python 包。
# random: 本机出口 IP 的 ASN > 国家 > 洲 匹配优先；verify: 校验手工 SNI/目标。
# Cloudflare 已知 IP 段 / ASN 13335 强制拒绝；不成功时不会静默放行。
# 地理位置数据来自 ipwho.is，匹配结果仅供参考（Anycast/数据库可能不准）。
# 自定义池支持 "DE www.example.de" 或 "www.example.de"，前者只作为提示，
# 不会替代对目标真实 IP 的定位。
reality_target_probe() {
  local mode="$1" server_ip="$2" sni="${3:-}" dest_host="${4:-}" dest_port="${5:-443}"
  python3 - "$mode" "$server_ip" "$sni" "$dest_host" "$dest_port" "$CONF_DIR/reality-targets.txt" "$DATA_DIR/geo-cache.json" <<'PY_REALITY_TARGET'
import ipaddress
import json
import os
import pathlib
import random
import re
import socket
import ssl
import sys
import time
import urllib.request

mode, server_ip, sni, dest_host, dest_port, targets_path, cache_path = sys.argv[1:]
# Cloudflare 官方公布的网段快照；联网时还会尝试获取最新列表。
CF_CIDRS = """103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 104.16.0.0/13
104.24.0.0/14 108.162.192.0/18 131.0.72.0/22 141.101.64.0/18
162.158.0.0/15 172.64.0.0/13 173.245.48.0/20 188.114.96.0/20
190.93.240.0/20 197.234.240.0/22 198.41.128.0/17
2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32
2405:8100::/32 2a06:98c0::/29 2c0f:f248::/32"""
cf_networks = [ipaddress.ip_network(x) for x in CF_CIDRS.split()]

def log(message):
    print('[目标检测] ' + message, file=sys.stderr)

def request_text(url, timeout=3):
    req=urllib.request.Request(url, headers={'User-Agent':'xray-multi/1.2'})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.read(32768).decode('utf-8')

# 官方增量更新的网段用于补足快照，失败时继续使用内置网段。
for fam in (4,6):
    try:
        values=request_text('https://www.cloudflare.com/ips-v'+str(fam), timeout=2).split()
        new=[ipaddress.ip_network(v, strict=True) for v in values]
        if not new:
            raise ValueError('空网段列表')
        cf_networks.extend(new)
    except Exception:
        log('Cloudflare v%d 网段更新不可用，使用内置网段。' % fam)

try:
    cache=json.loads(pathlib.Path(cache_path).read_text(encoding='utf-8'))
    if not isinstance(cache,dict): cache={}
except (OSError,ValueError):
    cache={}

def geo(ip):
    if ip in cache and time.time()-cache[ip].get('ts',0)<86400:
        return cache[ip].get('data')
    try:
        obj=json.loads(request_text('https://ipwho.is/'+ip, timeout=3))
        if obj.get('success') is not True:
            return None
        data={'country':obj.get('country_code',''),
              'continent':obj.get('continent_code',''),
              'asn':int((obj.get('connection') or {}).get('asn') or 0)}
        if data['country'] or data['asn']:
            cache[ip]={'ts':time.time(),'data':data}
            return data
    except (OSError,ValueError,TypeError,KeyError):
        pass
    return None

def save_cache():
    try:
        # 原有数据文件为 root 私有目录；原子写入并限制权限。
        path=pathlib.Path(cache_path)
        tmp=path.with_name(path.name+'.tmp')
        fd=os.open(str(tmp),os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
        with os.fdopen(fd,'w',encoding='utf-8') as f:
            json.dump(cache,f)
        os.replace(tmp,path)
    except OSError:
        pass

def host_ok(h):
    return (len(h)<=253 and '.' in h and '..' not in h
            and bool(re.fullmatch(r'[A-Za-z0-9.-]+',h))
            and all(0<len(x)<=63 and not x.startswith('-')
                    and not x.endswith('-') for x in h.split('.')))

def addresses(host,port):
    records=socket.getaddrinfo(host,port,type=socket.SOCK_STREAM)
    seen=set()
    out=[]
    for family,kind,proto,canon,sockaddr in records:
        ip=ipaddress.ip_address(sockaddr[0])
        if not ip.is_global:
            raise ValueError('DNS 返回非公网地址：'+str(ip))
        if any(ip in n for n in cf_networks):
            raise ValueError('解析到 Cloudflare IP：'+str(ip))
        if str(ip) not in seen:
            seen.add(str(ip))
            out.append((family,sockaddr,str(ip)))
    if not out:
        raise ValueError('没有可用地址')
    # 优先使用 IPv4，跨区域服务器的 IPv6 未必通畅。
    return sorted(out,key=lambda row:0 if row[0]==socket.AF_INET else 1)

ctx=ssl.create_default_context()
ctx.minimum_version=ssl.TLSVersion.TLSv1_3
ctx.maximum_version=ssl.TLSVersion.TLSv1_3
ctx.set_alpn_protocols(['h2'])

def tls_probe(host,port,server_name):
    addrs=addresses(host,port)
    last=None
    for family, addr, ip in addrs:
        try:
            with socket.socket(family,socket.SOCK_STREAM) as sock:
                sock.settimeout(3)
                sock.connect(addr)
                with ctx.wrap_socket(sock,server_hostname=server_name) as tls:
                    if tls.version()=='TLSv1.3' and tls.selected_alpn_protocol()=='h2':
                        return ip
                    last='TLS 1.3 或 h2 不符合要求'
        except (OSError,ssl.SSLError) as e:
            last=str(e)
    raise ValueError(last or 'TLS 握手失败')

# VPS 机房地址从服务器自身公网出口检测（而不是本地电脑）。
try:
    ipaddress.ip_address(server_ip)
    server=geo(server_ip)
except ValueError:
    server=None
if server:
    log('机房参考位置：%s / %s，ASN %s。' % (
        server.get('country') or '未知',server.get('continent') or '未知',server.get('asn') or '未知'))
else:
    log('服务器地理信息查询失败：将只进行 TLS 与 Cloudflare 检查；地域匹配不可保证。')

# 即使启用了用户自定义国家代码，仍以目标 IP 地理信息做选择判断。
country_override=os.environ.get('XRAY_GEO_COUNTRY','').strip().upper()
if re.fullmatch('[A-Z]{2}',country_override):
    server=(server or {}).copy()
    server['country']=country_override
    log('使用管理员指定的国家代码 %s。' % country_override)

def score(geo_data, country_hint=''):
    if not server or not geo_data:
        return (1 if country_hint and server and country_hint==server.get('country') else 0,'地域未知')
    if geo_data.get('asn') and geo_data['asn']==server.get('asn'):
        return 4,'同 ASN'
    if geo_data.get('country') and geo_data['country']==server.get('country'):
        return 3,'同国家/地区'
    if geo_data.get('continent') and geo_data['continent']==server.get('continent'):
        return 2,'同大洲'
    return 0,'其他地区'

try:
    if mode=='verify':
        if not host_ok(sni) or not host_ok(dest_host):
            raise ValueError('SNI 或目标域名格式错误')
        port=int(dest_port)
        if not 1<=port<=65535:
            raise ValueError('目标端口错误')
        ip=tls_probe(dest_host,port,sni)
        target_geo=geo(ip)
        if target_geo and target_geo.get('asn')==13335:
            raise ValueError('Cloudflare ASN 13335：禁止作为伪装目标')
        rank,kind=score(target_geo)
        log('已验证：%s -> %s；%s，目标国家/地区 %s，ASN %s。' % (
            sni,ip,kind,(target_geo or {}).get('country','未知'),
            (target_geo or {}).get('asn','未知')))
        # DNS/证书验证通过，地理不符合只提示，不影响手动模式。
        print(sni)
    elif mode=='random':
        builtin=['www.microsoft.com','www.apple.com','www.samsung.com',
                 'www.ibm.com','www.adobe.com','www.oracle.com',
                 'www.amazon.com','www.bing.com','github.com',
                 'www.mozilla.org','www.python.org','www.ubuntu.com',
                 'www.sony.com','www.intel.com','www.dell.com',
                 'www.cisco.com','www.hp.com','www.lenovo.com',
                 'www.nvidia.com','www.asus.com','www.wikipedia.org']
        path=pathlib.Path(targets_path)
        if path.exists():
            lines=path.read_text(encoding='utf-8').splitlines()
            choices=[]
            for line in lines:
                line=line.split('#',1)[0].strip()
                if not line: continue
                parts=line.split()
                if len(parts)==1: choices.append(('',parts[0]))
                elif len(parts)==2 and re.fullmatch('[A-Za-z]{2}',parts[0]):
                    choices.append((parts[0].upper(),parts[1]))
                else: log('忽略无效候选行：'+line[:80])
        else:
            choices=[('',x) for x in builtin]
        choices=list(dict.fromkeys((hint,h.lower()) for hint,h in choices if host_ok(h)))
        if not choices:
            raise ValueError('随机 SNI 候选池为空：请检查 reality-targets.txt')
        random.SystemRandom().shuffle(choices)
        # 有地区标注的候选优先测试，实际定位仍由解析 IP 决定。
        if server and server.get('country'):
            choices.sort(key=lambda t:t[0]!=server['country'])
        best_rank=-1
        best=[]
        checked=0
        for hint,host in choices[:20]:
            checked+=1
            try:
                ip=tls_probe(host,443,host)
                data=geo(ip)
                if data and data.get('asn')==13335:
                    log('%s 已排除：Cloudflare ASN 13335。' % host)
                    continue
                rank,kind=score(data,hint)
                if rank>best_rank:
                    best_rank=rank
                    best=[(host,ip,kind,data)]
                elif rank==best_rank:
                    best.append((host,ip,kind,data))
                if rank==4 and len(best)>=2:
                    break
            except (OSError,ValueError) as e:
                log('%s 已跳过：%s' % (host,str(e)[:95]))
        if not best:
            raise ValueError('无法找到非 Cloudflare 且支持 TLS 1.3/h2 的目标；请换目标池或手动指定')
        selected=random.SystemRandom().choice(best)
        host,ip,kind,data=selected
        log('从 %d 个候选中选中 %s (%s)，目标 IP %s、国家/地区 %s、ASN %s。' % (
            checked,host,kind,ip,(data or {}).get('country','未知'),
            (data or {}).get('asn','未知')))
        if best_rank<2:
            log('警告：没有找到可验证的同国/同洲目标；建议在候选池中补充当地网站。')
        print(host)
    else:
        raise ValueError('未知目标检测模式')
except (OSError,ValueError) as e:
    sys.exit('[-] REALITY 目标检测失败：'+str(e))
finally:
    save_cache()
PY_REALITY_TARGET
}

# 用此函数可以在创建前重新检测手动指定的目标地址，防止改目标绕过 Cloudflare 检查。
random_reality_sni() {
  reality_target_probe random "$1"
}

add_reality() {
  require_installed
  say '新增 VLESS + Vision + REALITY 节点'
  ask_base 443
  local sni dest raw priv pub uuid sid dest_host dest_port server_ip was_random=0
  server_ip="$(public_address)"
  ask sni 'REALITY 伪装目标 SNI（输入 random 随机选择，或手动填写域名）' 'random'
  case "${sni,,}" in
    random|r)
      info '随机检测支持 TLS 1.3 + HTTP/2 (h2) 的 SNI 目标……'
      was_random=1
      sni="$(random_reality_sni "$server_ip")" || die '自动选择 REALITY SNI 失败。'
      info "本次随机选中 SNI：$sni"
      ;;
    *) valid_sni "$sni" || die 'SNI 必须是有效域名。' ;;
  esac
  ask dest 'REALITY 目标地址（域名:端口）' "$sni:443"
  [[ "$dest" =~ ^([^:]+):([0-9]{1,5})$ ]] || die 'REALITY 目标地址格式不正确。'
  dest_host="${BASH_REMATCH[1]}"
  dest_port="${BASH_REMATCH[2]}"
  valid_host "$dest_host" && valid_port "$dest_port" || die 'REALITY 目标域名或端口不合法。'
  if [[ "$dest_host" != "$sni" ]]; then
    warn '目标地址与 SNI 不相同，将按真实目标地址检测 TLS 与 Cloudflare。'
  fi
  # 手动 SNI 必须验证；随机结果修改了目标地址也必须重验。
  if ((was_random == 0)) || [[ "$dest" != "$sni:443" ]]; then
    info '检测指定的目标是否支持 TLS 1.3/h2，以及是否使用 Cloudflare……'
    reality_target_probe verify "$server_ip" "$sni" "$dest_host" "$dest_port" >/dev/null \
      || die '该 REALITY 目标不可用或不安全，已阻止创建节点。'
  fi
  raw="$("$BIN" x25519)" || die 'REALITY 密钥生成失败。'
  read -r priv pub < <(python3 - "$raw" <<'PY'
import re,sys
pairs={}
for line in sys.argv[1].splitlines():
    if ':' in line:
        k,v=line.split(':',1)
        pairs[re.sub(r'[^a-z]','',k.lower())]=v.strip().split()[0]
private=pairs.get('privatekey','')
public=next((v for k,v in pairs.items() if k.startswith('publickey') or k.startswith('password')), '')
print(private, public)
PY
)
  [[ "$priv" =~ ^[a-zA-Z0-9_-]{40,50}$ && "$pub" =~ ^[a-zA-Z0-9_-]{40,50}$ ]] \
    || die '解析 xray x25519 输出失败；请确认所安装的 Xray 版本。'
  uuid="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  sid="$(openssl rand -hex 8)"
  make_candidate add "$NODE_NAME" reality "$NODE_PORT" "$NODE_HOST" "$uuid" "$priv" "$pub" "$sid" "$sni" "$dest" '' ''
  apply_candidate || die '节点创建失败。'
  info 'REALITY 节点已创建并启动。'
  show_node "$NODE_NAME"
  warn '请同时在云厂商安全组 / 系统防火墙放行该 TCP 端口。'
}

add_ss() {
  require_installed
  say '新增 Shadowsocks 2022 节点'
  ask_base 8388
  local method opt password length
  printf '加密方式：\n  1) 2022-blake3-aes-128-gcm（默认）\n  2) 2022-blake3-aes-256-gcm\n  3) 2022-blake3-chacha20-poly1305\n'
  ask opt '选择' '1'
  case "$opt" in
    1) method='2022-blake3-aes-128-gcm'; length=16 ;;
    2) method='2022-blake3-aes-256-gcm'; length=32 ;;
    3) method='2022-blake3-chacha20-poly1305'; length=32 ;;
    *) die '无效加密方式。' ;;
  esac
  password="$(openssl rand -base64 "$length" | tr -d '\n')"
  make_candidate add "$NODE_NAME" ss2022 "$NODE_PORT" "$NODE_HOST" '' '' '' '' '' '' "$method" "$password"
  apply_candidate || die '节点创建失败。'
  info 'Shadowsocks 2022 节点已创建并启动（TCP + UDP）。'
  show_node "$NODE_NAME"
  warn '请同时在云厂商安全组 / 系统防火墙放行该 TCP 和 UDP 端口。'
}

node_names() {
  [[ -f "$DB" ]] || { warn '暂无节点。'; return 0; }
  python3 - "$DB" <<'PY'
import json,sys
with open(sys.argv[1]) as f: a=json.load(f)['nodes']
if not a: print('暂无节点。')
else:
    print(f"{'名称':<20} {'协议':<12} {'端口':<7} {'连接地址'}")
    for n in a:
        print(f"{n['name']:<20} {n['kind']:<12} {n['port']:<7} {n['host']}")
PY
}

show_node() {
  local name="${1:-}" url kind port host
  [[ -f "$DB" ]] || die '暂无节点。'
  if [[ -z "$name" ]]; then
    node_names
    ask name '输入要查看的节点名称' ''
  fi
  local result
  result="$(python3 - "$DB" "$name" <<'PY'
import json,sys,base64,urllib.parse,ipaddress
with open(sys.argv[1]) as f: nodes=json.load(f)['nodes']
n=next((n for n in nodes if n['name']==sys.argv[2]),None)
if n is None: sys.exit('找不到节点')
host=n['host']
try:
    if ipaddress.ip_address(host).version==6: host='['+host+']'
except ValueError: pass
frag=urllib.parse.quote(n['name'],safe='')
if n['kind']=='reality':
    q=urllib.parse.urlencode({'encryption':'none','flow':'xtls-rprx-vision','security':'reality',
        'sni':n['sni'],'fp':'chrome','pbk':n['public_key'],'sid':n['short_id'],'type':'tcp'})
    url=f"vless://{n['uuid']}@{host}:{n['port']}?{q}#{frag}"
else:
    u=f"{n['method']}:{n['password']}".encode()
    b64=base64.urlsafe_b64encode(u).decode().rstrip('=')
    url=f"ss://{b64}@{host}:{n['port']}#{frag}"
print(n['kind'])
print(url)
PY
)" || die '找不到该节点。'
  kind="${result%%$'\n'*}"
  url="${result#*$'\n'}"
  say "节点：$name ($kind)"
  printf '\n分享链接：\n%s\n\n' "$url"
  if command -v qrencode >/dev/null 2>&1; then
    qrencode -t ANSIUTF8 -m 1 "$url" || warn '终端无法渲染二维码。'
    install -d -m 700 -o root -g root "$QR_DIR"
    qrencode -t PNG -s 6 -m 2 -o "$QR_DIR/$name.png" "$url" || warn 'PNG 二维码保存失败。'
    chmod 600 "$QR_DIR/$name.png" 2>/dev/null || true
    info "二维码 PNG：$QR_DIR/$name.png"
  else
    warn '未发现 qrencode，请先通过“安装 / 更新”安装依赖。'
  fi
  warn '分享链接和二维码均包含连接密钥，请勿公开传播。'
}

delete_node() {
  require_installed
  node_names
  local name confirm
  ask name '要删除的节点名称' ''
  valid_name "$name" || die '节点名称不合法。'
  ask confirm "确定删除 [$name] 吗？请输入 YES" ''
  [[ "$confirm" == YES ]] || { info '已取消。'; return; }
  make_candidate delete "$name"
  apply_candidate || die '删除节点失败。'
  rm -f "$QR_DIR/$name.png"
  info "节点 $name 已删除，其他节点保持运行。"
}


harden_reality() {
  require_installed
  say '为已有 REALITY 节点设置随机化的回落限速'
  warn '这只降低未认证回落连接的流量风险；不会更换旧节点的 SNI 或自动移除既有 Cloudflare 目标。'
  make_candidate harden ''
  apply_candidate || die '安全加固失败。'
  info '全部 REALITY 配置已应用回落限速。请检查旧节点目标域名是否使用 Cloudflare。'
}

status() {
  if [[ -x "$BIN" ]]; then "$BIN" version | head -n 1; else warn '尚未安装 Xray。'; fi
  if [[ -f "$UNIT" ]]; then
    systemctl --no-pager --full status "$SERVICE" || true
  else
    warn '服务尚未安装。'
  fi
  node_names
}

uninstall_all() {
  local confirm
  say '卸载 Xray Multi'
  warn '此操作将删除本脚本管理的所有节点、链接和二维码（不可恢复）。'
  ask confirm '确认卸载请输入 REMOVE' ''
  [[ "$confirm" == REMOVE ]] || { info '已取消。'; return; }
  systemctl disable --now "$SERVICE" >/dev/null 2>&1 || true
  rm -f "$UNIT"
  systemctl daemon-reload
  if [[ -f "$MARKER" ]]; then
    # 注意：本工具只清理它安装标记下的二进制文件；其他 xray.service 可能依赖它。
    if systemctl is-active --quiet xray.service 2>/dev/null || \
       systemctl is-active --quiet 'xray@*.service' 2>/dev/null; then
      warn '检测到其他 Xray 服务在运行，为避免损坏现有服务，保留 Xray 可执行文件。'
    else
      rm -f "$BIN"
      info '已移除由本脚本安装的 Xray 可执行文件。'
    fi
  else
    warn 'Xray 可执行文件并非由本脚本标记安装，保留以免影响其他程序。'
  fi
  rm -rf -- "$CONF_DIR" "$DATA_DIR"
  info '已删除本工具的服务和所有管理数据。'
}

help_text() {
  cat <<'EOF'
Xray 多配置管理器 v1.3（需要 root，Linux + systemd）

用法：sudo bash xray-manager.sh [命令] [节点名]
  不传参数        彩色中文交互菜单（文本输入支持左右方向键）
  install         安装 / 更新 Xray（官方最新正式版，验证 SHA256）
  update          同 install
  add-reality     新增 VLESS + Vision + REALITY
  add-ss          新增 Shadowsocks 2022 (TCP + UDP)
  list            列出所有节点
  show 节点名      显示分享链接、终端二维码、PNG 二维码
  delete          删除指定节点
  status          查看服务状态 / 所有节点
  restart         重启服务
  harden          给已有 REALITY 节点加回落限速（不更换 SNI）
  uninstall       卸载本工具管理的配置和 Xray
  help            显示帮助

路径：
  /etc/xray-multi/config.json          Xray 合并配置
  /var/lib/xray-multi/nodes.json       包含密钥的节点数据库（root 专用）
  /var/lib/xray-multi/qrcodes/         二维码（root 专用）
  /etc/systemd/system/xray-multi.service

提示：
  1. 防火墙和云平台安全组请自行放行节点端口；SS2022 同时需要 TCP/UDP。
  2. REALITY 默认根据机房公网 IP 的 ASN / 国家 / 大洲优选 TLS1.3+h2 目标。
     默认排除 Cloudflare IP/ASN，对人工目标也做 TLS + Cloudflare 检测。
     可选：编辑 /etc/xray-multi/reality-targets.txt，每行一个域名；也可写 DE www.example.de。
     可选：XRAY_GEO_COUNTRY=DE sudo -E bash xray-manager.sh add-reality 强制机房国家代码。
     IP 地理定位不保证精确；目标 CDN 解析和路由可能随时间变化。
  3. 新建节点默认对 REALITY 认证失败的回落连接设置随机化限速（非总带宽上限）。
     对旧节点执行 harden 启用限速，但它不会自动替换旧 SNI。
     请留意同一目标可被大量并发回落连接滥用，仍需主机流量监控。
  4. 仅管理本工具创建的节点，不迁移系统已有 /usr/local/etc/xray 配置。
  5. 使用独立 systemd 服务 xray-multi，不接管已有 xray.service。
EOF
}

menu() {
  local choice
  while :; do
    ui_home
    ui_read choice "  › 请选择操作 [01-10 / 00 / Q]: " || break
    case "$choice" in
      1|01|2|02) install_xray ;;
      3|03) add_reality ;;
      4|04) add_ss ;;
      5|05) node_names ;;
      6|06) show_node ;;
      7|07) delete_node ;;
      8|08) status ;;
      9|09) require_installed; systemctl restart "$SERVICE" && info '服务已重启。' ;;
      10) harden_reality ;;
      0|00) uninstall_all ;;
      q|Q|quit|exit) break ;;
      *) warn '无效选项：请输入菜单中的编号。' ;;
    esac
    printf '\n'
    ui_pause || break
  done
}

main() {
  case "${1:-menu}" in
    help|-h|--help) help_text; return ;;
  esac
  check_root
  case "${1:-menu}" in
    menu) menu ;;
    install|update) install_xray ;;
    add-reality) add_reality ;;
    add-ss) add_ss ;;
    list) node_names ;;
    show) show_node "${2:-}" ;;
    delete) delete_node ;;
    status) status ;;
    restart) require_installed; systemctl restart "$SERVICE"; info '服务已重启。' ;;
    harden) harden_reality ;;
    uninstall) uninstall_all ;;
    *) die '未知命令，请执行 bash xray-manager.sh help 查看帮助。' ;;
  esac
}
main "$@"
