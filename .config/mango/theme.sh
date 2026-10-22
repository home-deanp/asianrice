#!/usr/bin/env bash
# One command to retheme everything from a wallpaper.
#
#   theme.sh ~/Pictures/Wallpapers/forest.jpg   set the wallpaper, pick an accent colour from it,
#                                               recolour your menus/bar/notifications/borders, reload all
#   theme.sh --accent "#ff8800"                 keep the wallpaper, just set the accent colour by hand
#   theme.sh --restore                          re-apply the last wallpaper (run this at login)
#
# Needs: python-pillow (sudo pacman -S python-pillow) and a wallpaper setter: swww / awww / swaybg.
# Everything stays black; only the accent colour (your old #3B5283 blue) changes.
# Recoloured: rofi, mako, waybar (incl. the arch logo), swaylock, mango border, screenshot picker,
# Discord (Vesktop), kitty and fastfetch.

CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE="${XDG_CACHE_HOME:-$HOME/.cache}/theme"
MANGO_CONF="$CFG/mango/config.conf"

# Files whose accent colour gets rewritten. Add any of your own here.
TARGETS=(
    "$CFG"/rofi/*.rasi
    "$CFG/mako/config"
    "$CFG/waybar/style.css"
    "$CFG/swaylock/config"
    "$CFG/mango/screenshot.sh"
    "$CFG/fastfetch/config.jsonc"
)

KITTY_DIR="$CFG/kitty"
KITTY_ANSI_SLOTS="4 6"     # kitty ANSI colours that become the accent (4 = blue, 6 = cyan; fastfetch's arch logo is cyan)
WAYBAR_CSS="$CFG/waybar/style.css"

# Discord custom CSS (Vesktop / Vencord). The whole colour scheme follows the wallpaper hue:
# backgrounds, text greys, hover/active tints and the blue accent ramp.
# Opacity is never touched: the alpha in --bg-3 (fa), --bg-4 (dc), --hover etc. stays exactly as you wrote it.
# The first run saves your original values to ~/.cache/theme/discord-original.json and every later run
# recolours from those, so colours never drift. If you hand-edit those lines, delete that file to re-baseline.
BG_SAT=1.5        # how strongly the dark backgrounds pick up the tint (1.0 = your original saturation)
DISCORD_CSS=(
    "$CFG/vesktop/settings/quickCss.css"
    "$CFG/Vencord/settings/quickCss.css"
)

mkdir -p "$STATE"

notify() { command -v notify-send >/dev/null 2>&1 && notify-send -a Theme "$@"; }
die()    { echo "theme.sh: $*" >&2; notify "Theme" "$*"; exit 1; }

# ---- pick an accent colour from an image -----------------------------------
extract_accent() {
    python3 -I -c '
import colorsys, sys
from PIL import Image

img = Image.open(sys.argv[1]).convert("RGB")
img.thumbnail((128, 128))
data = img.tobytes()

buckets = {}                      # 36 hue buckets -> [weight, r*w, g*w, b*w]
for i in range(0, len(data), 3):
    r, g, b = data[i], data[i + 1], data[i + 2]
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    if s < 0.25 or v < 0.25 or v > 0.97:      # skip greys, near-black and near-white
        continue
    w = s * (v ** 0.5)
    e = buckets.setdefault(int(h * 36) % 36, [0.0, 0.0, 0.0, 0.0])
    e[0] += w; e[1] += r * w; e[2] += g * w; e[3] += b * w

if buckets:
    # strongest hue, counting its two neighbours so one colour is not split in half
    near = lambda k: buckets.get(k % 36, [0.0])[0]
    best = max(buckets, key=lambda k: buckets[k][0] + 0.5 * (near(k - 1) + near(k + 1)))
    w, r, g, b = buckets[best]
    r, g, b = r / w / 255, g / w / 255, b / w / 255
else:
    r, g, b = 0.50, 0.56, 0.65               # greyscale wallpaper: soft grey-blue

h, l, s = colorsys.rgb_to_hls(r, g, b)
s = min(max(s, 0.45), 0.75)                  # vivid enough, not neon
l = min(max(l, 0.42), 0.58)                  # readable on black
r, g, b = colorsys.hls_to_rgb(h, l, s)
print("%02X%02X%02X" % (round(r * 255), round(g * 255), round(b * 255)))
' "$1"
}

# ---- wallpaper ----------------------------------------------------------------
# awww / swww need their daemon running (yours is started by exec_once=awww-daemon).
# If it is not up yet, e.g. when this runs at login, start it and wait up to 5 seconds.
img_with_daemon() {   # $1 = awww or swww, $2 = image
    local tool=$1 i
    pgrep -x "$tool-daemon" >/dev/null 2>&1 || setsid -f "$tool-daemon" >/dev/null 2>&1
    for i in 1 2 3 4 5 6 7 8 9 10; do
        "$tool" img "$2" --transition-type fade >/dev/null 2>&1 && return 0
        sleep 0.5
    done
    return 1
}

set_wallpaper() {
    local img=$1
    if command -v awww >/dev/null 2>&1; then
        img_with_daemon awww "$img"
    elif command -v swww >/dev/null 2>&1; then
        img_with_daemon swww "$img"
    elif command -v swaybg >/dev/null 2>&1; then
        pkill -x swaybg
        setsid -f swaybg -i "$img" -m fill >/dev/null 2>&1
    else
        notify "Theme" "No wallpaper setter found (install swaybg or swww). Colours still updated."
    fi
}

# ---- discord ---------------------------------------------------------------------
discord_recolor() {   # $1 = quickCss.css, $2 = accent hex (no #)
    python3 -I - "$1" "$2" "$STATE/discord-original.json" "$BG_SAT" <<'PY'
import colorsys, json, os, re, sys

css_path, accent, state_path, bg_sat = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
BASE_HUE = 221                       # the hue of your original --blue palette

r, g, b = (int(accent[i:i + 2], 16) / 255 for i in (0, 2, 4))
target = round(colorsys.rgb_to_hsv(r, g, b)[0] * 360) % 360
delta = target - BASE_HUE

BLUE = {"--blue-%d" % i for i in range(1, 6)}
BG = {"--bg-%d" % i for i in range(1, 5)}
VARS = BLUE | BG | {"--text-%d" % i for i in range(1, 6)} | {
    "--hover", "--active", "--active-2", "--message-hover", "--button-border"}

HSL = re.compile(r"^(hsla?\(\s*)(-?[0-9.]+)(.*)$", re.I)
HEX = re.compile(r"^#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$")
LINE = re.compile(r"^(\s*)(--[a-z0-9-]+)(\s*:\s*)([^;]+?)(\s*;.*)$")

def recolor(name, value):
    sat = bg_sat if name in BG else 1.0
    m = HSL.match(value)
    if m:
        hue = (float(m.group(2)) + delta) % 360
        rest = m.group(3)                       # ", S%, L%[, A])" - alpha lives here, untouched
        if sat != 1.0:
            def bump(x):
                v = ("%.1f" % min(float(x.group(2)) * sat, 100)).rstrip("0").rstrip(".")
                return "%s%s%%" % (x.group(1), v)
            rest = re.sub(r"^(\s*,\s*)([0-9.]+)%", bump, rest, count=1)
        return "%s%s%s" % (m.group(1), ("%.1f" % hue).rstrip("0").rstrip("."), rest)
    m = HEX.match(value)
    if m:
        rgb, alpha = m.group(1), m.group(2) or ""
        rr, gg, bb = (int(rgb[i:i + 2], 16) / 255 for i in (0, 2, 4))
        h, l, s = colorsys.rgb_to_hls(rr, gg, bb)
        h = (h + delta / 360) % 1
        s = min(s * sat, 1.0)
        rr, gg, bb = colorsys.hls_to_rgb(h, l, s)
        out = "%02x%02x%02x" % (round(rr * 255), round(gg * 255), round(bb * 255))
        if rgb != rgb.lower():
            out = out.upper()
        return "#" + out + alpha                 # alpha byte copied as-is
    return None

text = open(css_path, encoding="utf-8").read()
try:
    state = json.load(open(state_path))
except Exception:
    state = {}
orig = state.setdefault(css_path, {})

lines = text.split("\n")
for i, line in enumerate(lines):
    m = LINE.match(line)
    if not m or m.group(2) not in VARS:
        continue
    name, value = m.group(2), m.group(4)
    if name not in orig:
        base = value
        if name in BLUE:                          # a previous theme.sh may already have rotated these
            mm = HSL.match(base)
            if mm:
                base = "%s%d%s" % (mm.group(1), BASE_HUE, mm.group(3))
        orig[name] = base
    new = recolor(name, orig[name])
    if new is not None:
        lines[i] = "%s%s%s%s%s" % (m.group(1), name, m.group(3), new, m.group(5))

out = "\n".join(lines)
if out != text:
    open(css_path, "w", encoding="utf-8").write(out)
os.makedirs(os.path.dirname(state_path), exist_ok=True)
json.dump(state, open(state_path, "w"), indent=1)
PY
}

# ---- kitty ------------------------------------------------------------------------
# Writes ~/.config/kitty/theme-accent.conf and makes sure kitty.conf includes it (last line, so it wins).
# Fastfetch draws its logo and labels with the terminal's ANSI colours, so it follows this automatically.
kitty_recolor() {   # $1 = accent hex (no #)
    [ -d "$KITTY_DIR" ] || return 0
    python3 -I - "$1" "$KITTY_DIR/theme-accent.conf" "$KITTY_ANSI_SLOTS" <<'PY'
import colorsys, sys
acc, out, slots = sys.argv[1], sys.argv[2], sys.argv[3].split()
r, g, b = (int(acc[i:i + 2], 16) / 255 for i in (0, 2, 4))
h, l, s = colorsys.rgb_to_hls(r, g, b)
def hexof(l2):
    rr, gg, bb = colorsys.hls_to_rgb(h, min(max(l2, 0), 1), s)
    return "#%02x%02x%02x" % (round(rr * 255), round(gg * 255), round(bb * 255))
base, bright = hexof(l), hexof(l + 0.12)
fg = "#000000" if (0.299 * r + 0.587 * g + 0.114 * b) > 0.55 else "#ffffff"
lines = ["# written by theme.sh - do not edit",
         "cursor " + base, "url_color " + base,
         "active_border_color " + base,
         "active_tab_background " + base, "active_tab_foreground " + fg,
         "selection_background " + base, "selection_foreground " + fg]
for n in slots:
    n = int(n)
    lines.append("color%d %s" % (n, base))
    lines.append("color%d %s" % (n + 8, bright))
open(out, "w").write("\n".join(lines) + "\n")
PY
    local conf="$KITTY_DIR/kitty.conf"
    if [ -f "$conf" ] && ! grep -q 'theme-accent.conf' "$conf"; then
        printf '\n# accent colours from theme.sh\ninclude theme-accent.conf\n' >> "$conf"
    fi
}

# ---- apply the accent colour ----------------------------------------------------
apply_accent() {
    local new=${1#\#}
    new=${new^^}
    local old
    old=$(cat "$STATE/accent" 2>/dev/null)
    old=${old:-3B5283}                                  # the blue you started with

    # waybar arch logo: it used a fixed catppuccin blue; make it follow the accent (one-time switch)
    [ -f "$WAYBAR_CSS" ] && sed -i "/^#custom-arch[[:space:]]*{/,/^}/ s/#89b4fa/#$old/I" "$WAYBAR_CSS"

    if [ "$old" != "$new" ]; then
        local f
        for f in "${TARGETS[@]}"; do
            [ -f "$f" ] && sed -i "s/$old/$new/Ig" "$f"
        done
    fi

    # mango: active window border (0xRRGGBBAA)
    if [ -f "$MANGO_CONF" ]; then
        local line="focus_color=0x${new}ff"
        if grep -q '^[[:space:]]*focus_color=' "$MANGO_CONF"; then
            sed -i "s/^[[:space:]]*focus_color=.*/$line/" "$MANGO_CONF"
        else
            printf '\n%s\n' "$line" >> "$MANGO_CONF"
        fi
    fi

    # discord: shift every themed colour to the new hue (Vesktop picks up the file change by itself)
    local css
    for css in "${DISCORD_CSS[@]}"; do
        [ -f "$css" ] && discord_recolor "$css" "$new"
    done

    # fastfetch: also catch colours written as 38;2;R;G;B
    if [ "$old" != "$new" ] && [ -f "$CFG/fastfetch/config.jsonc" ]; then
        local o n
        o=$(printf '%d;%d;%d' 0x${old:0:2} 0x${old:2:2} 0x${old:4:2})
        n=$(printf '%d;%d;%d' 0x${new:0:2} 0x${new:2:2} 0x${new:4:2})
        sed -i "s/38;2;$o/38;2;$n/g" "$CFG/fastfetch/config.jsonc"
    fi

    kitty_recolor "$new"

    echo "$new" > "$STATE/accent"
}

