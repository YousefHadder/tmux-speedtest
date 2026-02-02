#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_DIR/scripts/helpers.sh"

# Get user configuration
KEY=$(get_tmux_option "@speedtest_key" "o")
CLEAR_KEY=$(get_tmux_option "@speedtest_clear_key" "O")

# Set up key binding (use -b for background/non-blocking execution)
tmux bind-key "$KEY" run-shell -b "$CURRENT_DIR/scripts/speedtest.sh"
tmux bind-key "$CLEAR_KEY" run-shell -b "$CURRENT_DIR/scripts/clear.sh"

# Set up status bar interpolation
# This allows users to use #{speedtest_result} in their status bar
# Default to empty string so it doesn't show initially if auto-hide is desired
tmux set-option -gq @speedtest_result "$(get_tmux_option "@speedtest_icon_idle" "—")"

# Register the format interpolation
# tmux will call the script whenever it needs to render #{speedtest_result}
INTERPOLATION="#{speedtest_result}"
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
