#!/usr/bin/env python3
"""Waybar battery module: laptop battery plus any wireless gadget that reports one (mouse, keyboard, headset...).

Reads /sys/class/power_supply, plus UPower (`upower`) for wireless gadgets the kernel does not list there.
Needs nothing extra on a laptop; on a desktop, wireless mice/keyboards come from UPower. Prints nothing (the module hides itself) when the
computer has no battery at all. Output is waybar JSON.

Optional: warns once with a notification when something drops to 15% or lower (not charging).
"""
import glob
import json
import os
import subprocess
import re
import sys

SYS = os.environ.get("POWER_SUPPLY_DIR", "/sys/class/power_supply")
STATE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "battery-warned")
LOW, CRIT = 30, 15
COLOURS = {"ok": "#a6e3a1", "low": "#f9e2af", "crit": "#f38ba8"}   # same palette as the rest of the bar

# Nerd Font (Material Design) glyphs
LEVELS = [0xF008E, 0xF007A, 0xF007B, 0xF007C, 0xF007D, 0xF007E, 0xF007F, 0xF0080, 0xF0081, 0xF0082, 0xF0079]
CHARGING, MOUSE, KEYBOARD, HEADSET = 0xF0084, 0xF037D, 0xF030C, 0xF02CB


def read(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return ""


def fmt_time(seconds):
    m = int(seconds // 60)
    return "%dh %02dm" % (m // 60, m % 60) if m >= 60 else "%dm" % m


def sysfs_eta(d, status):
    """Seconds left (discharging) or until full (charging), worked out from numbers the kernel already exposes."""
    def num(n):
        v = read(d + "/" + n)
        return int(v) if v.isdigit() else 0
    full = num("energy_full") or num("charge_full")
    now = num("energy_now") or num("charge_now")
    rate = num("power_now") or num("current_now")
    if not (full and rate):
        return None
    if status == "Discharging":
        return now / rate * 3600
    if status == "Charging":
        return max(full - now, 0) / rate * 3600
    return None


def devices():
    found = []
    for d in sorted(glob.glob(SYS + "/*")):
        if read(d + "/type").lower() != "battery":
            continue
        cap = read(d + "/capacity")
        if not cap.isdigit():
            continue
        name = os.path.basename(d)
        model = read(d + "/model_name")
        found.append({
            "id": name,
            "pct": min(int(cap), 100),
            "status": read(d + "/status") or "Unknown",
            "system": read(d + "/scope").lower() != "device",
            "label": model or name,
            "eta": sysfs_eta(d, read(d + "/status") or "Unknown"),
        })
    found.sort(key=lambda x: (not x["system"], x["id"]))      # laptop first, then gadgets
    return found


def upower_devices(skip_ids):
    """Wireless mouse / keyboard / headset batteries from UPower (bluetooth and friends)."""
    try:
        paths = subprocess.run(["upower", "-e"], capture_output=True, text=True, timeout=3).stdout.split()
    except (OSError, subprocess.SubprocessError):
        return []
    found = []
    for path in paths:
        if "/devices/line_power" in path or path.endswith("/DisplayDevice"):
            continue
        try:
            out = subprocess.run(["upower", "-i", path], capture_output=True, text=True, timeout=3).stdout
        except (OSError, subprocess.SubprocessError):
            continue
        info, section = {}, ""
        for line in out.splitlines():
            if ":" in line:
                k, _, v = line.partition(":")
                info.setdefault(k.strip(), v.strip())
            elif line.strip():
                section = line.strip()                      # the device type line, e.g. "mouse"
        pct = info.get("percentage", "").rstrip("%")
        if not pct.isdigit() or info.get("present", "yes") == "no":
            continue
        native = os.path.basename(info.get("native-path", ""))
        if native in skip_ids or info.get("power supply", "no") == "yes":
            continue                                        # already listed from /sys (e.g. the laptop battery)
        eta = None
        m = re.search(r"time to (?:empty|full):\s*([\d.,]+)\s*(second|minute|hour|day)", out)
        if m:
            eta = float(m.group(1).replace(",", ".")) * {"second": 1, "minute": 60, "hour": 3600, "day": 86400}[m.group(2)]
        state = {"fully-charged": "Full", "pending-charge": "Charging"}.get(info.get("state", ""), info.get("state", "unknown").capitalize())
        found.append({
            "id": native or path,
            "pct": min(int(pct), 100),
            "status": state,
            "system": False,
            "label": info.get("model") or info.get("vendor") or section or "Wireless device",
            "type": section,
            "eta": eta,
        })
    return found


def kind(dev):
    t = dev.get("type", "")
    if t in ("keyboard", "mouse"):
        return t
    if t in ("headset", "headphones", "speakers"):
        return "headset"
    if dev["system"]:
        return "battery"
    text = (dev["label"] + " " + dev["id"]).lower()
    if any(k in text for k in ("keyboard", "kbd", "keys")):
        return "keyboard"
    if any(k in text for k in ("head", "buds", "airpods", "audio")):
        return "headset"
    return "mouse"                                            # most gadgets that report a battery


def icon(dev):
    k = kind(dev)
    if k == "keyboard":
        return chr(KEYBOARD)
    if k == "headset":
        return chr(HEADSET)
    if k == "mouse":
        return chr(MOUSE)
    if dev["status"] == "Charging":
        return chr(CHARGING)
    return chr(LEVELS[dev["pct"] // 10])


def level(dev):
    if dev["status"] == "Charging" or dev["status"] == "Full":
        return "ok"
    if dev["pct"] <= CRIT:
        return "crit"
    if dev["pct"] <= LOW:
        return "low"
    return "ok"


def warn(devs):
    """One notification per device when it first falls to CRIT%; forgotten again once it is above it or charging."""
    warned = set(read(STATE).split())
    now = set()
    for d in devs:
        if level(d) == "crit":
            now.add(d["id"])
            if d["id"] not in warned:
                try:
                    subprocess.run(["notify-send", "-a", "Battery", "-u", "critical",
                                    "Low battery", "%s is at %d%%" % (d["label"], d["pct"])], check=False)
                except OSError:
                    pass
    if now != warned:
        os.makedirs(os.path.dirname(STATE), exist_ok=True)
        with open(STATE, "w") as f:
            f.write(" ".join(sorted(now)))


def main():
    sys.stdout.reconfigure(encoding="utf-8")        # waybar may run us with a plain C locale
    devs = devices()
    devs += upower_devices({d["id"] for d in devs})
    if not devs:
        print(json.dumps({"text": "", "tooltip": False}, ensure_ascii=False))
        return
    warn(devs)
    parts, tips = [], []
    for d in devs:
        lv = level(d)
        text = "%s %d%%" % (icon(d), d["pct"])
        parts.append(text if lv == "ok" else "<span foreground='%s'>%s</span>" % (COLOURS[lv], text))
        who = "Laptop" if d["system"] else d["label"]
        line = "%s: %d%% (%s)" % (who, d["pct"], d["status"].lower())
        if d.get("eta"):
            line += "  ·  %s %s" % (fmt_time(d["eta"]), "until full" if d["status"] == "Charging" else "left")
        tips.append(line)
    try:
        prof = subprocess.run(["powerprofilesctl", "get"], capture_output=True, text=True, timeout=2).stdout.strip()
        if prof:
            tips.append("")
            tips.append("Power profile: %s  (click to change)" % prof.replace("-", " ").capitalize())
    except (OSError, subprocess.SubprocessError):
        pass
    worst = "crit" if any(level(d) == "crit" for d in devs) else "low" if any(level(d) == "low" for d in devs) else "ok"
    print(json.dumps({"text": "  ".join(parts), "tooltip": "\n".join(tips), "class": worst}, ensure_ascii=False))


main()
