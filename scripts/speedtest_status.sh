#!/usr/bin/env bash

# This script is called by tmux to interpolate #{speedtest_result}
# It simply returns the current value of the @speedtest_result option

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

ICON_IDLE=$(get_tmux_option "@speedtest_icon_idle" "—")
RESULT=$(get_tmux_option "@speedtest_result" "")

# Check if result has expired
if [[ -n "$RESULT" && "$RESULT" != "$ICON_IDLE" ]] && is_result_expired; then
    set_tmux_option "@speedtest_result" "$ICON_IDLE"
    set_tmux_option "@speedtest_last_run" "0"
    RESULT="$ICON_IDLE"
fi

# If result is empty, check if we should show idle icon
if [[ -z "$RESULT" ]]; then
    # If idle icon is not empty, show it (persistent mode)
    # If idle icon IS empty, output nothing (auto-hide mode)
    if [[ -n "$ICON_IDLE" ]]; then
         echo "$ICON_IDLE"
    else
         printf ""
    fi
elif [[ "$RESULT" == "$ICON_IDLE" ]]; then
    # If result explicitly matches idle icon
    if [[ -n "$ICON_IDLE" ]]; then
         echo "$ICON_IDLE"
    else
         printf ""
    fi
else
    # Active result
    # Add a leading space for better visual separation
    echo " $RESULT"
fi
