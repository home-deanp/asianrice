#!/usr/bin/env bash
# Usage: hw.sh cpu | gpu
# Prints "<icon> 12%  45°C" for Waybar custom modules.
# Icons are written as raw UTF-8 bytes so they survive copy/paste.

ICON_CPU=$'CPU'   # U+F2DB microchip
ICON_GPU=$'GPU'   # U+F08AE display

hwmon_temp() {
  # $1 = space-separated list of hwmon driver names to look for
  local h name want
  for h in /sys/class/hwmon/hwmon*; do
    name=$(<"$h/name")
    for want in $1; do
      if [[ $name == "$want" && -r "$h/temp1_input" ]]; then
        echo $(( $(<"$h/temp1_input") / 1000 ))
        return
      fi
    done
  done
}

cpu() {
  local u n s i io irq sirq st t1 i1 t2 i2 usage temp
  read -r _ u n s i io irq sirq st _ < /proc/stat
  t1=$((u + n + s + i + io + irq + sirq + st)); i1=$((i + io))
  sleep 0.4
  read -r _ u n s i io irq sirq st _ < /proc/stat
  t2=$((u + n + s + i + io + irq + sirq + st)); i2=$((i + io))
  usage=$(( 100 * ( (t2 - t1) - (i2 - i1) ) / (t2 - t1) ))
  temp=$(hwmon_temp "k10temp coretemp zenpower")
  echo "${ICON_CPU} ${usage}%  ${temp:-?}°C"
}

gpu() {
  local use temp d
  if command -v nvidia-smi >/dev/null 2>&1; then
    IFS=', ' read -r use temp < <(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits)
    echo "${ICON_GPU} ${use}%  ${temp}°C"
    return
  fi
  for d in /sys/class/drm/card*/device; do
    if [[ -r "$d/gpu_busy_percent" ]]; then
      use=$(<"$d/gpu_busy_percent")
      temp=$(cat "$d"/hwmon/hwmon*/temp1_input 2>/dev/null | head -n1)
      echo "${ICON_GPU} ${use}%  $(( ${temp:-0} / 1000 ))°C"
      return
    fi
  done
  echo "${ICON_GPU} n/a"
}

case "$1" in
  cpu) cpu ;;
  gpu) gpu ;;
  *) echo "usage: $0 cpu|gpu" >&2; exit 1 ;;
esac
