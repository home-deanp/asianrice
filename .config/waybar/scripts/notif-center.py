#!/usr/bin/env python3
"""Notification panel for mako, shown in rofi (square corners, app icons, clear button on top).

Lists recent notifications, newest first. Enter on one copies its text and closes.
Top row clears them all. Esc, or clicking the bell again, closes it.
(Do not disturb = right-click the bell, dismiss popups = middle-click, set in waybar.)
"""
import configparser
import glob
import json
import os
import re
import subprocess

CONFIG = os.path.expanduser("~/.config/rofi/clipboard.rasi")   # base theme (fonts, colours)
MAX_ROWS = 50
CACHE = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
CLEARED = os.path.join(CACHE, "mako-cleared")   # notifications up to this id were cleared
CLEAR_LABEL = "Clear all notifications"

# Overrides on top of your clipboard theme: no rounding, no search bar, smaller text.
# Text size is "Figtree 11" below (your launcher uses 13); icons scale with it (1.7em).
# Position is top-right. The compositor already keeps the panel below your bar, so
# y-offset is only the extra gap: 0 = touching the bar, bigger = further down.
# If it overlaps the bar, raise y-offset a little. x-offset: more negative = further left.
OVERRIDES = """
* {
    b-radius: 0px;
    font: "Figtree 11";
}
window {
    background-color: #000000E6;
    border-radius: 0px;
    width: 420px;
    location: northeast;
    anchor: northeast;
    x-offset: -8px;
    y-offset: 4px;
}
mainbox {
    children: [listview];
}
element {
    border-radius: 0px;
}
element-icon {
    size: 1.7em;
}
element-text {
    vertical-align: 0.5;
}
"""
PANEL_THEME = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "notif-panel.rasi")


def build_theme():
    """Your clipboard theme + the overrides above, written as a normal multi-line .rasi file."""
    try:
        with open(CONFIG, encoding="utf-8") as f:
            base = f.read()
    except OSError:
        base = ""
    os.makedirs(os.path.dirname(PANEL_THEME), exist_ok=True)
    with open(PANEL_THEME, "w", encoding="utf-8") as f:
        f.write(base + "\n" + OVERRIDES)
    return PANEL_THEME


def run(*cmd, stdin=None):
    try:
        return subprocess.run(list(cmd), input=stdin, capture_output=True, timeout=300 if stdin else 5)
    except Exception:
        return None


def mako_text(*args):
    res = run("makoctl", *args)
    if not res or res.returncode != 0:
        return None
    return res.stdout.decode("utf-8", "replace")


def load_json(text):
    """Parse makoctl -j output: a JSON array, a dict, or several objects in a row."""
    text = text.strip()
    data = None
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
        if not m:
            continue
        app = re.search(r"^\s*App name: (.*)$", block, re.M)
        entry = re.search(r"^\s*Desktop entry: (.*)$", block, re.M)
        items.append({
            "id": int(m.group(1)),
            "summary": m.group(2).strip(),
            "app_name": app.group(1).strip() if app else "",
            "desktop_entry": entry.group(1).strip() if entry else "",
        })
    return items


def fetch(kind):
    """kind is 'history' or 'list'. Newest first."""
    text = mako_text(kind, "-j")
    items = load_json(text) if text else []
    if not items:
        plain = mako_text(kind)
        items = parse_plain(plain) if plain else []
    clean = []
    for it in items:
        clean.append({
            "id": int(it.get("id") or 0),
            "summary": (it.get("summary") or "").strip(),
            "app": (it.get("app_name") or "").strip(),
            "body": re.sub(r"<[^>]+>", "", it.get("body") or "").replace("\n", " ").strip(),
            "icon": (it.get("app_icon") or "").strip(),
            "entry": (it.get("desktop_entry") or "").strip(),
        })
    clean.sort(key=lambda i: i["id"], reverse=True)
    return clean


# ---- icons -----------------------------------------------------------------

_desktop_index = None


