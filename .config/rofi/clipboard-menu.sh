#!/usr/bin/env bash
# Clipboard menu for cliphist + rofi, with image thumbnails
#   Enter  = copy the selected entry
#   Alt+d  = delete the selected entry (menu reopens)
#   Top row = clear all history
#
# Copied images / screenshots show as thumbnails instead of "[[ binary data ]]".
# Optional: install imagemagick to make the thumbnails small and fast (sudo pacman -S imagemagick).

CONFIG="$HOME/.config/rofi/clipboard.rasi"
CLEAR_LABEL="🗑  Clear clipboard history"
TAB=$'\t'
THUMBS="${XDG_CACHE_HOME:-$HOME/.cache}/cliphist-thumbs"
MAX_THUMBS=40      # only the newest this-many images get a thumbnail
mkdir -p "$THUMBS"

if command -v magick >/dev/null 2>&1; then IM=(magick)
elif command -v convert >/dev/null 2>&1; then IM=(convert)
else IM=(); fi

# cliphist labels images like:  [[ binary data 56 KiB png 1280x720 ]]
img_re='^\[\[ binary data .* (png|jpe?g|bmp|gif|webp|tiff?) ([0-9]+x[0-9]+) \]\]$'

# Print the menu rows. Image rows get a thumbnail via rofi's "text\0icon\x1f<path>" syntax.
build_rows() {
    local list line id rest ext dims key file f count=0
    local -A keep=()
    list=$(cliphist list)
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        id=${line%%"$TAB"*}
        rest=${line#*"$TAB"}
        if [[ $rest =~ $img_re ]] && [ "$count" -lt "$MAX_THUMBS" ]; then
            ext=${BASH_REMATCH[1]}; dims=${BASH_REMATCH[2]}
            [ "$ext" = jpeg ] && ext=jpg
            # name includes the label so a reused id can never show someone else's picture
            key=$(printf '%s' "$rest" | tr -c 'A-Za-z0-9' '_')
            if [ ${#IM[@]} -gt 0 ]; then file="$THUMBS/${id}_${key}.png"; else file="$THUMBS/${id}_${key}.$ext"; fi
            if [ ! -s "$file" ]; then
                if [ ${#IM[@]} -gt 0 ]; then
                    cliphist decode "$id" | "${IM[@]}" '-[0]' -thumbnail 320x320 "png:$file" 2>/dev/null
                else
                    cliphist decode "$id" > "$file" 2>/dev/null
                fi
            fi
            if [ -s "$file" ]; then
                keep["$file"]=1
                printf '%s\t%s\0icon\x1f%s\n' "$id" "Image  ($ext $dims)" "$file"
                count=$((count + 1))
                continue
            fi
        fi
        printf '%s\n' "$line"
    done <<< "$list"
    # drop thumbnails of entries that are no longer in the history
    for f in "$THUMBS"/*; do
        [ -e "$f" ] || continue
        [ -n "${keep[$f]}" ] || rm -f "$f"
    done
}

while true; do
    choice=$(
        {
            printf 'clear%s%s\n' "$TAB" "$CLEAR_LABEL"
            build_rows
        } | rofi -config "$CONFIG" -dmenu -p Clipboard -show-icons \
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
        rm -f "$THUMBS"/*
        exit 0
    fi

    # Enter on an entry: copy it (images are copied back as the full original)
    printf '%s\n' "$choice" | cliphist decode | wl-copy
    exit 0
done
