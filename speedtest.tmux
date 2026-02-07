#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_DIR/scripts/helpers.sh"

# Get user configuration
KEY=$(get_tmux_option "@speedtest_key" "o")
CLEAR_KEY=$(get_tmux_option "@speedtest_clear_key" "O")
DETAIL_KEY=$(get_tmux_option "@speedtest_detail_key" "d")

# Set up key binding (use -b for background/non-blocking execution)
tmux bind-key "$KEY" run-shell -b "$CURRENT_DIR/scripts/speedtest.sh"
tmux bind-key "$CLEAR_KEY" run-shell -b "$CURRENT_DIR/scripts/clear.sh"
tmux bind-key "$DETAIL_KEY" run-shell -b "$CURRENT_DIR/scripts/popup_detail.sh"

# Set up status bar interpolation
# This allows users to use #{speedtest_result} in their status bar
# Default to empty string so it doesn't show initially if auto-hide is desired
tmux set-option -gq @speedtest_result "$(get_tmux_option "@speedtest_icon_idle" "—")"

# Set up status interpolation script path
STATUS_SCRIPT="$CURRENT_DIR/scripts/speedtest_status.sh"

# Update status-right and status-left to interpolate our variable
# We use a tmux format that calls our script
update_status_interpolation() {
    local status_option="$1"
    local current_value
    current_value=$(tmux show-option -gqv "$status_option")

    if [[ "$current_value" == *"#{speedtest_result}"* ]]; then
        # Replace #{speedtest_result} with a script call that returns the value
        local new_value="${current_value//\#\{speedtest_result\}/#($STATUS_SCRIPT)}"
        tmux set-option -gq "$status_option" "$new_value"
    fi
}

update_status_interpolation "status-right"
update_status_interpolation "status-left"

# Run on tmux start if enabled
if [[ "$(get_tmux_option "@speedtest_run_on_start" "off")" == "on" ]]; then
    "$CURRENT_DIR/scripts/speedtest.sh" &
    disown
fi

# Start interval runner if configured
INTERVAL=$(get_tmux_option "@speedtest_interval" "0")
INTERVAL_SECONDS=$(parse_time_to_seconds "$INTERVAL")

if [[ "$INTERVAL_SECONDS" -gt 0 ]]; then
    INTERVAL_LOCK="/tmp/tmux-speedtest-interval.lock"

    # Check if interval runner is already active (prevents duplicates on tmux source)
    start_runner=true
    if [[ -f "$INTERVAL_LOCK" ]]; then
        runner_pid=$(cat "$INTERVAL_LOCK" 2>/dev/null)
        if [[ "$runner_pid" =~ ^[0-9]+$ ]] && kill -0 "$runner_pid" 2>/dev/null; then
            start_runner=false
        else
            rm -f "$INTERVAL_LOCK"
        fi
    fi

    if [[ "$start_runner" == "true" ]]; then
        "$CURRENT_DIR/scripts/interval_runner.sh" &
        disown
    fi
fi
