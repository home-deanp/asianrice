#!/usr/bin/env bash
# Brightness for waybar and the brightness keys, on desktop AND laptop:
#   laptop (has a screen backlight)  -> brightnessctl, the real panel brightness
#   desktop (no backlight)           -> wl-gammarelay, the software dimming you already use
#
#   brightness.sh get     print the current brightness as a number, e.g. 70   (waybar module)
#   brightness.sh up      raise brightness 5%
#   brightness.sh down    lower brightness 5%
#
# Needs brightnessctl on the laptop (sudo pacman -S brightnessctl) and wl-gammarelay-rs on the desktop.

STEP=5                      # percent per press / scroll
MIN=1                       # laptop: never go fully black
BACKLIGHT_DIR="${BACKLIGHT_DIR:-/sys/class/backlight}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"

if [ -n "$(ls -A "$BACKLIGHT_DIR" 2>/dev/null)" ] && command -v brightnessctl >/dev/null 2>&1; then
    backend=panel
else
    backend=gamma
fi

get() {
    case $backend in
        panel) brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%' ;;
        gamma) busctl --user get-property rs.wl-gammarelay / rs.wl.gammarelay Brightness 2>/dev/null |
                   awk '{print int($2 * 100 + 0.5)}' ;;
    esac
}

change() {   # $1 = + or -
    case $backend in
        panel)
            cur=$(get); cur=${cur:-100}
            if [ "$1" = + ]; then new=$(( cur + STEP )); [ "$new" -gt 100 ] && new=100
            else                  new=$(( cur - STEP )); [ "$new" -lt "$MIN" ] && new=$MIN; fi
            brightnessctl -q set "${new}%" ;;
        gamma) busctl --user call rs.wl-gammarelay / rs.wl.gammarelay UpdateBrightness d "${1}0.0${STEP}" >/dev/null 2>&1 ;;
    esac
    pkill -RTMIN+9 waybar 2>/dev/null     # refresh the bar's number right away
}

case "$1" in
    up)   change + ;;
    down) change - ;;
    *)    get ;;
esac
