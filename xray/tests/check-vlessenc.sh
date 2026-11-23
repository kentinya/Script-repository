#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/xray-manager.sh"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/data" "$work/config"
DATA_DIR="$work/data"
CONF_DIR="$work/config"
DB="$DATA_DIR/nodes.json"
CONFIG="$CONF_DIR/config.json"
TRAFFIC_STATE="$DATA_DIR/traffic.json"
QR_DIR="$work/qrcodes"
STATS_PORT=18785
CONFIG_LOCK_FD=''
BIN="$work/fake-xray"

# 模拟 xray vlessenc 的两套输出；使用形状正确但不是可用密钥的测试值。
cat > "$BIN" <<'SH_XRAY'
#!/usr/bin/env bash
[[ "$1" == vlessenc ]] || exit 1
python3 - <<'PY'
print('Choose one Authentication to use, do not mix them.')
print('Authentication: X25519, not Post-Quantum')
print('"decryption": "mlkem768x25519plus.native.600s.'+'A'*43+'"')
print('"encryption": "mlkem768x25519plus.native.0rtt.'+'B'*43+'"')
print('Authentication: ML-KEM-768, Post-Quantum')
print('"decryption": "mlkem768x25519plus.native.600s.'+'C'*86+'"')
print('"encryption": "mlkem768x25519plus.native.0rtt.'+'D'*1580+'"')
PY
SH_XRAY
chmod +x "$BIN"

printf '{"nodes":[]}\n' > "$DB"
printf '{"nodes":{}}\n' > "$TRAFFIC_STATE"

# 只加载函数定义，不触碰 systemd/root/network。
sed -n '/^release_config_lock() {/,/^}/p' "$SCRIPT" > "$work/functions.sh"
sed -n '/^make_candidate() {/,/^}/p' "$SCRIPT" >> "$work/functions.sh"
sed -n '/^add_vlessenc() {/,/^}/p' "$SCRIPT" >> "$work/functions.sh"
sed -n '/^show_node() {/,/^}/p' "$SCRIPT" >> "$work/functions.sh"
source "$work/functions.sh"

say() { :; }
info() { :; }
warn() { :; }
die() { printf '%s\n' "$*" >&2; exit 1; }
require_installed() { :; }
ask_base() {
  NODE_NAME="$TEST_NAME"
  NODE_PORT="$TEST_PORT"
  NODE_HOST='203.0.113.23'
}
ask() {
  case "$1" in
    auth) printf -v "$1" '%s' "$TEST_AUTH" ;;
    handshake) printf -v "$1" '%s' "$TEST_RTT" ;;
    *) die "Unexpected prompt: $1" ;;
  esac
}
apply_candidate() {
  cp "$DATA_DIR/.nodes.pending.json" "$DB"
  cp "$CONF_DIR/.config.pending.json" "$CONFIG"
  release_config_lock
}
command() {
  if [[ "$1" == -v && "$2" == qrencode ]]; then return 1; fi
  builtin command "$@"
}

TEST_NAME='enc-x25519' TEST_PORT=8443 TEST_AUTH=1 TEST_RTT=1
add_vlessenc > "$work/x25519.txt"
TEST_NAME='enc-mlkem' TEST_PORT=8444 TEST_AUTH=2 TEST_RTT=2
add_vlessenc > "$work/mlkem.txt"

python3 - "$DB" "$CONFIG" "$work/x25519.txt" "$work/mlkem.txt" <<'PY'
import json,pathlib,sys,urllib.parse
db=json.load(open(sys.argv[1],encoding='utf-8'))
conf=json.load(open(sys.argv[2],encoding='utf-8'))
a,b=db['nodes']
assert [a['kind'],b['kind']]==['vlessenc','vlessenc']
assert a['decryption'].endswith('A'*43)
assert a['encryption'].endswith('B'*43)
assert '.1rtt.' in a['encryption']
assert b['decryption'].endswith('C'*86)
assert b['encryption'].endswith('D'*1580)
assert '.0rtt.' in b['encryption']
tags={n['tag']:n for n in conf['inbounds']}
assert {'vlessenc-enc-x25519','vlessenc-enc-mlkem'} <= tags.keys()
for node in (a,b):
    inbound=tags['vlessenc-'+node['name']]
    assert inbound['protocol']=='vless'
    assert inbound['settings']['decryption']==node['decryption']
    assert inbound['settings']['clients']==[{'id':node['uuid'],'flow':'xtls-rprx-vision'}]
    assert inbound['streamSettings']=={'network':'tcp','security':'none'}
for node,filename in ((a,sys.argv[3]),(b,sys.argv[4])):
    output=pathlib.Path(filename).read_text()
    assert node['decryption'] not in output,'server private key leaked'
    assert node['encryption'] in output
    uri=next(line for line in output.splitlines() if line.startswith('vless://'))
    query=urllib.parse.parse_qs(urllib.parse.urlsplit(uri).query)
    assert query['encryption']==[node['encryption']]
    assert query['security']==['none']
    assert query['flow']==['xtls-rprx-vision']
    assert '    tls: false' in output
    assert '    encryption: "'+node['encryption']+'"' in output
    assert '"streamSettings": {' in output
    assert 'Xray 客户端 outbound JSON' in output
assert conf['api']['services']==['StatsService']
print('VLESS Encryption auth pair selection, handshake, server config, client exports and key isolation verified')
PY
