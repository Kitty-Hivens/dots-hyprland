#!/usr/bin/env bash
# File-manager launcher for the Win+E bind.
#
# Same "first available from the list" behaviour as launch_first_available.sh,
# with wedge recovery for nautilus. Nautilus is single-instance over D-Bus, so
# a busy or crashed primary makes every re-launch block on that primary's main
# loop -- which is exactly the "Win+E hangs for a long time" symptom. We open
# the window through a bounded D-Bus call; if it does not answer in time the
# instance is stuck, so we tear it down and start a clean one.

set -u

FM_URI="file://$HOME"
FM_TIMEOUT=8

# Opens/presents a window through the running (or D-Bus-activated) nautilus.
# Returns non-zero if the primary does not answer within FM_TIMEOUT, i.e. it is
# wedged -- a healthy instance replies in well under a second even while its
# background threads are busy generating thumbnails.
nautilus_show() {
    gdbus call --session --timeout "$FM_TIMEOUT" \
        --dest org.freedesktop.FileManager1 \
        --object-path /org/freedesktop/FileManager1 \
        --method org.freedesktop.FileManager1.ShowFolders \
        "['$FM_URI']" "" >/dev/null 2>&1
}

open_nautilus() {
    # ShowFolders both D-Bus-activates a cold nautilus and reuses a warm one,
    # so the happy path is a single bounded call.
    nautilus_show && return 0

    # Stuck or half-dead primary: it still owns the bus name and blocks every
    # new window, so remove it before starting fresh.
    pkill -x nautilus 2>/dev/null
    for _ in $(seq 1 10); do
        pgrep -x nautilus >/dev/null 2>&1 || break
        sleep 0.2
    done
    pgrep -x nautilus >/dev/null 2>&1 && pkill -9 -x nautilus 2>/dev/null

    # Re-activate via the bus; fall back to a direct spawn if that still fails.
    nautilus_show && return 0
    setsid -f nautilus >/dev/null 2>&1
}

for cmd in "$@"; do
    [[ -z "$cmd" ]] && continue
    eval "command -v ${cmd%% *}" >/dev/null 2>&1 || continue
    if [[ "${cmd%% *}" == "nautilus" ]]; then
        open_nautilus
    else
        eval "$cmd" &
    fi
    exit 0
done
