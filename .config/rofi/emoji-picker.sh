#!/usr/bin/env bash
# Emoji picker for rofi + wl-copy
#   Type to search by name AND hidden keywords (e.g. "crying", "tears", "sparkly eyes")
#   Enter = copy the emoji to your clipboard
#   Recently used emojis are pinned to the top
#
# Needs: rofi, wl-clipboard, curl (curl only for the first run)
#
# Add your own search words in ~/.config/rofi/emoji-extra.txt
# (the list rebuilds automatically after you edit it).

CONFIG="$HOME/.config/rofi/clipboard.rasi"        # reuse the clipboard menu theme
EXTRA="${EMOJI_EXTRA:-$HOME/.config/rofi/emoji-extra.txt}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/rofi-emoji"
RAW_TEST="$CACHE_DIR/emoji-test.txt"
RAW_ANN="$CACHE_DIR/annotations-en.xml"
LIST="$CACHE_DIR/emoji.txt"
RECENT="$CACHE_DIR/recent.txt"
TEST_URL="https://unicode.org/Public/emoji/latest/emoji-test.txt"
ANN_URL="https://raw.githubusercontent.com/unicode-org/cldr/main/common/annotations/en.xml"

# Hide emojis newer than your emoji font supports (they show up as boxes / weird icons).
# Raise this (e.g. 16.0, 17.0) if your font is recent, lower it if you still see boxes.
MAX_VERSION=15.1

AUTO_TYPE=0   # set to 1 to also type the emoji into the focused window (needs wtype)

mkdir -p "$CACHE_DIR" "$(dirname "$EXTRA")"
touch "$RECENT"

# Default extra search words (only created once, edit freely)
if [ ! -f "$EXTRA" ]; then
    cat > "$EXTRA" <<'EOF'
# Extra search words. One emoji per line: the emoji, then words to find it by.
# Lines starting with # are ignored. The picker rebuilds its list when this file changes.
🥺 sparkly eyes sparkle shiny eyes puppy eyes uwu cute begging please
🥹 sparkly eyes teary tears happy cry crying touched
🤩 sparkly eyes sparkle starry eyes wow amazed excited
✨ sparkly sparkle sparkles glitter shiny magic
💖 sparkly heart sparkle pink heart love
😭 crying tears sobbing bawling sad cry
😢 crying tears sad cry teardrop
🥲 crying tears smiling happy sad bittersweet
😂 laughing crying tears joy lol lmao
😿 crying cat tears sad cry
💔 broken heart sad heartbreak crying
🫠 melting face awkward embarrassed
🙏 please thank you pray hope begging
EOF
fi

# Turn the Unicode emoji list + keyword database into "😀 grinning face<SOH>meta<US>search words"
build_list() {
    [ -s "$RAW_TEST" ] || curl -fsSL "$TEST_URL" -o "$RAW_TEST" || return 1
    [ -s "$RAW_ANN" ]  || curl -fsSL "$ANN_URL"  -o "$RAW_ANN"  || return 1
    {
        grep -v -e '^#' -e '^[[:space:]]*$' "$EXTRA" | sed 's/^/X\t/'
        grep '<annotation cp=' "$RAW_ANN" | grep -v 'type="tts"' | sed 's/^/A\t/'
        grep '; fully-qualified' "$RAW_TEST" | sed 's/^/E\t/'
    } | LC_ALL=C awk -F'\t' -v maxv="$MAX_VERSION" '
        function strip(s) { gsub(/\357\270\217/, "", s); return s }
        function decode(s) {
            gsub(/&quot;/, "\"", s); gsub(/&apos;/, "\047", s)
            gsub(/&lt;/, "<", s); gsub(/&gt;/, ">", s); gsub(/&amp;/, "\\&", s)
            return s
        }
        {
            tag = substr($0, 1, 1); rest = substr($0, 3)
        }
        tag == "X" {
            e = rest; sub(/[ \t].*/, "", e)
            k = rest; if (!sub(/^[^ \t]*[ \t]+/, "", k)) k = ""
            extra[strip(e)] = extra[strip(e)] " " k
            next
        }
        tag == "A" {
            line = rest; sub(/^[^"]*"/, "", line)
            cp = line; sub(/".*/, "", cp)
            kw = line; sub(/^[^>]*>/, "", kw); sub(/<\/annotation>.*/, "", kw)
            gsub(/ \| /, " ", kw)
            ann[strip(cp)] = decode(kw)
            next
        }
        tag == "E" {
            sub(/^[^#]*# /, "", rest)
            split(rest, f, " ")
            emoji = f[1]; ver = substr(f[2], 2) + 0
            if (ver > maxv + 0) next
            name = rest; sub(/^[^ ]+ [^ ]+ /, "", name)
            if (name ~ /skin tone/) next
            key = strip(emoji)
            printf "%s %s\001meta\037%s %s %s\n", emoji, name, name, ann[key], extra[key]
        }
    ' > "$LIST.tmp" && [ -s "$LIST.tmp" ] && mv "$LIST.tmp" "$LIST"
}

# Rebuild if there is no list yet, the extras changed, or this script (e.g. MAX_VERSION) changed
if [ ! -s "$LIST" ] || [ "$EXTRA" -nt "$LIST" ] || [ "${BASH_SOURCE[0]}" -nt "$LIST" ]; then
    if ! build_list && [ ! -s "$LIST" ]; then
        msg="Couldn't download the emoji list. Check your internet connection and try again."
        command -v notify-send >/dev/null && notify-send "Emoji picker" "$msg"
        echo "$msg" >&2
        exit 1
    fi
fi

# Pin recently used emojis to the top, then hand rofi "text<NUL>meta<US>keywords" rows
choice=$(
    awk -F'\001' -v recent_file="$RECENT" '
        BEGIN {
            while ((getline line < recent_file) > 0)
                if (!(line in rank)) { rank[line] = ++n; order[n] = line }
        }
        { e = $1; sub(/ .*/, "", e); if (e in rank) pinned[e] = $0; else rest[++m] = $0 }
        END {
            for (i = 1; i <= n; i++) if (order[i] in pinned) print pinned[order[i]]
            for (i = 1; i <= m; i++) print rest[i]
        }
    ' "$LIST" | tr '\001' '\000' |
        rofi -config "$CONFIG" -dmenu -i -p Emoji \
            -mesg "Enter: copy emoji  |  search names or words like: crying, sparkly, heart" \
            -theme-str 'entry { placeholder: "Search Emoji"; }'
)

[ -z "$choice" ] && exit 0

emoji=${choice%% *}
printf '%s' "$emoji" | wl-copy

# Remember it as recently used (keep the last 15)
{ printf '%s\n' "$emoji"; grep -vxF "$emoji" "$RECENT"; } | head -n 15 > "$RECENT.tmp" &&
    mv "$RECENT.tmp" "$RECENT"

if [ "$AUTO_TYPE" = 1 ] && command -v wtype >/dev/null; then
    sleep 0.15
    wtype "$emoji"
fi
