#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

# Get idle icon to reset to
# If user sets this to "", it effectively enables auto-hide
ICON_IDLE=$(get_tmux_option "@speedtest_icon_idle" "—")

# Reset the result option to the idle icon (or empty string)
set_tmux_option "@speedtest_result" "$ICON_IDLE"

# Refresh status line
tmux refresh-client -S

if [[ "$(get_tmux_option "@speedtest_notifications" "on")" != "off" ]]; then
    tmux display-message "speedtest: Results cleared"
fi
