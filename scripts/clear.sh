#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

# Get user configuration
ICON_IDLE=$(get_tmux_option "@speedtest_icon_idle" "—")

# Cancel running test if exists
LOCK_FILE="/tmp/tmux-speedtest.lock"
if [[ -f "$LOCK_FILE" ]]; then
    PID=$(cat "$LOCK_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        kill "$PID"
    fi
    rm -f "$LOCK_FILE"
fi

# Reset the result option to the idle icon (or empty string)
set_tmux_option "@speedtest_result" "$ICON_IDLE"

# Refresh status line
tmux refresh-client -S

if [[ "$(get_tmux_option "@speedtest_notifications" "on")" != "off" ]]; then
    tmux display-message "speedtest: Results cleared"
fi
