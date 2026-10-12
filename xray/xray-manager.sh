#!/usr/bin/env bash
# Xray 多节点管理器 v1.5：VLESS + Vision + REALITY / Shadowsocks 2022
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
TRAFFIC_STATE="$DATA_DIR/traffic.json"
STATS_PORT=18785
MANAGER_BIN='/usr/local/sbin/xray-multi-manager'
CONFIG_LOCK_FD=''
TRAFFIC_UNIT='/etc/systemd/system/xray-multi-traffic.service'
TRAFFIC_TIMER='/etc/systemd/system/xray-multi-traffic.timer'

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
        print(sum(n.get('kind') != 'forward' for n in json.load(f).get('nodes', [])))
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
  │  ◆  X R A Y   M U L T I                            v1.5     │
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
  ui_section '端口转发'
  printf '  %s[11]%s  新增 TCP / UDP 转发        %s[12]%s  查看转发规则\n' \
    "$UI_ACCENT" "$UI_RESET" "$UI_ACCENT" "$UI_RESET"
  ui_item '13' '删除转发规则'
  ui_section '单节点流量'
  printf '  %s[14]%s  查看流量统计              %s[15]%s  设置单节点流量额度\n' \
    "$UI_ACCENT" "$UI_RESET" "$UI_ACCENT" "$UI_RESET"
  ui_item '16' '节点流量清零 / 恢复超额节点'
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
  for p in curl unzip openssl python3 qrencode ss flock; do
    command -v "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  ((${#missing[@]} == 0)) && return 0
  info "安装所需依赖：${missing[*]}"
  if command -v apt-get >/dev/null 2>&1; then
    local packages=(curl unzip openssl python3 qrencode iproute2 util-linux)
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl unzip openssl python3 qrencode iproute util-linux
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl unzip openssl python3 qrencode iproute util-linux
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm --needed curl unzip openssl python qrencode iproute2 util-linux
  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install curl unzip openssl python3 qrencode iproute2 util-linux
  else
    die '不支持当前发行版的软件包管理器，请手动安装 curl unzip openssl python3 qrencode iproute2。'
  fi
  for p in curl unzip openssl python3 qrencode ss flock; do
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
  if [[ -f "$CONFIG" ]] && grep -q '"xraymulti-stats"' "$CONFIG"; then
    traffic_sample || warn '更新内核前流量采集失败，可能损失最后一个采样区间的统计。'
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
  if [[ -f "$TRAFFIC_TIMER" ]]; then setup_traffic_monitor; fi
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
  [[ "$1" != "$STATS_PORT" ]] || die "端口 $STATS_PORT 已保留给本机 Xray 统计 API。"
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

