#!/usr/bin/env bash
# Lightweight screenshot tool for Wayland: grim + slurp (+ swappy for the choose-after step).
#
#   screenshot.sh area      drag to select a region, then a small window shows it:
#                             Ctrl+C = copy to clipboard   Ctrl+S = save to file   (it closes after either)
#                             Esc = cancel
#   screenshot.sh quick     drag to select a region; saved AND copied instantly, no window
#   screenshot.sh screen    all monitors, saved AND copied instantly
#   screenshot.sh output    just one monitor, saved AND copied:  screenshot.sh output DP-1
#
# Needs: grim slurp wl-clipboard swappy libnotify
# Optional: wayfreeze freezes the screen while you pick the area (yay -S wayfreeze-git).
# Optional: wlrctl moves the cursor out of the way for the grab (sudo pacman -S wlrctl)
# Optional: imagemagick + wlr-randr let the picture be cut from a clean grab taken the instant you press the key,
#           so the mouse cursor and the selector can never end up in it.
# Saved shots go to ~/Pictures/Screenshots. Copied ones also land in your clipboard menu as thumbnails.

DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
mkdir -p "$DIR"

# Only one at a time: pressing the shortcut again while a screenshot is open cancels the selection instead of
# starting a second one.
exec 9> "${XDG_RUNTIME_DIR:-/tmp}/screenshot.lock"
if ! flock -n 9; then
    pkill -x slurp
    exit 0
fi

notify() { command -v notify-send >/dev/null && notify-send "$@"; }

for tool in grim slurp wl-copy; do
    command -v "$tool" >/dev/null 2>&1 || {
        msg="Screenshot needs '$tool' installed (sudo pacman -S grim slurp wl-clipboard)."
        notify "Screenshot" "$msg"; echo "$msg" >&2
        exit 1
    }
done

# Freeze the screen while you select (needs wayfreeze; without it everything still works, just unfrozen)
freeze_pid=""
freeze_start() {
    command -v wayfreeze >/dev/null 2>&1 || return 0
    wayfreeze --hide-cursor >/dev/null 2>&1 &
    freeze_pid=$!
    sleep 0.15                                  # let it grab the frame before the selector appears
}
freeze_stop() {
    [ -n "$freeze_pid" ] && kill "$freeze_pid" 2>/dev/null
    freeze_pid=""
}

# ---- clean grab ---------------------------------------------------------------------
# grim leaves the cursor out by default, but wayfreeze's frozen frame has it baked in. So we grab the whole screen
# with grim first (before anything is drawn), freeze for the selection, and cut the chosen area out of that grab.
if command -v magick >/dev/null 2>&1; then IM=(magick)
elif command -v convert >/dev/null 2>&1; then IM=(convert)
else IM=(); fi

