#!/system/bin/sh
# service.sh - Magisk module service script
# 自动检测 rmnet_data* 接口并把 NET_TABLE 的 default route 切换到可用的接口+gateway
# 放在 /data/adb/modules/rmnet-netwatch/service.sh 并 chmod 0755
# 日志: /data/adb/modules/rmnet-netwatch/net-switch.log

MODDIR=${0%/*}

# Load configuration
CONFIG_FILE="$MODDIR/config.conf"
if [ -f "$CONFIG_FILE" ]; then
  . "$CONFIG_FILE"
else
  # Fallback to default values if config file doesn't exist
  LOGDIR="/data/local/tmp"
  LOG="$LOGDIR/net-switch.log"
  PING_TARGET="www.baidu.com"
  SLEEP_INTERVAL=5
  # 默认最大固定可用数据接口(不包含上网接口)
  MAX_RMNET_DATA=3
fi

log() {
  ts=$(date +"%F %T")
  echo "[$ts] $*" >> "$LOG"
}

# Helper: get last rmnet_data* name from ip rules
get_net_table() {
  # 找最后一个包含 "lookup rmnet_data" 的名字
  ip rule show 2>/dev/null | awk '/lookup rmnet_data/ {name=$NF} END{print name}'
}

# Helper: list all rmnet_data interfaces appearing in ip route show
list_rmnet_ifaces() {
  echo "$ROUTES" | awk -v max="$MAX_RMNET_DATA" '
    {
      for (i = 1; i < NF; i++) {
        iface = $(i+1)
        if ($i == "dev" && iface ~ /^rmnet_data[0-9]+$/) {
          num = substr(iface, 11)
          if (num + 0 <= max && !(iface in seen)) {
            seen[iface] = 1
            list[++count] = iface
          }
        }
      }
    }
    END {
      # 倒序输出
      for (i = count; i >= 1; i--) print list[i]
    }'
}

# Helper: get gateway for a given interface
get_gateway_for_iface() {
  iface="$1"
  line=$(echo "$ROUTES" | grep "dev $iface " | head -n1)
  [ -z "$line" ] && return

  # 如果有 "via" 字段，直接用
  gw=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i=="via") print $(i+1)}')
  if [ -n "$gw" ]; then
    echo "$gw"
    return
  fi

  # 提取 network 和 prefix
  net=$(echo "$line" | awk '{print $1}')

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
  ip route show table "$table" 2>/dev/null | awk '
    /^default/ {
      gw="-"; dev="-";
      for(i=1;i<=NF;i++){
        if($i=="via") gw=$(i+1)
        if($i=="dev") dev=$(i+1)
      }
      print dev, gw
      exit
    }'
}

# Ping check: try domain first, then fallback IP. Use -I iface (if supported)
check_iface_connectivity() {
  iface="$1"
  if ping -c 1 -W 1 -I "$iface" "$PING_TARGET" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# Safe: ensure log exists and permissions
mkdir -p "$LOGDIR"
: > "$LOG"
chmod 644 "$LOG"

# Main loop
log "=== rmnet-netwatch started ==="
while true; do

  # 设备休眠, 下一循环
  if [ $(service call power 12 | awk '{print $(NF-1)}') -eq 0 ] 2>/dev/null; then
      sleep "$SLEEP_INTERVAL"
      continue
  fi

  NET_TABLE=$(get_net_table)
  if [ -z "$NET_TABLE" ]; then
    log "没有找到 NET_TABLE，稍后重试"
    sleep "$SLEEP_INTERVAL"
    continue
  fi

  # 缓存 ip route show 的结果
  ROUTES=$(ip route show 2>/dev/null)

  for IFACE in $(list_rmnet_ifaces); do
    [ -z "$IFACE" ] && continue
    GW=$(get_gateway_for_iface "$IFACE")
    if [ -z "$GW" ]; then
      log "接口 $IFACE 未找到网关，跳过"
      continue
    fi

    read cur_dev cur_gw <<EOF
$(get_default_in_table "$NET_TABLE")
EOF
    [ -z "$cur_dev" ] && cur_dev="-"
    [ -z "$cur_gw" ] && cur_gw="-"

    if check_iface_connectivity "$IFACE"; then
      if [ "$cur_dev" != "$IFACE" ] || [ "$cur_gw" != "$GW" ]; then
        if ip route replace default via "$GW" dev "$IFACE" table "$NET_TABLE" 2>/dev/null; then
          log "已将 table $NET_TABLE 的 default 路由替换为 dev=$IFACE via $GW"
        else
          log "尝试替换 table $NET_TABLE default 失败"
        fi
      fi
      break
    fi
  done

  sleep "$SLEEP_INTERVAL"
done
