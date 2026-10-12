#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/xray-manager.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/config"
DB="$work/nodes.json"
CONF_DIR="$work/config"
GOST_CONFIG="$CONF_DIR/gost-forward.json"
GOST_SERVICE='xray-multi-forward.service'
GOST_UNIT="$work/gost.service"
RUN_USER='root'
GOST_BIN="$work/gost"

cat >"$GOST_BIN" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$GOST_BIN"

cat >"$DB" <<'JSON'
{
  "nodes": [
    {"name":"tcp-one","kind":"forward","port":10001,"host":"0.0.0.0","target_host":"203.0.113.10","target_port":443,"network":"tcp"},
    {"name":"udp-one","kind":"forward","port":10002,"host":"127.0.0.1","target_host":"example.com","target_port":53,"network":"udp"},
    {"name":"both","kind":"forward","port":10003,"host":"0.0.0.0","target_host":"2001:db8::10","target_port":8443,"network":"tcp,udp"}
  ]
}
JSON

sed -n '/^sync_gost_forwarding() {/,/^}/p' "$SCRIPT" > "$work/functions.sh"
source "$work/functions.sh"

install_gost() { :; }
write_gost_unit() { :; }
systemctl() {
  if [[ "${1:-}" == is-active ]]; then return 0; fi
  return 0
}

sync_gost_forwarding

python3 - "$GOST_CONFIG" <<'PY'
import json,sys
c=json.load(open(sys.argv[1]))
services={s['name']:s for s in c['services']}
assert set(services)=={
    'forward-tcp-one-tcp',
    'forward-udp-one-udp',
    'forward-both-tcp',
    'forward-both-udp',
}, services.keys()
assert services['forward-tcp-one-tcp']['handler']['type']=='tcp'
assert services['forward-udp-one-udp']['listener']['type']=='udp'
assert services['forward-tcp-one-tcp']['addr']=='0.0.0.0:10001'
assert services['forward-tcp-one-tcp']['forwarder']['nodes'][0]['addr']=='203.0.113.10:443'
assert services['forward-udp-one-udp']['forwarder']['nodes'][0]['addr']=='example.com:53'
assert services['forward-both-tcp']['forwarder']['nodes'][0]['addr']=='[2001:db8::10]:8443'
print('GOST TCP/UDP forwarding config generated correctly')
PY