def desktop_index():
    """Map app names / desktop file names to the Icon= from installed .desktop files."""
    global _desktop_index
    if _desktop_index is not None:
        return _desktop_index
    idx = {}
    home = os.path.expanduser("~")
    dirs = [os.path.join(home, ".local/share")]
    dirs += (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    dirs += [os.path.join(home, ".local/share/flatpak/exports/share"), "/var/lib/flatpak/exports/share"]
    for d in dirs:
        for path in glob.glob(os.path.join(d, "applications", "*.desktop")):
            icon = name = wmclass = None
            in_entry = False
            try:
                with open(path, encoding="utf-8", errors="replace") as f:
                    for line in f:
                        line = line.strip()
                        if line.startswith("["):
                            if in_entry:
                                break
                            in_entry = line == "[Desktop Entry]"
                        elif in_entry:
                            if line.startswith("Icon="):
                                icon = line[5:].strip()
                            elif line.startswith("Name="):
                                name = line[5:].strip()
                            elif line.startswith("StartupWMClass="):
                                wmclass = line[15:].strip()
            except OSError:
                continue
            if not icon:
                continue
            stem = os.path.basename(path)[:-8].lower()
            for key in (stem, stem.split(".")[-1], (name or "").lower(), (wmclass or "").lower()):
                if key:
                    idx.setdefault(key, icon)
    _desktop_index = idx
    return idx


def icon_for(n):
    """Icon path or theme icon name for rofi; empty if we have nothing to go on."""
    icon = n["icon"]
    if icon.startswith("file://"):
        icon = icon[7:]
    if icon:
        return icon
    idx = desktop_index()
    for key in (n["entry"], n["app"], n["app"].replace(" ", "-")):
        hit = idx.get(key.lower()) if key else None
        if hit:
            return hit
    return (n["entry"] or n["app"]).lower().replace(" ", "-")


def icon_theme():
    """Rofi can't always tell your icon theme on Wayland, so read it from GTK settings."""
    try:
        cp = configparser.ConfigParser()
        cp.read(os.path.expanduser("~/.config/gtk-3.0/settings.ini"))
        name = cp.get("Settings", "gtk-icon-theme-name", fallback="").strip()
        if name:
            return name
    except Exception:
        pass
    res = run("gsettings", "get", "org.gnome.desktop.interface", "icon-theme")
    if res and res.returncode == 0:
        return res.stdout.decode("utf-8", "replace").strip().strip("'\"")
    return ""


# ---- state -------------------------------------------------------------------

def read_int(path):
    try:
        with open(path) as f:
            return int(f.read().strip() or 0)
    except Exception:
        return 0


def write_int(path, n):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(str(n))
    except Exception:
        pass


def mark_seen():
    """Opening the panel counts as reading: the bell goes back to normal."""
    script = os.path.join(os.path.dirname(os.path.realpath(__file__)), "mako-status.py")
    if os.path.exists(script):
        run("python3", script, "--seen")
    refresh_bar()


def refresh_bar():
    run("pkill", "-RTMIN+8", "waybar")   # matches "signal": 8 in the waybar module


# ---- panel -------------------------------------------------------------------

def main():
    mark_seen()
    past = fetch("history")
    active = fetch("list")
    latest = max([i["id"] for i in past + active] or [0])

    cleared = read_int(CLEARED)
    if latest < cleared:            # mako was restarted and its ids started over
        cleared = 0
        write_int(CLEARED, 0)
    shown = [n for n in past if n["id"] > cleared][:MAX_ROWS]

    rows = []  # (label, icon, kind, text to copy)
    if shown:
        rows.append((CLEAR_LABEL, "", "clear", ""))
    for n in shown:
        label = n["summary"] or n["app"] or "(no title)"
        if n["body"]:
            label += "  -  " + n["body"]
        rows.append((label, icon_for(n), "copy", n["body"] or n["summary"]))

    if rows:
        payload = "\n".join(
            label + (f"\0icon\x1f{icon}" if icon else "") for label, icon, _, _ in rows
        )
    else:
        payload = "No notifications\0nonselectable\x1ftrue"

    cmd = [
        "rofi", "-config", build_theme(), "-dmenu", "-i", "-p", "Notifications",
        "-format", "i", "-show-icons",
        "-kb-cancel", "Escape",   # your theme cancels on any left click; only Esc closes here
    ]
    theme = icon_theme()
    if theme:
        cmd += ["-icon-theme", theme]

    res = run(*cmd, stdin=payload.encode("utf-8"))
    if not res:
        return
    choice = res.stdout.decode("utf-8", "replace").strip()
    if not choice.isdigit() or int(choice) >= len(rows):
        return

    _, _, kind, data = rows[int(choice)]
    if kind == "clear":
        write_int(CLEARED, latest)
        run("makoctl", "dismiss", "-a")
        mark_seen()
    elif kind == "copy" and data:
        run("wl-copy", stdin=data.encode("utf-8"))


main()
