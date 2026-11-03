#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$repo_root/xray/xray-manager.sh"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

# 单独加载 show_node，不启动 systemd 或访问网络。
sed -n '/^show_node() {/,/^}/p' "$script" > "$work/show.sh"
source "$work/show.sh"

DB="$work/nodes.json"
QR_DIR="$work/qrcodes"
say() { :; }
warn() { :; }
info() { :; }
die() { printf '%s\n' "$*" >&2; exit 1; }
# 不依赖 CI runner 是否安装了 qrencode。
command() {
    if [[ "$1" == "-v" && "$2" == "qrencode" ]]; then return 1; fi
    builtin command "$@"
}
python3 - "$DB" <<'PY'
import json,sys
nodes=[
    {
        "name":"reality-test","kind":"reality","port":443,"host":"203.0.113.7",
        "uuid":"a12cfd86-6133-4101-9b3e-3d6d38427701",
        "public_key":"TEST_Public_Key_01234567890123456789012345678",
        "private_key":"PRIVATE_KEY_MUST_NOT_LEAK",
        "short_id":"0011223344556677","sni":"www.example.org",
    },
    {
        "name":"ss-test","kind":"ss2022","port":8388,"host":"203.0.113.8",
        "method":"2022-blake3-aes-128-gcm","password":"examplePassword",
    }
]
with open(sys.argv[1],"w",encoding="utf-8") as f:
    json.dump({"nodes":nodes},f)
PY

show_node reality-test > "$work/reality.txt"
show_node ss-test > "$work/ss.txt"

python3 - "$work/reality.txt" "$work/ss.txt" <<'PY'
import pathlib,sys,urllib.parse
reality=pathlib.Path(sys.argv[1]).read_text()
ss=pathlib.Path(sys.argv[2]).read_text()
lines=reality.splitlines()
links=[line for line in lines if line.startswith("vless://")]
assert len(links)==2,links
main,legacy=links
uri=urllib.parse.urlsplit(main)
queries=urllib.parse.parse_qs(uri.query)
assert queries["support-x25519mlkem768"]==["true"],queries
for field in ["pbk","sid","fp","sni","flow","security"]:
    assert field in queries,field
assert "support-x25519mlkem768" not in legacy
assert "      support-x25519mlkem768: true" in reality
assert '      short-id: "0011223344556677"' in reality
assert '    client-fingerprint: chrome' in reality
assert '    servername: "www.example.org"' in reality
loon=next((line for line in lines if line.startswith("reality-test = VLESS,")),None)
assert loon is not None
for fragment in ["transport=tcp","flow=xtls-rprx-vision","public-key=","short-id=0011223344556677","over-tls=true","sni=www.example.org","tls-profile=chrome"]:
    assert fragment in loon,fragment
assert "PRIVATE_KEY_MUST_NOT_LEAK" not in reality
assert "ss://" in ss
assert "support-x25519mlkem768" not in ss
assert "Mihomo YAML" not in ss
assert "Loon [Proxy]" not in ss
print("REALITY Mihomo/Loon exports, legacy URI and Shadowsocks isolation verified")
PY
