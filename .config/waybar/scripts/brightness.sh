#!/usr/bin/env bash
# Usage: brightness.sh up | down
# Steps wl-gammarelay-rs brightness by 5%, clamped between MIN and MAX.

export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

STEP=0.05
MIN=0.05   # lowest allowed brightness (5%)
MAX=1.0    # highest allowed brightness (100%)

cur=$(busctl --user get-property rs.wl-gammarelay / rs.wl.gammarelay Brightness | awk '{print $2}')
[[ -z $cur ]] && exit 1

case "$1" in
  up)   delta=$STEP ;;
  down) delta=-$STEP ;;
  *)    echo "usage: $0 up|down" >&2; exit 1 ;;
esac

new=$(awk -v c="$cur" -v d="$delta" -v lo="$MIN" -v hi="$MAX" \
  'BEGIN { n = c + d; if (n < lo) n = lo; if (n > hi) n = hi; printf "%.2f", n }')

busctl --user set-property rs.wl-gammarelay / rs.wl.gammarelay Brightness d "$new"
pkill -RTMIN+9 waybar