# 配置变更从生成候选到服务切换使用同一把锁，防止菜单与定时器冲突。
release_config_lock() {
  if [[ -n "$CONFIG_LOCK_FD" ]]; then
    exec {CONFIG_LOCK_FD}>&-
    CONFIG_LOCK_FD=''
  fi
}
# 生成变更候选数据及 Xray 整体配置，不直接覆盖线上文件。
make_candidate() {
  local action="$1" name="$2" kind="${3:-}" port="${4:-}" host="${5:-}" \
        uuid="${6:-}" priv="${7:-}" pub="${8:-}" sid="${9:-}" \
        sni="${10:-}" dest="${11:-}" method="${12:-}" psk="${13:-}"
  local candidate_db="$DATA_DIR/.nodes.pending.json" candidate_config="$CONF_DIR/.config.pending.json"
  exec {CONFIG_LOCK_FD}>"$DATA_DIR/.config-operation.lock"
  flock -x "$CONFIG_LOCK_FD" || die '无法取得配置修改锁'
  rm -f "$candidate_db" "$candidate_config"
  python3 - "$DB" "$candidate_db" "$candidate_config" "$TRAFFIC_STATE" "$STATS_PORT" \
    "$action" "$name" "$kind" "$port" "$host" "$uuid" "$priv" "$pub" \
    "$sid" "$sni" "$dest" "$method" "$psk" <<'PY'
import json,sys,os
(db_path,new_db,new_conf,traffic_path,stats_port,action,name,kind,port,host,uuid,priv,pub,sid,sni,dest,method,psk)=sys.argv[1:]
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
    elif kind=='forward':
        if method not in ('tcp','udp','tcp,udp'):
            raise ValueError('无效转发协议')
        if not psk.isdigit() or not 1 <= int(psk) <= 65535:
            raise ValueError('无效目标端口')
        node.update(target_host=dest,target_port=int(psk),network=method)
    else: raise ValueError('不支持的协议类型')
    nodes.append(node)
elif action=='delete':
    if not any(n['name']==name for n in nodes): raise ValueError('找不到指定节点')
    db['nodes']=[n for n in nodes if n['name']!=name]
    nodes=db['nodes']
elif action=='harden' or action=='sync':
    pass
elif action=='quota':
    selected=next((n for n in nodes if n['name']==name),None)
    if selected is None: raise ValueError('找不到指定节点')
    limit=int(port)
    if limit<0: raise ValueError('流量上限不能为负数')
    selected['quota_bytes']=limit
else: raise ValueError('无效操作')
import secrets
for n in nodes:
    n.setdefault('quota_id',secrets.token_hex(12))
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
# 流量状态文件独立于节点数据库，采样不引发每分钟重启。
try:
    with open(traffic_path,encoding='utf-8') as f: traffic=json.load(f).get('nodes',{})
except (OSError,ValueError,TypeError):
    traffic={}
if any(n['port']==int(stats_port) for n in nodes):
    raise ValueError('现有节点占用了内部统计端口 '+stats_port+'，请先调整该节点')
inbounds=[{'tag':'xraymulti-stats-in','listen':'127.0.0.1',
           'port':int(stats_port),'protocol':'dokodemo-door',
           'settings':{'address':'127.0.0.1'}}]
for n in nodes:
    used=traffic.get(n['quota_id'],{}).get('uplink',0)+traffic.get(n['quota_id'],{}).get('downlink',0)
    if n.get('quota_bytes',0)>0 and used>=n['quota_bytes']:
        continue
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
    elif n['kind']=='ss2022':
        inbounds.append({
            'tag':'ss2022-'+n['name'], 'listen':'0.0.0.0', 'port':n['port'],
            'protocol':'shadowsocks', 'settings':{
                'method':n['method'],'password':n['password'],'network':'tcp,udp'
            }
        })
    elif n['kind']=='forward':
        inbounds.append({
            'tag':'forward-'+n['name'], 'listen':n['host'], 'port':n['port'],
            'protocol':'tunnel',
            'settings':{
                'allowedNetwork':n['network'],
                'rewriteAddress':n['target_host'],
                'rewritePort':n['target_port'],
                'followRedirect':False
            },
            'sniffing':{'enabled':False}
        })
    else:
        raise ValueError('未知节点类型: '+str(n['kind']))
conf={'log':{'loglevel':'warning'},'inbounds':inbounds,
      'outbounds':[{'protocol':'freedom','tag':'direct'}, {'protocol':'blackhole','tag':'block'}],
      'stats':{},
      'policy':{'system':{'statsInboundUplink':True,'statsInboundDownlink':True}},
      'api':{'tag':'xraymulti-stats','services':['StatsService']}}
forward_tags=['forward-'+n['name'] for n in nodes if n['kind']=='forward']
rules=[{'type':'field','inboundTag':['xraymulti-stats-in'],'outboundTag':'xraymulti-stats'}]
rules.extend({'type':'field','inboundTag':[tag],'outboundTag':'direct'} for tag in forward_tags)
conf['routing']={'rules':rules}
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
  # 服务重启会清空内核计数，先落盘已观察到的流量。
  if [[ -f "$CONFIG" ]] && grep -q '"xraymulti-stats"' "$CONFIG"; then
    traffic_sample || warn '切换配置前无法采集流量；本次重启前未采集的字节可能丢失。'
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
    release_config_lock
    return 1
  fi
  rm -f "$old_db" "$old_config"
  release_config_lock
  return 0
}