PRE=""; LAYOUT=""
screen_layout() {    # prints "left top scale" of all enabled outputs (a full grim grab starts at left/top, at the top scale)
    command -v wlr-randr >/dev/null 2>&1 || return 1
    wlr-randr 2>/dev/null | awk '
        /^[^ ]/     { en = 0; px = 0; py = 0 }
        /Enabled:/  { en = ($2 == "yes") }
        /Position:/ { split($2, p, ","); px = p[1]; py = p[2] }
        /Scale:/    { if (en) { if (!n || px < mx) mx = px; if (!n || py < my) my = py; if ($2 > sc) sc = $2; n++ } }
        END { if (n) printf "%d %d %s\n", mx, my, sc }'
}
# Your compositor draws the cursor into every capture and the compositor can't be told not to, so we push the
# pointer into the bottom-right corner first (wlrctl). There only its very tip is on screen, 1 pixel.
HIDE_WAIT=0.15
park_cursor() {
    command -v wlrctl >/dev/null 2>&1 && wlrctl pointer move 20000 20000 >/dev/null 2>&1
    sleep "$HIDE_WAIT"
}
precapture() {
    park_cursor
    [ ${#IM[@]} -gt 0 ] || return 0
    LAYOUT=$(screen_layout) || return 0
    [ -n "$LAYOUT" ] || return 0
    PRE=$(mktemp --suffix=.png)
    grim "$PRE" 2>/dev/null && [ -s "$PRE" ] || { rm -f "$PRE"; PRE=""; }
}
capture_region() {   # $1 = slurp geometry "x,y wxh", $2 = output file
    if [ -n "$PRE" ]; then
        local gx gy gw gh ox oy sc crop
        read -r gx gy gw gh <<< "$(tr ',x' '  ' <<< "$1")"
        read -r ox oy sc <<< "$LAYOUT"
        crop=$(awk -v gx="$gx" -v gy="$gy" -v gw="$gw" -v gh="$gh" -v ox="$ox" -v oy="$oy" -v s="$sc" 'BEGIN {
            printf "%dx%d+%d+%d", gw * s + 0.5, gh * s + 0.5, (gx - ox) * s + 0.5, (gy - oy) * s + 0.5 }')
        "${IM[@]}" "$PRE" -crop "$crop" +repage "$2" 2>/dev/null && [ -s "$2" ] && return 0
    fi
    grim -g "$1" "$2"        # fallback: capture live
}
cleanup() { freeze_stop; [ -n "$PRE" ] && rm -f "$PRE"; }
trap cleanup EXIT

# Region picker styled like your theme: dimmed screen, blue outline
# After you let go, slurp's overlay takes a moment to disappear. If grim fires before that, the coloured
# outline and tint end up in the screenshot, so wait a moment (raise SETTLE if you still see a tint).
SETTLE=0.3
pick_area() {
    local g accent
    accent=$(cat "${XDG_CACHE_HOME:-$HOME/.cache}/theme/accent" 2>/dev/null)    # the colour theme.sh last picked
    accent=${accent:-3B5283}
    g=$(slurp -d -b '#00000066' -c "#${accent}FF" -s "#${accent}33" -w 2) || return 1
    sleep "$SETTLE"
    printf '%s\n' "$g"
}

# Swappy settings: close after you copy or save, save into the Screenshots folder, no toolbar.
# Only created if you don't already have a swappy config (set show_panel=true to get drawing tools).
setup_swappy() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/swappy/config"
    [ -f "$cfg" ] && return
    mkdir -p "$(dirname "$cfg")"
    cat > "$cfg" <<EOF
[Default]
save_dir=$DIR
save_filename_format=%Y-%m-%d_%H-%M-%S.png
early_exit=true
show_panel=false
auto_save=false
EOF
}

# Instant save + copy of an existing grim command's output
save_and_copy() {
    local file="$DIR/$(date +%Y-%m-%d_%H-%M-%S).png"
    "$@" "$file" || exit 1
    freeze_stop
    wl-copy --type image/png < "$file"
    notify -a Screenshot -i "$file" "Screenshot copied" "Saved to ${file/#$HOME/~}"
}

mode=${1:-area}
[ "$mode" = edit ] && mode=area

case "$mode" in
    area)
        precapture
        freeze_start
        geom=$(pick_area) || exit 0                 # Esc / right-click cancels
        if command -v swappy >/dev/null 2>&1; then
            setup_swappy
            tmp=$(mktemp --suffix=.png)
            capture_region "$geom" "$tmp"           # cut from the grab taken when you pressed the key...
            freeze_stop                             # ...then unfreeze and open the editor
            swappy -f "$tmp"                        # Ctrl+C copies, Ctrl+S saves, then it closes
            rm -f "$tmp"
        else
            notify "Screenshot" "Install swappy for the copy/save choice (sudo pacman -S swappy). Saved and copied for now."
            save_and_copy capture_region "$geom"
        fi
        ;;
    quick)
        precapture
        freeze_start
        geom=$(pick_area) || exit 0
        save_and_copy capture_region "$geom"
        ;;
    screen)
        park_cursor
        save_and_copy grim
        ;;
    output)
        [ -n "$2" ] || { echo "usage: screenshot.sh output <name, e.g. DP-1>" >&2; exit 1; }
        park_cursor
        save_and_copy grim -o "$2"
        ;;
    *)
        echo "usage: screenshot.sh [area|quick|screen|output NAME]" >&2
        exit 1
        ;;
esac
