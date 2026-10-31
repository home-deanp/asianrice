#!/usr/bin/env bash
# Power profile picker for the waybar battery: click the battery, choose a profile.
# Needs power-profiles-daemon (powerprofilesctl). Only offers the profiles your machine actually has.

command -v powerprofilesctl >/dev/null 2>&1 || { notify-send -a Power "powerprofilesctl isn't installed"; exit 1; }

BASE_THEME="$HOME/.config/rofi/clipboard.rasi"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
THEME="$CACHE/power-profile.rasi"

# order shown, with an icon and a label for each profile
ORDER=(performance balanced power-saver)
declare -A ICON=( [performance]=$'\xf3\xb0\x93\x85' [balanced]=$'\xf3\xb0\x97\x91' [power-saver]=$'\xf3\xb0\x8c\xaa' )
declare -A LABEL=( [performance]="Performance" [balanced]="Balanced" [power-saver]="Power saver" )

current=$(powerprofilesctl get 2>/dev/null)
mapfile -t have < <(powerprofilesctl list 2>/dev/null | sed -nE 's/^[* ] ([a-z-]+):$/\1/p')

profiles=(); rows=(); selected=0
for p in "${ORDER[@]}"; do
    printf '%s\n' "${have[@]}" | grep -qx "$p" || continue
    [ "$p" = "$current" ] && selected=${#profiles[@]}
    mark=""; [ "$p" = "$current" ] && mark="   ●"
    profiles+=("$p")
    rows+=("${ICON[$p]}  ${LABEL[$p]}$mark")
done
[ ${#profiles[@]} -gt 0 ] || { notify-send -a Power "No power profiles available"; exit 1; }

mkdir -p "$CACHE"
{
    [ -f "$BASE_THEME" ] && cat "$BASE_THEME"
    cat <<'RASI'

window {
    location: northeast;
    anchor: northeast;
    x-offset: -8px;
    y-offset: 4px;
    width: 280px;
}
mainbox {
    children: [listview];
}
listview {
    columns: 1;
    lines: 3;
}
RASI
} > "$THEME"

choice=$(printf '%s\n' "${rows[@]}" | rofi -config "$THEME" -dmenu -p "Power" -format i -selected-row "$selected" -kb-cancel Escape)
[ -z "$choice" ] && exit 0

powerprofilesctl set "${profiles[$choice]}" && notify-send -a Power "Power profile" "${LABEL[${profiles[$choice]}]}"
pkill -RTMIN+10 waybar        # refresh the battery tooltip
