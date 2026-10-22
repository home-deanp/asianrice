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
# Saved shots go to ~/Pictures/Screenshots. Copied ones also land in your clipboard menu as thumbnails.

DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
mkdir -p "$DIR"

notify() { command -v notify-send >/dev/null && notify-send "$@"; }

for tool in grim slurp wl-copy; do
    command -v "$tool" >/dev/null 2>&1 || {
        msg="Screenshot needs '$tool' installed (sudo pacman -S grim slurp wl-clipboard)."
        notify "Screenshot" "$msg"; echo "$msg" >&2
        exit 1
    }
done

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
    wl-copy --type image/png < "$file"
    notify -a Screenshot -i "$file" "Screenshot copied" "Saved to ${file/#$HOME/~}"
}

mode=${1:-area}
[ "$mode" = edit ] && mode=area

case "$mode" in
    area)
        geom=$(pick_area) || exit 0                 # Esc / right-click cancels
        if command -v swappy >/dev/null 2>&1; then
            setup_swappy
            grim -g "$geom" - | swappy -f -         # Ctrl+C copies, Ctrl+S saves, then it closes
        else
            notify "Screenshot" "Install swappy for the copy/save choice (sudo pacman -S swappy). Saved and copied for now."
            save_and_copy grim -g "$geom"
        fi
        ;;
    quick)
        geom=$(pick_area) || exit 0
        save_and_copy grim -g "$geom"
        ;;
    screen)
        save_and_copy grim
        ;;
    output)
        [ -n "$2" ] || { echo "usage: screenshot.sh output <name, e.g. DP-1>" >&2; exit 1; }
        save_and_copy grim -o "$2"
        ;;
    *)
        echo "usage: screenshot.sh [area|quick|screen|output NAME]" >&2
        exit 1
        ;;
esac