# StatsService 采样与累计存档。两次采样间的进程重启可能遗漏部分流量。
traffic_db() {
  python3 - "$DB" "$TRAFFIC_STATE" "$BIN" "$STATS_PORT" "$SERVICE" "$1" "$2" <<'PY_TRAFFIC'
import fcntl,json,os,subprocess,sys,tempfile,time
db_path,path,xray,port,service,action,name=sys.argv[1:]
with open(db_path,encoding='utf-8') as f: nodes=json.load(f).get('nodes',[])
os.makedirs(os.path.dirname(path),exist_ok=True)
def run(argv):
    return subprocess.run(argv,check=True,capture_output=True,text=True,timeout=8).stdout.strip()
def epoch_id():
    pid=int(run(['systemctl','show','-p','MainPID','--value',service]))
    if pid<=0: raise RuntimeError('Xray 未运行')
    with open('/proc/%d/stat'%pid) as f: raw=f.read()
    start=raw[raw.rfind(')')+2:].split()[19]
    with open('/proc/sys/kernel/random/boot_id') as f: boot=f.read().strip()
    return '%s:%d:%s'%(boot,pid,start)
def save(data):
    fd,tmp=tempfile.mkstemp(dir=os.path.dirname(path),prefix='.traffic-')
    try:
        with os.fdopen(fd,'w',encoding='utf-8') as f:
            os.fchmod(f.fileno(),0o600)
            json.dump(data,f,ensure_ascii=False,indent=2)
            f.write('\n')
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp,path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)
with open(path+'.lock','a+') as lock:
    os.chmod(path+'.lock',0o600)
    fcntl.flock(lock,fcntl.LOCK_EX)
    try:
        with open(path,encoding='utf-8') as f: data=json.load(f)
    except FileNotFoundError:
        data={'nodes':{}}
    records=data.setdefault('nodes',{})
    if action=='sample':
        epoch=epoch_id()
        output=run([xray,'api','statsquery','--server=127.0.0.1:'+port,'--pattern=inbound>>>'])
        if epoch!=epoch_id(): raise RuntimeError('采样时 Xray 已重启')
        counters={s['name']:int(s['value']) for s in json.loads(output or '{}').get('stat',[]) if 'name' in s}
        for n in nodes:
            qid=n.get('quota_id')
            if not qid: continue
            tag={'reality':'reality-','ss2022':'ss2022-','forward':'forward-'}.get(n['kind'],'')+n['name']
            rec=records.setdefault(qid,{'uplink':0,'downlink':0,'last_up':0,'last_down':0,'epoch':''})
            for key,last in (('uplink','last_up'),('downlink','last_down')):
                current=counters.get('inbound>>>%s>>>traffic>>>%s'%(tag,key),0)
                previous=int(rec.get(last,0))
                delta=max(0,current-previous) if rec.get('epoch')==epoch and current>=previous else current
                rec[key]=int(rec.get(key,0))+delta
                rec[last]=current
            rec['epoch']=epoch
            rec['sample_at']=int(time.time())
        save(data)
    elif action=='reset':
        node=next((n for n in nodes if n['name']==name),None)
        if node is None: sys.exit('找不到指定节点')
        qid=node.get('quota_id')
        if not qid: sys.exit('节点 ID 尚未初始化')
        rec=records.setdefault(qid,{})
        rec['uplink']=0
        rec['downlink']=0
        save(data)
    elif action=='reached':
        with open('/etc/xray-multi/config.json',encoding='utf-8') as f:
            active={n.get('tag') for n in json.load(f).get('inbounds',[])}
        for n in nodes:
            limit=int(n.get('quota_bytes',0))
            rec=records.get(n.get('quota_id'),{})
            used=int(rec.get('uplink',0))+int(rec.get('downlink',0))
            tag={'reality':'reality-','ss2022':'ss2022-','forward':'forward-'}.get(n['kind'],'')+n['name']
            if limit>0 and used>=limit and tag in active:
                print('  节点 %s 已超额：%d / %d 字节'%(n['name'],used,limit))
                sys.exit(0)
        sys.exit(1)
    elif action=='list':
        gib=1024**3
        print('  %-19s %-10s %10s %10s %17s  %s'%('名称','类型','上传GiB','下载GiB','已用/限额 GiB','状态'))
        for n in nodes:
            rec=records.get(n.get('quota_id'),{})
            up=int(rec.get('uplink',0)); down=int(rec.get('downlink',0))
            limit=int(n.get('quota_bytes',0)); used=up+down
            target='不限' if limit==0 else '%.2f'%(limit/gib)
            state='已停用' if limit>0 and used>=limit else '正常'
            print('  %-19s %-10s %10.2f %10.2f %7.2f / %-8s %s'%(
                n['name'],n['kind'],up/gib,down/gib,used/gib,target,state))
        if not nodes: print('  暂无节点')
    else:
        sys.exit('未知流量操作')
PY_TRAFFIC
}

traffic_sample() {
  [[ -f "$DB" && -f "$CONFIG" && -x "$BIN" ]] || return 0
  grep -q '"xraymulti-stats"' "$CONFIG" || return 0
  traffic_db sample ''
}

