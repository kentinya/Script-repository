#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/xray-manager.sh"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

# 只加载 add_reality，避免 root/systemd 和真实网络依赖。
sed -n '/^add_reality() {/,/^}/p' "$script" >"$work/add_reality.sh"
source "$work/add_reality.sh"

BIN="$work/fake-xray"
cat >"$BIN" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == x25519 ]]; then
  printf 'PrivateKey: %s\nPassword: %s\n' \
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' \
    'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
else
  exit 1
fi
SH
chmod +x "$BIN"

require_installed() { :; }
say() { :; }
info() { :; }
warn() { :; }
die() { echo "$*" >&2; exit 1; }
ask_base() {
  NODE_NAME='auto-checked'
  NODE_PORT=443
  NODE_HOST='198.51.100.5'
}
public_address() { printf '198.51.100.5'; }
ask() {
  case "$1" in
    sni) printf -v "$1" '%s' 'random' ;;
    dest) printf -v "$1" '%s' "$3" ;;
    *) echo "unexpected prompt: $1" >&2; exit 1 ;;
  esac
}
random_reality_sni() { printf 'unreliable.example\nstable.example\n'; }
reality_smoke_test() {
  case "$1:$2" in
    unreliable.example:unreliable.example:443) return 1 ;;
    stable.example:stable.example:443) return 0 ;;
    *) return 1 ;;
  esac
}
valid_host() { :; }
valid_port() { :; }
make_candidate() { selected="${10}|${11}"; }
apply_candidate() { :; }
show_node() { :; }

selected=''
add_reality
[[ "$selected" == 'stable.example|stable.example:443' ]] || {
  printf 'Wrong REALITY SNI selection: %s\n' "$selected" >&2
  exit 1
}
echo 'Random REALITY selector correctly skipped a failed candidate'