# ---- reload everything that is running -----------------------------------------
reload_all() {
    command -v makoctl >/dev/null 2>&1 && makoctl reload
    pgrep -x waybar >/dev/null 2>&1 && pkill -SIGUSR2 waybar          # waybar reloads its CSS
    if command -v mmsg >/dev/null 2>&1; then
        mmsg dispatch reload_config >/dev/null 2>&1 || mmsg -d reload_config >/dev/null 2>&1
    fi
    pgrep -x kitty >/dev/null 2>&1 && pkill -USR1 -x kitty          # kitty reloads its config
    # rofi, swaylock and the screenshot picker read their colours each time they open
}

valid_hex() { [[ $1 =~ ^#?[0-9a-fA-F]{6}$ ]]; }

case "$1" in
    ""|-h|--help)
        sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    --restore)
        img=$(cat "$STATE/wallpaper" 2>/dev/null)
        [ -f "$img" ] && set_wallpaper "$img"
        exit 0
        ;;
    --accent)
        valid_hex "$2" || die "Give a colour like: theme.sh --accent \"#ff8800\""
        apply_accent "$2"
        reload_all
        notify "Accent set" "#${2#\#}"
        ;;
    *)
        img=$(realpath -- "$1" 2>/dev/null)
        [ -f "$img" ] || die "Not a file: $1"
        accent=$(extract_accent "$img") || die "Couldn't read colours (is python-pillow installed? sudo pacman -S python-pillow)"
        valid_hex "$accent" || die "Colour extraction failed"
        set_wallpaper "$img"
        echo "$img" > "$STATE/wallpaper"
        apply_accent "$accent"
        reload_all
        notify "Theme updated" "Accent #$accent"
        ;;
esac