setup_traffic_monitor() {
  # 保存自包含脚本供 systemd 定时器调用。
  local source="${BASH_SOURCE[0]}"
  if [[ "$source" != "$MANAGER_BIN" ]]; then
    install -m 700 "$source" "$MANAGER_BIN.new" || die '安装流量监控脚本失败'
    mv -f "$MANAGER_BIN.new" "$MANAGER_BIN"
  fi
  cat >"$TRAFFIC_UNIT" <<'EOF_TRAFFIC_UNIT'
[Unit]
Description=Xray Multi Per-node Quota Check
After=xray-multi.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/xray-multi-manager traffic-check
EOF_TRAFFIC_UNIT
  cat >"$TRAFFIC_TIMER" <<'EOF_TRAFFIC_TIMER'
[Unit]
Description=Xray Multi Quota Timer

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
AccuracySec=10s
Persistent=true
Unit=xray-multi-traffic.service

[Install]
WantedBy=timers.target
EOF_TRAFFIC_TIMER
  chmod 644 "$TRAFFIC_UNIT" "$TRAFFIC_TIMER"
  systemctl daemon-reload
  systemctl enable --now xray-multi-traffic.timer >/dev/null || die '启用流量监控定时器失败'
}

traffic_check() {
  [[ -f "$DB" && -f "$CONFIG" && -x "$BIN" ]] || return 0
  traffic_sample || { warn '统计接口采样失败，本次未更新配额，请检查 Xray 服务。'; return 1; }
  if traffic_db reached ''; then
    make_candidate sync ''
    apply_candidate || { warn '无法自动停用超额节点，请检查日志！'; return 1; }
    info '超额节点已停用；重启 Xray 可能短暂中断其他节点的现有连接。'
  fi
}

traffic_list() {
  require_installed
  traffic_sample || warn '无法采集即时流量，显示最后一次保存的结果。'
  say '每个节点上传 + 下载累计流量'
  traffic_db list ''
}

traffic_set() {
  require_installed
  local name="$1" gib="$2" limit
  [[ -n "$name" ]] || { node_names; ask name '节点/转发名称' ''; }
  valid_name "$name" || die '节点名称不合法'
  [[ -n "$gib" ]] || ask gib '上限 GiB（0 不限制，上行+下行合计）' '10'
  limit="$(python3 - "$gib" <<'PY_QUOTA_PARSE'
from decimal import Decimal,InvalidOperation
import sys
try:
    g=Decimal(sys.argv[1])
    if not g.is_finite() or not 0<=g<=1000000: raise ValueError()
    b=int(g*1024**3)
    if g>0 and b==0: raise ValueError()
    print(b)
except (InvalidOperation,ValueError):
    sys.exit('流量上限必须是 0-1000000 之间的 GiB 数值')
PY_QUOTA_PARSE
)" || die '无效的流量上限'
  traffic_sample || warn '更改额度前未能采集即时流量。'
  make_candidate quota "$name" '' "$limit"
  apply_candidate || die '修改流量额度失败'
  setup_traffic_monitor
  info "节点 $name 流量额度已更新。0 表示不限。"
  traffic_list
}

