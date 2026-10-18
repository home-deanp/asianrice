#!/usr/bin/env python3
"""Waybar module for mako: monochrome bell, turns blue while you have unread notifications.

  mako-status.py          print the waybar JSON
  mako-status.py --seen   mark everything so far as read (the panel and dismiss-all call this)

Icons are Nerd Font glyphs (needs a Nerd Font or "Symbols Nerd Font" installed):
  U+F0A2 outline bell = nothing new, U+F0F3 solid bell = unread, U+F1F6 bell-slash = do not disturb
"""
import html
import json
import os
import re
import subprocess
import sys

MAX_TOOLTIP = 8
ICON_NONE = ""
ICON_UNREAD = ""
ICON_DND = ""
STATE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "mako-last-seen")


def mako(*args):
    try:
        out = subprocess.run(["makoctl", *args], capture_output=True, text=True, timeout=2)
        return out.stdout if out.returncode == 0 else ""
    except Exception:
        return ""


def load_json(text):
    text = text.strip()
    if not text:
        return []
    try:
        data = json.loads(text)
    except ValueError:
        data, dec, i = [], json.JSONDecoder(), 0
        while i < len(text):
            while i < len(text) and text[i] in " \r\n\t,[]":
                i += 1
            if i >= len(text):
                break
            try:
                obj, i = dec.raw_decode(text, i)
            except ValueError:
                break
            data.append(obj)
    if isinstance(data, dict):
        lists = [v for v in data.values() if isinstance(v, list)]
        data = lists[0] if lists else [data]
    out = []
    for item in data:
        if isinstance(item, list):
            out += [x for x in item if isinstance(x, dict)]
        elif isinstance(item, dict):
            out.append(item)
    return out


def parse_plain(text):
    items = []
    for block in re.split(r"^(?=Notification \d+:)", text, flags=re.M):
        m = re.match(r"Notification (\d+): (.*)", block)
        if m:
            app = re.search(r"^\s*App name: (.*)$", block, re.M)
            items.append({"id": int(m.group(1)), "summary": m.group(2).strip(),
                          "app_name": app.group(1).strip() if app else ""})
    return items


def fetch(kind):
    """Notifications newest first, as dicts with id, summary, app, body."""
    items = load_json(mako(kind, "-j")) or parse_plain(mako(kind))
    out = [
        {
            "id": int(i.get("id") or 0),
            "summary": (i.get("summary") or "").strip(),
            "app": (i.get("app_name") or "").strip(),
            "body": re.sub(r"<[^>]+>", "", i.get("body") or "").replace("\n", " ").strip(),
        }
        for i in items
    ]
    out.sort(key=lambda i: i["id"], reverse=True)
    return out


def read_seen():
    try:
        with open(STATE) as f:
            return int(f.read().strip() or 0)
    except Exception:
        return 0


def write_seen(n):
    try:
        os.makedirs(os.path.dirname(STATE), exist_ok=True)
        with open(STATE, "w") as f:
            f.write(str(n))
    except Exception:
        pass


def line(item):
    text = item["summary"] or item["app"] or "(no title)"
    body = item["body"]
    if body:
        text += " - " + (body if len(body) <= 60 else body[:57] + "...")
    return html.escape(text)


active = fetch("list")
history = fetch("history")
latest = max([i["id"] for i in active + history] or [0])

if "--seen" in sys.argv:
    write_seen(latest)
    sys.exit(0)

seen = read_seen()
if latest < seen:          # mako was restarted and its ids started over
    seen = 0
    write_seen(0)
unread = latest > seen

dnd = "do-not-disturb" in mako("mode").split()

if dnd:
    icon, cls = ICON_DND, "dnd"
elif unread:
    icon, cls = ICON_UNREAD, "active"
else:
    icon, cls = ICON_NONE, "none"

tip = []
if dnd:
    tip.append("<b>Do not disturb is on</b>")
if active:
    tip.append("<b>Now</b>")
    tip += [line(i) for i in active[:MAX_TOOLTIP]]
elif unread:
    tip.append("New notifications - click to view")
if not tip:
    tip.append("No new notifications")
tip.append("")
tip.append("Click: open panel | Right-click: do not disturb | Middle: dismiss all")

print(json.dumps({"text": icon, "tooltip": "\n".join(tip), "class": cls, "alt": cls}))
