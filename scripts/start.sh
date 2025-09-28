#!/system/bin/sh
# service.sh - Magisk module service script
# 自动检测 rmnet_data* 接口并把 NET_TABLE 的 default route 切换到可用的接口+gateway
# 放在 /data/adb/modules/rmnet-netwatch/service.sh 并 chmod 0755
# 日志: /data/adb/modules/rmnet-netwatch/net-switch.log

MODDIR=${0%/*}
LOG="$MODDIR/net-switch.log"
PING_TARGET="www.baidu.com"
PING_FALLBACK="8.8.8.8"
SLEEP_INTERVAL=5

log() {
  ts=$(date +"%F %T")
  echo "[$ts] $*" >> "$LOG"
}

# Helper: get last rmnet_data* name from ip rules
get_net_table() {
  # 找最后一个包含 "lookup rmnet_data" 的名字
  # ip rule show 2>/dev/null | awk '/lookup rmnet_data/ {name=$NF} END{print name}'
  NET_TABLE=$(ip rule show | awk '/lookup/ {print $NF}' | tail -n1)
}

# Helper: list all rmnet_data interfaces appearing in ip route show
list_rmnet_ifaces() {
  # extract "dev rmnet_dataX"
  ip route show 2>/dev/null | awk '
    {
      for(i=1;i<=NF;i++) {
        if ($i=="dev" && $(i+1) ~ /^rmnet_data[0-9]+$/) {
          print $(i+1)
        }
      }
    }' | sort -u
}

# Helper: get gateway for a given interface
get_gateway_for_iface() {
  iface="$1"
  line=$(ip route show 2>/dev/null | grep "dev $iface " | head -n1)
  [ -z "$line" ] && return

  # 提取 network 和 prefix
  net=$(echo "$line" | awk '{print $1}')
  # 提取 src
  src=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')

  # 如果有 "via" 字段，直接用
  gw=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i=="via") print $(i+1)}')
  if [ -n "$gw" ]; then
    echo "$gw"
    return
  fi

  # 否则计算 network+1
  ip=$(echo "$net" | cut -d/ -f1)
  prefix=$(echo "$net" | cut -d/ -f2)

  # 把 IPv4 转换为十进制
  IFS=. read -r o1 o2 o3 o4 <<EOF
$ip
EOF
  dec=$(( (o1<<24) + (o2<<16) + (o3<<8) + o4 ))

  # 掩码
  mask=$(( 0xFFFFFFFF << (32-prefix) & 0xFFFFFFFF ))

  # network
  net_dec=$(( dec & mask ))

  # gateway = network+1
  gw_dec=$(( net_dec + 1 ))

  gw_ip="$(( (gw_dec>>24)&255 )).$(( (gw_dec>>16)&255 )).$(( (gw_dec>>8)&255 )).$(( gw_dec&255 ))"
  echo "$gw_ip"
}

# Helper: get default route's dev and gw from a table (NET_TABLE may be name or number)
get_default_in_table() {
  table="$1"
  # returns "dev:g w" (dev and gw), or empty if none
  ip route show table "$table" 2>/dev/null | awk '
    BEGIN {gw="-"; dev="-"}
    /^default/ {
      for(i=1;i<=NF;i++){
        if($i=="via") gw=$(i+1)
        if($i=="dev") dev=$(i+1)
      }
      print dev ":" gw
      exit
    }
    END {
      # if none printed, print nothing
    }'
}

# Ping check: try domain first, then fallback IP. Use -I iface (if supported)
check_iface_connectivity() {
  iface="$1"
  # try domain
  if ping -c 1 -W 1 -I "$iface" "$PING_TARGET" >/dev/null 2>&1; then
    return 0
  fi
  # fallback to IP
  if ping -c 1 -W 1 -I "$iface" "$PING_FALLBACK" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# Safe: ensure log exists and permissions
mkdir -p "$MODDIR"
rm -rf "$LOG"
touch "$LOG"
chmod 644 "$LOG"

# Main loop
log "=== rmnet-netwatch started ==="
while true; do
  NET_TABLE=$(get_net_table)
  if [ -z "$NET_TABLE" ]; then
    log "没有找到 NET_TABLE，稍后重试"
    sleep "$SLEEP_INTERVAL"
    continue
  fi

  # log "NET_TABLE = $NET_TABLE"

  # build map of interface->gw
  # iterate all rmnet_data interfaces found in ip route show
  for IFACE in $(list_rmnet_ifaces); do
    [ -z "$IFACE" ] && continue
    GW=$(get_gateway_for_iface "$IFACE")
    if [ -z "$GW" ]; then
      log "接口 $IFACE 未找到网关，跳过"
      continue
    fi
    # log "检测到接口 $IFACE 网关 $GW"

    # Get current default route in NET_TABLE
    cur=$(get_default_in_table "$NET_TABLE")
    cur_dev=$(printf "%s" "$cur" | awk -F: '{print $1}')
    cur_gw=$(printf "%s" "$cur" | awk -F: '{print $2}')

    # If no default present, mark as "-"
    [ -z "$cur_dev" ] && cur_dev="-"
    [ -z "$cur_gw" ] && cur_gw="-"

    # log "NET_TABLE($NET_TABLE) 当前 default -> dev=$cur_dev gw=$cur_gw"

    # check if iface can reach external network
    if check_iface_connectivity "$IFACE"; then
      # log "接口 $IFACE 能访问外网"
      # if NET_TABLE 的 default 不是当前 iface 或 gw 不匹配，就替换
      if [ "$cur_dev" != "$IFACE" ] || [ "$cur_gw" != "$GW" ]; then
        # Replace default route in the NET_TABLE
        # Use ip route replace (如果表里没有 default 则会添加)
        ip route replace default via "$GW" dev "$IFACE" table "$NET_TABLE" 2>/dev/null
        if [ $? -eq 0 ]; then
          log "已将 table $NET_TABLE 的 default 路由替换为 dev=$IFACE via $GW"
        else
          log "尝试替换 table $NET_TABLE default 失败：ip route replace returned $?"
        fi
      fi
      break
    fi
  done

  sleep "$SLEEP_INTERVAL"
done
