#!/usr/bin/env python3
"""Rewrite the generated output region of the Hyprland monitors config.

Only the block between the markers is replaced. Everything else, in particular
the docking handlers that decide whether the laptop panel is on, is preserved:
regenerating the whole file would delete them and leave an undocked boot with no
display.

Usage: monitors_write.py <config path> <plan json>
"""

import json
import os
import shutil
import sys

BEGIN = "-- >>> yukiui:outputs"
END = "-- <<< yukiui:outputs"

HEADER = [
    "-- Output settings live in the marked region below and are written by the YukiUI",
    "-- system settings Displays page. Saving there regenerates only that region;",
    "-- anything outside it, including the docking rules, is left alone.",
    "",
]


def format_scale(value):
    value = float(value)
    return str(int(value)) if value.is_integer() else str(value)


def monitor_line(entry, disabled=False):
    name = entry["name"]
    if disabled:
        # Geometry is written even for an output that is off. Hyprland validates
        # the layout across every output it knows about, disabled ones included,
        # and warns about overlaps; the warning then fires on each layout
        # recalculation, which happens on every fullscreen transition.
        return (
            f'hl.monitor({{ output = "{name}", '
            f'mode = "{entry["width"]}x{entry["height"]}@{round(float(entry["refreshRate"]))}", '
            f'position = "{entry["x"]}x{entry["y"]}", '
            f'scale = {format_scale(entry.get("scale", 1))}, disabled = true }})'
        )

    return (
        f'hl.monitor({{ output = "{name}", '
        f'mode = "{entry["width"]}x{entry["height"]}@{round(float(entry["refreshRate"]))}", '
        f'position = "{entry["x"]}x{entry["y"]}", '
        f'scale = {format_scale(entry.get("scale", 1))}, '
        f'transform = {int(entry.get("transform", 0))}, '
        + (f'vrr = {1 if entry.get("vrr") else 0}, ' if entry.get("vrrOverride") else "")
        + 
        f'bitdepth = {10 if int(entry.get("bitdepth", 8)) == 10 else 8}, '
        f'cm = "{entry.get("cm") or "srgb"}", '
        f'sdrbrightness = {float(entry.get("sdrBrightness", 1.0)):g}, '
        f'sdrsaturation = {float(entry.get("sdrSaturation", 1.0)):g} }})'
    )


def park_disabled(plan):
    """Move switched-off outputs clear of the active ones.

    Their stored position is usually wherever they sat while in use, which now
    overlaps whatever took their place. Hyprland counts that as a broken layout
    and complains every time it recalculates.
    """
    active = [e for e in plan if e.get("enabled", True)]
    off = [e for e in plan if not e.get("enabled", True)]
    if not active or not off:
        return off

    left = min(int(e["x"]) for e in active)
    parked = []
    for entry in off:
        entry = dict(entry)
        # Logical width, so a rotated panel is parked by the space it actually
        # takes. Using the raw width leaves a portrait display overlapping the
        # active one, which is exactly what parking is meant to avoid.
        rotated = int(entry.get("transform", 0)) % 2 == 1
        pixels = int(entry["height"] if rotated else entry["width"])
        width = pixels / (float(entry.get("scale", 1)) or 1)
        left -= int(width)
        entry["x"], entry["y"] = left, 0
        parked.append(entry)
    return parked


def replace_region(lines, generated):
    # Matched after stripping: a stray trailing space would otherwise hide the
    # markers, and the file would get a second region while the stale one below
    # kept overriding it.
    stripped = [line.strip() for line in lines]
    try:
        start = stripped.index(BEGIN)
        end = stripped.index(END)
    except ValueError:
        # No markers yet. The region goes last: in Lua the final call for an
        # output wins, so placing it first would let pre-existing lines override
        # everything written here, and the page would report a save that quietly
        # does nothing. Existing content is kept verbatim rather than filtered.
        body = list(lines)
        while body and not body[-1].strip():
            body.pop()
        return (body + [""] if body else []) + HEADER + [BEGIN] + generated + [END]

    if end < start:
        raise SystemExit("markers are out of order")
    return lines[:start + 1] + generated + lines[end:]


def main():
    if len(sys.argv) != 3:
        print("usage: monitors_write.py <config> <plan json>", file=sys.stderr)
        return 2

    path, plan_json = sys.argv[1], sys.argv[2]
    plan = json.loads(plan_json)
    if not plan:
        print("empty plan", file=sys.stderr)
        return 2

    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as handle:
            lines = handle.read().split("\n")
        shutil.copy2(path, path + ".bak")
    else:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        lines = []

    generated = [monitor_line(entry) for entry in plan if entry.get("enabled", True)]
    generated += [monitor_line(entry, disabled=True) for entry in park_disabled(plan)]
    result = replace_region(lines, generated)

    temp = path + ".tmp"
    with open(temp, "w", encoding="utf-8") as handle:
        handle.write("\n".join(result).rstrip("\n") + "\n")
    os.replace(temp, path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
