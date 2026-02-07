#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

# Get user configuration
ICON_IDLE=$(get_tmux_option "@speedtest_icon_idle" "—")

# Cancel running test if exists
if [[ -f "$LOCK_FILE" ]]; then
    PID=$(cat "$LOCK_FILE" 2>/dev/null)
    if [[ "$PID" =~ ^[0-9]+$ ]] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null
    fi
    release_lock
fi

# Stop interval runner if active
INTERVAL_LOCK="/tmp/tmux-speedtest-interval.lock"
if [[ -f "$INTERVAL_LOCK" ]]; then
    RUNNER_PID=$(cat "$INTERVAL_LOCK" 2>/dev/null)
    if [[ "$RUNNER_PID" =~ ^[0-9]+$ ]] && kill -0 "$RUNNER_PID" 2>/dev/null; then
        kill "$RUNNER_PID" 2>/dev/null
    fi
    rm -f "$INTERVAL_LOCK"
fi

# Reset the result option to the idle icon (or empty string)
set_tmux_option "@speedtest_result" "$ICON_IDLE"
set_tmux_option "@speedtest_last_run" "0"

# Clear stored detail data
set_tmux_option "@speedtest_result_json" ""
set_tmux_option "@speedtest_result_timestamp" ""
set_tmux_option "@speedtest_result_provider" ""

# Refresh status line
tmux refresh-client -S

if [[ "$(get_tmux_option "@speedtest_notifications" "on")" != "off" ]]; then
    tmux display-message "speedtest: Results cleared"
fi
