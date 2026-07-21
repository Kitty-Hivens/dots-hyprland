#!/usr/bin/env bash
# xdg-desktop-portal-hyprland custom_picker_binary.
#
# xdph runs this synchronously, sets XDPH_WINDOW_SHARING_LIST in the env, passes
# --allow-token when screencopy:allow_token_by_default is on, and reads one line
# of the form
#     [SELECTION]{r|}/{screen:NAME | window:ID | region:NAME@x,y,w,h}
# from stdout (no marker on stdout == the user cancelled).
#
# Quickshell is a long-running daemon, so we hand the request to the running shell
# over IPC and block on a FIFO until it writes back the selection payload.

allow_token=0
[ "$1" = "--allow-token" ] && allow_token=1

fifo="$(mktemp -u --tmpdir "xdph-share-picker.XXXXXX")"
mkfifo "$fifo" || exit 1
trap 'rm -f "$fifo"' EXIT

# Fire-and-return: the handler opens the panel and returns immediately.
# -c ii selects the shell instance; without it qs looks for a "default" config and bails.
if ! qs -c ii ipc call screenShare open "$allow_token" "$fifo" "$XDPH_WINDOW_SHARING_LIST" >/dev/null 2>&1; then
    exit 1
fi

# Block until the shell writes the payload (or empty on cancel). The timeout keeps a
# dead/hung shell from wedging xdph forever.
payload="$(timeout 300 cat "$fifo")"

[ -n "$payload" ] && printf '[SELECTION]%s\n' "$payload"
