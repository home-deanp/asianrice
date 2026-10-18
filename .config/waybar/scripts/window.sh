#!/usr/bin/env bash
# Prints the focused window for Waybar, using mmsg's JSON output.
# Change SHOW to: appid (e.g. "kitty"), title (e.g. "~"), or both.
SHOW="appid"

out=$(mmsg get focusing-client 2>/dev/null)

if command -v jq >/dev/null 2>&1; then
  title=$(jq -r '.title // empty' <<<"$out" 2>/dev/null)
  appid=$(jq -r '.appid // empty' <<<"$out" 2>/dev/null)
else
  title=$(sed -n 's/.*"title":"\([^"]*\)".*/\1/p' <<<"$out")
  appid=$(sed -n 's/.*"appid":"\([^"]*\)".*/\1/p' <<<"$out")
fi

case "$SHOW" in
  title) echo "${title:-$appid}" ;;
  both)  if [[ -n $appid && -n $title ]]; then echo "$appid — $title"; else echo "${appid:-$title}"; fi ;;
  *)     echo "${appid:-$title}" ;;
esac
