#!/usr/bin/env bash
# Pick your own accent colour (or go back to following the wallpaper) from a rofi list.
#   Auto            the accent comes from the wallpaper again
#   a colour        that colour is kept, even when you change wallpapers
#   Custom colour   type your own hex, e.g. ff8800
#
# Put it on a key, e.g. in the mango config:  bind=SUPER+SHIFT,t,spawn,~/.config/mango/accent-picker.sh

THEME_SH="${THEME_SH:-$HOME/.config/mango/theme.sh}"
BASE_THEME="$HOME/.config/rofi/clipboard.rasi"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
LIST_THEME="$CACHE/accent-list.rasi"
ENTRY_THEME="$CACHE/accent-entry.rasi"

# name|hex      (edit or add your own lines here)
PRESETS=(
    "White|F2F2F2"
    "Red|E03131"
    "Orange|F76B15"
    "Yellow|F5C542"
    "Green|30A46C"
    "Teal|12A594"
    "Blue|3B82F6"
    "Original blue|3B5283"
    "Purple|8E4EC6"
    "Pink|E93D82"
)

mkdir -p "$CACHE"
{ [ -f "$BASE_THEME" ] && cat "$BASE_THEME"; printf '\nmainbox {\n    children: [listview];\n}\n'; } > "$LIST_THEME"
{ [ -f "$BASE_THEME" ] && cat "$BASE_THEME"; printf '\nmainbox {\n    children: [inputbar];\n}\n'; } > "$ENTRY_THEME"

rows=("Auto  (follow the wallpaper)")
for p in "${PRESETS[@]}"; do
    rows+=("<span foreground=\"#${p#*|}\">●</span>  ${p%|*}")
done
rows+=("Custom colour…")

choice=$(printf '%s\n' "${rows[@]}" | rofi -config "$LIST_THEME" -dmenu -markup-rows -p Accent -format i -kb-cancel Escape)
[ -z "$choice" ] && exit 0

if [ "$choice" -eq 0 ]; then
    exec "$THEME_SH" --auto
elif [ "$choice" -eq $(( ${#rows[@]} - 1 )) ]; then
    hex=$(printf '' | rofi -config "$ENTRY_THEME" -dmenu -p "Hex colour (e.g. ff8800)" -kb-cancel Escape)
    hex=${hex#\#}
    [[ $hex =~ ^[0-9a-fA-F]{6}$ ]] || { notify-send -a Theme "Accent" "That isn't a 6-digit hex colour"; exit 1; }
    exec "$THEME_SH" --accent "#$hex"
else
    p=${PRESETS[$((choice - 1))]}
    exec "$THEME_SH" --accent "#${p#*|}"
fi
