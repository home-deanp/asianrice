#!/usr/bin/env bash
# Calculator for rofi + wl-copy
#   Type an expression, press Enter  -> result appears as the top row
#   Press Enter again (search box empty) -> copies the selected result and closes
#   Start with an operator (e.g. "*5" or "+ 12") to keep calculating from the last result
#   Esc = close
#
# Best with qalc (libqalculate): units, percentages, functions, currency, e.g.
#   15% of 80    5 km to miles    sqrt(144)    2^10    sin(45 deg)    20 USD to AUD
# Without qalc it falls back to python3 (basic maths only).
#
# Needs: rofi, wl-clipboard, and qalc (recommended) or python3

CONFIG="$HOME/.config/rofi/clipboard.rasi"        # reuse the clipboard menu theme
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/rofi-calc"
HISTORY="$CACHE_DIR/history.txt"                  # newest first: "expression = result"
MAX_HISTORY=30

mkdir -p "$CACHE_DIR"
touch "$HISTORY"

evaluate() {
    if command -v qalc >/dev/null 2>&1; then
        qalc -t "$1" 2>/dev/null | tail -n1
    elif command -v python3 >/dev/null 2>&1; then
        python3 -I -c '
import math, re, sys
e = sys.argv[1].replace("^", "**").replace("×", "*").replace("÷", "/")
e = re.sub(r"(\d+(?:\.\d+)?)\s*%", r"(\1/100)", e)
ns = {k: getattr(math, k) for k in dir(math) if not k.startswith("_")}
ns["__builtins__"] = {}
try:
    r = eval(e, ns)
    if isinstance(r, float):
        r = int(r) if r == int(r) and abs(r) < 1e15 else float("%.12g" % r)
    print(r)
except Exception:
    sys.exit(1)
' "$1" 2>/dev/null
    fi
}

if ! command -v qalc >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
    msg="Calculator needs qalc (libqalculate) or python3 installed."
    command -v notify-send >/dev/null && notify-send "Calculator" "$msg"
    echo "$msg" >&2
    exit 1
fi

hint="Type an expression and press Enter  |  e.g. 2+2, 15% of 80, 5 km to miles"
last=""

while true; do
    rows=$(cat "$HISTORY")
    [ -z "$rows" ] && rows="(no results yet)"

    out=$(
        printf '%s\n' "$rows" |
            rofi -config "$CONFIG" -dmenu -p Calc -format 'i|f' \
                -mesg "$hint" \
                -theme-str 'entry { placeholder: "Type an expression"; }'
    )

    # Esc
    [ -z "$out" ] && exit 0

    idx=${out%%|*}
    filt=${out#*|}

    if [ -n "$filt" ]; then
        # Evaluate what was typed (operator first = continue from the last result)
        expr=$filt
        case "$expr" in
            [+*/^%]*|"- "*) [ -n "$last" ] && expr="$last $expr" ;;
        esac

        result=$(evaluate "$expr")
        if [ -z "$result" ]; then
            hint="Couldn't calculate \"$filt\" - try again"
            continue
        fi

        last=$result
        { printf '%s = %s\n' "$expr" "$result"; cat "$HISTORY"; } |
            head -n "$MAX_HISTORY" > "$HISTORY.tmp" && mv "$HISTORY.tmp" "$HISTORY"
        hint="$expr = $result   |   Enter again to copy it"
    else
        # Search box empty: copy the selected row's result
        [ "$idx" -ge 0 ] 2>/dev/null || continue
        row=$(printf '%s\n' "$rows" | sed -n "$((idx + 1))p")
        case "$row" in
            *" = "*) printf '%s' "${row##* = }" | wl-copy; exit 0 ;;
            *) continue ;;
        esac
    fi
done