traffic_reset() {
  require_installed
  local name="$1"
  [[ -n "$name" ]] || { traffic_list; ask name '清零哪个节点/转发规则' ''; }
  valid_name "$name" || die '节点名称不合法'
  traffic_sample || warn '清零前未能采集即时流量。'
  traffic_db reset "$name" || die '重置流量失败'
  make_candidate sync ''
  apply_candidate || die '累计流量已重置，但重新启用节点失败'
  info "节点 $name 的累计流量已清零。"
  traffic_list
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
        builtin=['dl.google.com','www.apple.com','www.samsung.com',
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
        ranked=[]
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
                ranked.append((rank,host,ip,kind,data))
            except (OSError,ValueError) as e:
                log('%s 已跳过：%s' % (host,str(e)[:95]))
        if not ranked:
            raise ValueError('无法找到非 Cloudflare 且支持 TLS 1.3/h2 的目标；请换目标池或手动指定')
        random.SystemRandom().shuffle(ranked)
        ranked.sort(key=lambda candidate:candidate[0],reverse=True)
        shortlisted=ranked[:6]
        log('TLS 初筛 %d 个目标，将对 %d 个候选进行真实 REALITY 连接测试。' % (
            checked,len(shortlisted)))
        if shortlisted[0][0]<2:
            log('警告：没有找到可验证的同国/同洲目标；建议在候选池中补充当地网站。')
        for rank,host,ip,kind,data in shortlisted:
            log('REALITY 待测：%s (%s)，IP %s、国家/地区 %s、ASN %s。' % (
                host,kind,ip,(data or {}).get('country','未知'),
                (data or {}).get('asn','未知')))
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

# 普通 TLS 1.3/h2 检测不足以保证 REALITY 握手兼容（例如目标证书记录过大）。
# 临时 Xray 仅监听 127.0.0.1，经 SOCKS5 和 REALITY 完成两次数据往返，不修改线上服务。
reality_smoke_test() {
  python3 - "$BIN" "$1" "$2" <<'PY_REALITY_SMOKE'
import json,os,re,socket,subprocess,sys,tempfile,threading,time,uuid

def readn(sock,n):
    data=b''
    while len(data)<n:
        piece=sock.recv(n-len(data))
        if not piece: raise OSError('SOCKS 连接提前关闭')
        data+=piece
    return data

def freeport():
    with socket.socket() as s:
        s.bind(('127.0.0.1',0))
        return s.getsockname()[1]

def check(binary,sni,dest):
    output=subprocess.run([binary,'x25519'],capture_output=True,text=True,check=True,timeout=8).stdout
    pairs={re.sub('[^a-z]','',k.lower()):v.strip().split()[0] for line in output.splitlines()
           if ':' in line for k,v in [line.split(':',1)] if v.strip()}
    priv=pairs.get('privatekey','')
    pub=next((v for k,v in pairs.items() if k.startswith(('publickey','password'))),'')
    if not priv or not pub: raise ValueError('无法生成临时 REALITY 密钥')
    rp,sp=freeport(),freeport()
    with socket.socket() as echo:
        echo.bind(('127.0.0.1',0)); echo.listen(2); ep=echo.getsockname()[1]
        done=threading.Event()
        def serve():
            echo.settimeout(.2)
            while not done.is_set():
                try: conn,_=echo.accept()
                except socket.timeout: continue
                except OSError: break
                with conn:
                    conn.settimeout(6)
                    try:
                        data=conn.recv(100)
                        if data: conn.sendall(data)
                    except OSError: pass
        threading.Thread(target=serve,daemon=True).start()
        uid=str(uuid.uuid4()); sid=os.urandom(8).hex()
        cfg={'log':{'loglevel':'warning'},'inbounds':[
            {'tag':'socks','listen':'127.0.0.1','port':sp,'protocol':'socks','settings':{'auth':'noauth'}},
            {'tag':'reality','listen':'127.0.0.1','port':rp,'protocol':'vless',
             'settings':{'clients':[{'id':uid,'flow':'xtls-rprx-vision'}],'decryption':'none'},
             'streamSettings':{'network':'tcp','security':'reality','realitySettings':{
                 'target':dest,'serverNames':[sni],'privateKey':priv,'shortIds':[sid]}}}],
             'outbounds':[
            {'tag':'client','protocol':'vless',
             'settings':{'vnext':[{'address':'127.0.0.1','port':rp,
                                   'users':[{'id':uid,'encryption':'none','flow':'xtls-rprx-vision'}]}]},
             'streamSettings':{'network':'tcp','security':'reality','realitySettings':{
                 'serverName':sni,'fingerprint':'chrome','publicKey':pub,'shortId':sid}}},
            {'tag':'direct','protocol':'freedom'}],
            'routing':{'rules':[{'type':'field','inboundTag':['socks'],'outboundTag':'client'},
                                {'type':'field','inboundTag':['reality'],'outboundTag':'direct'}]}}
        try:
            with tempfile.TemporaryDirectory(prefix='xray-reality-check-') as tmp:
                path=os.path.join(tmp,'config.json')
                with open(path,'w') as f: json.dump(cfg,f)
                os.chmod(path,0o600)
                with open(os.path.join(tmp,'xray.log'),'wb') as log:
                    proc=subprocess.Popen([binary,'run','-format','json','-config',path],
                                          stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT)
                    try:
                        for _ in range(40):
                            if proc.poll() is not None: raise ValueError('临时 Xray 启动失败')
                            try:
                                with socket.create_connection(('127.0.0.1',sp),timeout=.3): break
                            except OSError: time.sleep(.1)
                        else: raise ValueError('临时 Xray 启动超时')
                        for _ in range(2):
                            with socket.create_connection(('127.0.0.1',sp),timeout=5) as sock:
                                sock.settimeout(6); sock.sendall(b'\x05\x01\x00')
                                if readn(sock,2)!=b'\x05\x00': raise ValueError('SOCKS 方法失败')
                                sock.sendall(b'\x05\x01\x00\x01\x7f\x00\x00\x01'+ep.to_bytes(2,'big'))
                                hdr=readn(sock,4)
                                if hdr[:2]!=b'\x05\x00': raise ValueError('REALITY 链路失败 (SOCKS %d)'%hdr[1])
                                if hdr[3]==1: readn(sock,6)
                                elif hdr[3]==3: readn(sock,readn(sock,1)[0]+2)
                                elif hdr[3]==4: readn(sock,18)
                                else: raise ValueError('SOCKS 地址类型不合法')
                                data=os.urandom(16); sock.sendall(data)
                                if readn(sock,len(data))!=data: raise ValueError('REALITY 数据往返不一致')
                    finally:
                        if proc.poll() is None: proc.terminate()
                        try: proc.wait(timeout=2)
                        except subprocess.TimeoutExpired: proc.kill(); proc.wait(timeout=2)
        finally: done.set()

try: check(*sys.argv[1:4])
except (OSError,ValueError,subprocess.SubprocessError) as exc:
    print('[REALITY 自检] '+str(exc)[:170],file=sys.stderr)
    sys.exit(1)
PY_REALITY_SMOKE
}

add_reality() {
  require_installed
  say '新增 VLESS + Vision + REALITY 节点'
  ask_base 443
  local sni dest raw priv pub uuid sid dest_host dest_port server_ip was_random=0 candidates candidate
  server_ip="$(public_address)"
  ask sni 'REALITY 伪装目标 SNI（输入 random 随机选择，或手动填写域名）' 'random'
  case "${sni,,}" in
    random|r)
      info '随机初筛 TLS 1.3 + HTTP/2 (h2) 和 Cloudflare 目标，然后实测 REALITY 连接……'
      was_random=1
      candidates="$(random_reality_sni "$server_ip")" || die '自动选择 REALITY SNI 失败。'
      sni=''
      while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue
        info "尝试 REALITY 全链路连接：$candidate"
        if reality_smoke_test "$candidate" "$candidate:443"; then
          sni="$candidate"
          break
        fi
        warn "目标 $candidate 在 REALITY 实测失败，尝试下一个候选。"
      done <<<"$candidates"
      [[ -n "$sni" ]] || die '候选站点均未通过 REALITY 实测，未修改任何节点。请调整 SNI 候选池或排查网络。'
      info "通过 REALITY 实测的 SNI：$sni"
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
    info '正在用临时本机 Xray 验证所选 SNI 和目标地址的真实 REALITY 握手……'
    reality_smoke_test "$sni" "$dest"       || die '该目标虽然可能支持 HTTPS，但 REALITY 实测失败；未修改原节点。'
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


# 转发入口由 Xray tunnel 实现，独立规则复用现有数据库及配置回滚。
forward_exists() {
  [[ -f "$DB" ]] || return 1
  python3 - "$DB" "$1" <<'PY_FORWARD_EXISTS'
import json,sys
with open(sys.argv[1],encoding='utf-8') as f:
    nodes=json.load(f).get('nodes',[])
sys.exit(0 if any(n.get('name')==sys.argv[2] and n.get('kind')=='forward' for n in nodes) else 1)
PY_FORWARD_EXISTS
}

forward_list() {
  say '当前端口转发规则'
  [[ -f "$DB" ]] || { info '暂无转发规则。'; return 0; }
  python3 - "$DB" <<'PY_FORWARD_LIST'
import json,sys,ipaddress
with open(sys.argv[1],encoding='utf-8') as f:
    rules=[n for n in json.load(f).get('nodes',[]) if n.get('kind')=='forward']
if not rules:
    print('  暂无转发规则。')
else:
    print('  %-20s %-23s %-31s %s' % ('名称','A 监听','B 目标','协议'))
    for n in rules:
        dest=n['target_host']
        try:
            if ipaddress.ip_address(dest).version==6: dest='['+dest+']'
        except ValueError:
            pass
        print('  %-20s %-23s %-31s %s' % (
            n['name'],f"{n['host']}:{n['port']}",
            f"{dest}:{n['target_port']}",n['network']))
PY_FORWARD_LIST
}

add_forward() {
  require_installed
  say '新增 A → B 端口转发'
  local name listen port target target_port choice network
  ask name '规则名称（字母、数字、下划线、短横线）' ''
  valid_name "$name" || die '规则名称不合法。'
  ask listen 'A 服务器监听 IPv4（0.0.0.0 表示所有网卡）' '0.0.0.0'
  python3 - "$listen" <<'PY_FORWARD_LISTEN' || die '监听 IP 必须是有效 IPv4 地址。'
import ipaddress,sys
ipaddress.IPv4Address(sys.argv[1])
PY_FORWARD_LISTEN
  ask port 'A 服务器监听端口' '10086'
  valid_port "$port" || die '监听端口必须是 1-65535。'
  port="$((10#$port))"
  port_available "$port" "$name"
  ask target 'B 服务器目标 IP 或域名' ''
  valid_host "$target" || die '目标 IP 或域名不合法。'
  case "$target" in
    0.0.0.0|::|255.255.255.255) die '不允许使用无效目标地址。' ;;
  esac
  ask target_port 'B 服务器目标端口' "$port"
  valid_port "$target_port" || die '目标端口必须是 1-65535。'
  target_port="$((10#$target_port))"
  if [[ "$target_port" == "$port" ]]; then
    case "$target" in
      "$listen") die 'A/B 地址与端口完全相同，会造成转发循环。' ;;
      127.0.0.1|localhost)
        [[ "$listen" != '0.0.0.0' && "$listen" != '127.0.0.1' ]] \
          || die '同端口转发到本机回环地址可能产生转发循环。' ;;
    esac
  fi
  printf '  [1] TCP（默认）  [2] UDP  [3] TCP + UDP\n'
  ask choice '选择转发协议' '1'
  case "$choice" in
    1|tcp|TCP) network='tcp' ;;
    2|udp|UDP) network='udp' ;;
    3|both|BOTH|tcp,udp) network='tcp,udp' ;;
    *) die '无效转发协议。' ;;
  esac
  if [[ "$listen" == 0.0.0.0 ]]; then
    warn '转发入口将对所有 IPv4 网卡开放。请在云防火墙限制来源 IP，防止被滥用刷流量。'
  fi
  make_candidate add "$name" forward "$port" "$listen" '' '' '' '' '' "$target" "$network" "$target_port"
  apply_candidate || die '转发创建失败，旧配置已恢复。'
  info "转发已启用：$listen:$port → $target:$target_port [$network]"
  warn '请确保 A 的防火墙 / 云安全组放行监听端口，B 允许来自 A 的连接。'
}

