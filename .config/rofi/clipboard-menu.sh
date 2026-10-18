#!/usr/bin/env bash
# Clipboard menu for cliphist + rofi
#   Enter  = copy the selected entry
#   Alt+d  = delete the selected entry (menu reopens)
#   Top row = clear all history

CONFIG="$HOME/.config/rofi/clipboard.rasi"
CLEAR_LABEL="🗑  Clear clipboard history"
TAB=$'\t'

while true; do
    entries=$(cliphist list)

    choice=$(
        {
            printf 'clear%s%s\n' "$TAB" "$CLEAR_LABEL"
            [ -n "$entries" ] && printf '%s\n' "$entries"
        } | rofi -config "$CONFIG" -dmenu -p Clipboard \
            -display-columns 2 -display-column-separator '\t' \
            -kb-custom-1 "Alt+d" \
            -mesg "Enter: copy  |  Alt+d: delete entry"
    )
    rc=$?

    # Esc / nothing picked
    [ -z "$choice" ] && exit 0

    id=${choice%%"$TAB"*}

    # Alt+d: delete the highlighted entry, then reopen
    if [ "$rc" -eq 10 ]; then
        [ "$id" != "clear" ] && printf '%s\n' "$choice" | cliphist delete
        continue
    fi

    # Enter on the clear row
    if [ "$id" = "clear" ]; then
        cliphist wipe
        exit 0
    fi

    # Enter on an entry: copy it
    printf '%s\n' "$choice" | cliphist decode | wl-copy
    exit 0
done
