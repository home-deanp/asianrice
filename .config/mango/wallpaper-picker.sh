#!/usr/bin/env bash
# Wallpaper picker: a grid of big previews in rofi. Pick one and everything rethemes (theme.sh).
#   Enter / click   use the highlighted wallpaper
#   Alt+R           pick a random wallpaper
#   Esc             close
#
# Put your wallpapers in ~/Pictures/Wallpapers (or set WALLPAPER_DIR).
# Needs imagemagick for fast, sharp previews (sudo pacman -S imagemagick); the first open builds them.

DIR="${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}"
THEME_SH="${THEME_SH:-$HOME/.config/mango/theme.sh}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
THUMBS="$CACHE/wallpaper-thumbs-v2"
PICKER_THEME="$CACHE/wallpaper-picker.rasi"

# ---- size knobs ---------------------------------------------------------------
COLS=3            # (not called COLUMNS: bash treats that name specially)
ROWS=2
ICON=16           # preview size in "em" (text heights); 16 is about 300px. Bigger = bigger previews
# -----------------------------------------------------------------------------------
WIDTH=$(( COLS * (ICON + 3) + 2 ))     # window width in em

mkdir -p "$THUMBS"

if command -v magick >/dev/null 2>&1; then IM=(magick)
elif command -v convert >/dev/null 2>&1; then IM=(convert)
else IM=(); fi

mapfile -t files < <(find "$DIR" -maxdepth 2 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null | sort)

if [ "${#files[@]}" -eq 0 ]; then
    msg="No wallpapers found in $DIR"
    command -v notify-send >/dev/null && notify-send "Wallpaper" "$msg"
    echo "$msg" >&2
    exit 1
fi

# A self-contained theme (not layered on clipboard.rasi, so nothing inherited can hide the previews).
# Black + accent colour, no names, no search bar.
build_theme() {
    local accent
    accent=$(cat "$CACHE/theme/accent" 2>/dev/null)
    accent=${accent:-3B5283}
    cat > "$PICKER_THEME" <<EOF
* {
    font: "Figtree 11";
}
window {
    location: center;
    anchor: center;
    width: ${WIDTH}em;
    padding: 12px;
    border: 2px;
    border-radius: 0px;
    border-color: #${accent}FF;
    background-color: #000000E6;
}
mainbox {
    children: [listview];
    background-color: transparent;
}
listview {
    columns: ${COLS};
    lines: ${ROWS};
    scrollbar: false;
    spacing: 8px;
    background-color: transparent;
}
element {
    orientation: vertical;
    padding: 8px;
    border-radius: 0px;
    background-color: transparent;
}
element normal.normal, element alternate.normal {
    background-color: transparent;
    text-color: transparent;
}
element selected.normal {
    background-color: #${accent}FF;
    text-color: transparent;
}
element-icon {
    size: ${ICON}em;
    background-color: transparent;
}
/* the label only exists so rofi keeps the row: make it invisible and flat */
element-text {
    font: "Figtree 1";
    text-color: transparent;
    padding: 0px;
    margin: 0px;
}
EOF
}

thumb_for() {   # a cached 4:3 preview of $1 (falls back to the original)
    local f=$1 key t
    [ ${#IM[@]} -gt 0 ] || { printf '%s' "$f"; return; }
    key=$(printf '%s%s' "$f" "$(stat -c %Y "$f")" | md5sum | cut -c1-16)
    t="$THUMBS/$key.png"
    [ -s "$t" ] || "${IM[@]}" "${f}[0]" -thumbnail 480x360^ -gravity center -extent 480x360 "png:$t" 2>/dev/null
    if [ -s "$t" ]; then printf '%s' "$t"; else printf '%s' "$f"; fi
}

build_theme

# Each row needs a real (non-blank) label or rofi drops it; the theme hides the text anyway.
LOG="$CACHE/wallpaper-picker.log"
choice=$(
    n=0
    for f in "${files[@]}"; do
        n=$((n + 1))
        printf '%s\0icon\x1f%s\n' "$n" "$(thumb_for "$f")"
    done | rofi -config "$PICKER_THEME" -dmenu -p Wallpaper -format i -show-icons \
        -columns "$COLS" -lines "$ROWS" \
        -kb-cancel Escape -kb-custom-1 "Alt+r" 2>"$LOG"
)
rc=$?

if [ "$rc" -eq 10 ]; then
    pick=${files[RANDOM % ${#files[@]}]}          # Alt+R
elif [ -z "$choice" ]; then
    exit 0                                         # Esc
else
    pick=${files[$choice]}
fi

"$THEME_SH" "$pick"
