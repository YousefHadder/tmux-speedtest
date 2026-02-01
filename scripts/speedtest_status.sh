#!/usr/bin/env bash

# This script is called by tmux to interpolate #{speedtest_result}
# It simply returns the current value of the @speedtest_result option

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

ICON_IDLE=$(get_tmux_option "@speedtest_icon_idle" "")
RESULT=$(get_tmux_option "@speedtest_result" "$ICON_IDLE")

echo "$RESULT"
