#!/system/bin/sh

MODDIR=${0%/*}

CONFIG_FILE="$MODDIR/config.conf"
CONFIG_MTIME=""

load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
  else
    LOGDIR="/data/local/tmp"
    LOG="$LOGDIR/net-switch.log"
    PING_TARGET="www.baidu.com"
    ENT_NAME=rmnet_data
    SLEEP_INTERVAL=5
    MAX_RMNET_DATA=3
    MIN_RMNET_DATA=0
    CONFIG_MTIME=""
  fi
}

check_config_reload() {
  if [ -f "$CONFIG_FILE" ]; then
    current_mtime=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || stat -f %m "$CONFIG_FILE" 2>/dev/null)
    if [ "$current_mtime" != "$CONFIG_MTIME" ]; then
      CONFIG_MTIME=$current_mtime
      log "检测到配置文件更新，重新加载配置"
      load_config
    fi
  fi
}

load_config

log() {
  ts=$(date +"%F %T")
  echo "[$ts] $*" >> "$LOG"
}

get_net_table() {
  t_name=$(ip rule show 2>/dev/null | awk '/lookup / {name=$NF} END{print name}')
  [ -n "$t_name" ] && echo "$t_name" | grep -q "^$ENT_NAME" && echo "$t_name"
}

list_rmnet_ifaces() {
  echo "$ROUTES" | awk -v max="$MAX_RMNET_DATA" -v min="$MIN_RMNET_DATA" -v ent_name="$ENT_NAME" '
    {
      for (i = 1; i < NF; i++) {
        iface = $(i+1)
        if ($i == "dev" && iface ~ ("^" ent_name "[0-9]+$")) {
          num = substr(iface, length(ent_name) + 1)
          if (num + 0 >= min && num + 0 <= max && !(iface in seen)) {
            seen[iface] = 1
            list[++count] = iface
          }
        }
      }
    }
    END {
      for (i = count; i >= 1; i--) print list[i]
    }'
}

get_gateway_for_iface() {
  iface="$1"
  line=$(echo "$ROUTES" | grep "dev $iface " | head -n1)
  [ -z "$line" ] && return

  gw=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i=="via") print $(i+1)}')
  if [ -n "$gw" ]; then
    echo "$gw"
    return
  fi

  net=$(echo "$line" | awk '{print $1}')

  ip=$(echo "$net" | cut -d/ -f1)
  prefix=$(echo "$net" | cut -d/ -f2)

  IFS=. read -r o1 o2 o3 o4 <<EOF
$ip
EOF
  dec=$(( (o1<<24) + (o2<<16) + (o3<<8) + o4 ))

  mask=$(( 0xFFFFFFFF << (32-prefix) & 0xFFFFFFFF ))

  net_dec=$(( dec & mask ))

  gw_dec=$(( net_dec + 1 ))
  gw_ip="$(( (gw_dec>>24)&255 )).$(( (gw_dec>>16)&255 )).$(( (gw_dec>>8)&255 )).$(( gw_dec&255 ))"
  echo "$gw_ip"
}

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

check_iface_connectivity() {
  iface="$1"
  if ping -c 1 -W 1 -I "$iface" "$PING_TARGET" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

mkdir -p "$LOGDIR"
: > "$LOG"
chmod 644 "$LOG"

log "=== rmnet-netwatch started ==="
while true; do

  if [ $(service call power 12 | awk '{print $(NF-1)}') -eq 0 ] 2>/dev/null; then
      sleep "$SLEEP_INTERVAL"
      continue
  fi

  check_config_reload

  NET_TABLE=$(get_net_table)
  if [ -z "$NET_TABLE" ]; then
    log "没有找到 NET_TABLE，稍后重试"
    sleep "$SLEEP_INTERVAL"
    continue
  fi

  ROUTES=$(ip route show 2>/dev/null)

  for IFACE in $(list_rmnet_ifaces); do
    [ -z "$IFACE" ] && continue
    [ "$IFACE" = "$NET_TABLE" ] && continue
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