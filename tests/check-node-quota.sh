#!/usr/bin/env bash
set -Eeuo pipefail
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/data" "$work/config"
DATA_DIR="$work/data"
CONF_DIR="$work/config"
DB="$DATA_DIR/nodes.json"
TRAFFIC_STATE="$DATA_DIR/traffic.json"
STATS_PORT=18785
CONFIG_LOCK_FD=''
# 仅引入待测的函数，不执行 main() 或要求 root/systemd。
sed -n '/^release_config_lock() {/,/^}/p' xray-manager.sh > "$work/functions.sh"
sed -n '/^make_candidate() {/,/^}/p' xray-manager.sh >> "$work/functions.sh"
source "$work/functions.sh"

python3 - "$DB" "$TRAFFIC_STATE" <<'PY'
import json,sys
nodes=[
    {'name':'alpha','kind':'ss2022','port':8388,'host':'198.51.100.1',
     'method':'2022-blake3-aes-128-gcm','password':'test','quota_id':'a','quota_bytes':100},
    {'name':'beta','kind':'ss2022','port':8389,'host':'198.51.100.1',
     'method':'2022-blake3-aes-128-gcm','password':'test','quota_id':'b','quota_bytes':0},
    {'name':'relay','kind':'forward','port':9000,'host':'0.0.0.0',
     'target_host':'203.0.113.2','target_port':443,'network':'tcp',
     'quota_id':'c','quota_bytes':100}
]
json.dump({'nodes':nodes},open(sys.argv[1],'w'))
json.dump({'nodes':{
    'a':{'uplink':60,'downlink':40},
    'b':{'uplink':900,'downlink':900},
    'c':{'uplink':20,'downlink':30}
}},open(sys.argv[2],'w'))
PY

make_candidate sync ''
python3 - "$CONF_DIR/.config.pending.json" <<'PY'
import json,sys
c=json.load(open(sys.argv[1]))
tags={n['tag'] for n in c['inbounds']}
assert 'ss2022-alpha' not in tags, tags
assert {'ss2022-beta','forward-relay','xraymulti-stats-in'} <= tags
assert c['policy']['system']['statsInboundUplink'] is True
assert c['policy']['system']['statsInboundDownlink'] is True
assert c['api']['services']==['StatsService']
assert c['routing']['rules'][0]['outboundTag']=='xraymulti-stats'
print('Quota-exceeded node disabled, other nodes remain active')
PY
release_config_lock

make_candidate quota alpha '' 101
python3 - "$CONF_DIR/.config.pending.json" "$DATA_DIR/.nodes.pending.json" <<'PY'
import json,sys
c=json.load(open(sys.argv[1]))
db=json.load(open(sys.argv[2]))
assert 'ss2022-alpha' in {n['tag'] for n in c['inbounds']}
assert next(n for n in db['nodes'] if n['name']=='alpha')['quota_bytes']==101
print('Increasing quota restores the previously disabled node')
PY
release_config_lock