delete_forward() {
  require_installed
  forward_list
  local name confirm
  ask name '要删除的转发规则名称' ''
  valid_name "$name" || die '规则名称不合法。'
  forward_exists "$name" || die '找不到该转发规则；代理节点请使用节点删除菜单。'
  ask confirm "确定删除转发规则 [$name] 吗？请输入 YES" ''
  [[ "$confirm" == YES ]] || { info '已取消。'; return; }
  make_candidate delete "$name"
  apply_candidate || die '删除转发失败，旧配置已恢复。'
  info "转发规则 $name 已删除。"
}

node_names() {
  [[ -f "$DB" ]] || { warn '暂无节点。'; return 0; }
  python3 - "$DB" <<'PY'
import json,sys
with open(sys.argv[1]) as f: a=[n for n in json.load(f)['nodes'] if n.get('kind')!='forward']
if not a: print('暂无代理节点。')
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
if n.get('kind')=='forward': sys.exit('该名称属于转发规则，请使用 forward-list 查看')
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
  if forward_exists "$name"; then die '该名称属于转发规则，请从端口转发菜单删除。'; fi
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

restart_managed_service() {
  require_installed
  traffic_sample || warn '重启前无法获取最新流量数据。'
  systemctl restart "$SERVICE" && info '服务已重启。'
}

status() {
  if [[ -x "$BIN" ]]; then "$BIN" version | head -n 1; else warn '尚未安装 Xray。'; fi
  if [[ -f "$UNIT" ]]; then
    systemctl --no-pager --full status "$SERVICE" || true
  else
    warn '服务尚未安装。'
  fi
  node_names
  forward_list
}

uninstall_all() {
  local confirm
  say '卸载 Xray Multi'
  warn '此操作将删除本脚本管理的所有节点、端口转发规则、链接和二维码（不可恢复）。'
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
  systemctl disable --now xray-multi-traffic.timer >/dev/null 2>&1 || true
  rm -f "$TRAFFIC_UNIT" "$TRAFFIC_TIMER" "$MANAGER_BIN" "$MANAGER_BIN.new"
  systemctl daemon-reload
  rm -rf -- "$CONF_DIR" "$DATA_DIR"
  info '已删除本工具的服务和所有管理数据。'
}

help_text() {
  cat <<'EOF'
Xray 多配置管理器 v1.5（需要 root，Linux + systemd）

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
  forward-add     新增 A IP:端口 → B IP:端口 转发（TCP / UDP）
  forward-list    查看全部转发规则
  forward-delete  删除指定转发规则
  quota-list      查看每个节点累计流量、配额和停用状态
  quota-set 名称 GiB  设置独立流量额度（0 表示不限，支持小数）
  quota-reset 名称    清零累计流量并重新启用超额节点
  traffic-check   立即采样并执行自动停用（systemd 定时器调用）
  uninstall       卸载本工具管理的配置和 Xray
  help            显示帮助

路径：
  /etc/xray-multi/config.json          Xray 合并配置
  /var/lib/xray-multi/nodes.json       包含密钥的节点数据库（root 专用）
  /var/lib/xray-multi/qrcodes/         二维码（root 专用）
  /var/lib/xray-multi/traffic.json     累计流量（root 专用）
  /etc/systemd/system/xray-multi.service

提示：
  1. 防火墙和云平台安全组请自行放行节点端口；SS2022 同时需要 TCP/UDP。
  2. REALITY 默认根据机房公网 IP 的 ASN / 国家 / 大洲优选 TLS1.3+h2 目标。
     默认排除 Cloudflare IP/ASN，对人工目标也做 TLS + Cloudflare 检测。
     可选：编辑 /etc/xray-multi/reality-targets.txt，每行一个域名；也可写 DE www.example.de。
     可选：XRAY_GEO_COUNTRY=DE sudo -E bash xray-manager.sh add-reality 强制机房国家代码。
     新建 REALITY 节点先做 TLS 初筛，再使用临时本机 Xray 完成两次 REALITY 数据往返。
     无法通过实测的随机候选会被跳过；此检测只监听 127.0.0.1，不影响线上服务。
     通过检测不保证公网入站、客户端兼容或未来目标 DNS 变化。
     IP 地理定位不保证精确；目标 CDN 解析和路由可能随时间变化。
  3. 新建节点默认对 REALITY 认证失败的回落连接设置随机化限速（非总带宽上限）。
     对旧节点执行 harden 启用限速，但它不会自动替换旧 SNI。
     请留意同一目标可被大量并发回落连接滥用，仍需主机流量监控。
  4. 仅管理本工具创建的节点，不迁移系统已有 /usr/local/etc/xray 配置。
  5. 使用独立 systemd 服务 xray-multi，不接管已有 xray.service。
  6. 单节点流量限制基于 Xray StatsService 入站统计，上下行字节相加；可用于代理节点及转发规则。
     首次设置额度后安装每分钟运行的 systemd 定时器（xray-multi-traffic.timer）。
     超额时从 Xray 的有效配置中停用对应节点，重置用量或调高额度可恢复。
     这是分钟级配额，并非实时硬限速；峰值流量和非正常重启可能造成超额/漏计。
     启停限额会重启 Xray，其他节点继续存在，但当前连接可能短暂中断。
     仅统计 Xray 入站流量，不包含协议栈及运营商计费额外开销。
  7. 端口转发规则和节点统一保存 /var/lib/xray-multi/nodes.json，支持失败回滚。
     转发不是加密隧道；公网监听应在防火墙限制来源 IP，防止刷流量。
     B 服务器通常看到 A 的出口 IP，而不是原始客户端 IP。
EOF
}

menu() {
  local choice
  while :; do
    ui_home
    ui_read choice "  › 请选择操作 [01-16 / 00 / Q]: " || break
    case "$choice" in
      1|01|2|02) install_xray ;;
      3|03) add_reality ;;
      4|04) add_ss ;;
      5|05) node_names ;;
      6|06) show_node ;;
      7|07) delete_node ;;
      8|08) status ;;
      9|09) restart_managed_service ;;
      10) harden_reality ;;
      11) add_forward ;;
      12) forward_list ;;
      13) delete_forward ;;
      14) traffic_list ;;
      15) traffic_set '' '' ;;
      16) traffic_reset '' ;;
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
    restart) restart_managed_service ;;
    harden) harden_reality ;;
    forward-add) add_forward ;;
    forward-list) forward_list ;;
    forward-delete) delete_forward ;;
    quota-list|traffic-list) traffic_list ;;
    quota-set) traffic_set "${2:-}" "${3:-}" ;;
    quota-reset) traffic_reset "${2:-}" ;;
    traffic-check) traffic_check ;;
    uninstall) uninstall_all ;;
    *) die '未知命令，请执行 bash xray-manager.sh help 查看帮助。' ;;
  esac
}
main "$@"
