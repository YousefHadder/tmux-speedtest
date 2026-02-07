#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

INTERVAL_LOCK="/tmp/tmux-speedtest-interval.lock"

# Clean up lock file on exit
cleanup() {
    rm -f "$INTERVAL_LOCK"
}
trap cleanup EXIT

# Check if already running
if [[ -f "$INTERVAL_LOCK" ]]; then
    local_pid=$(cat "$INTERVAL_LOCK" 2>/dev/null)
    if [[ "$local_pid" =~ ^[0-9]+$ ]] && kill -0 "$local_pid" 2>/dev/null; then
        exit 0
    fi
fi

# Write our PID
echo "${BASHPID:-$$}" > "$INTERVAL_LOCK"

# Main loop
while true; do
    INTERVAL=$(get_tmux_option "@speedtest_interval" "0")
    INTERVAL_SECONDS=$(parse_time_to_seconds "$INTERVAL")

    # Exit if disabled
    if [[ "$INTERVAL_SECONDS" -eq 0 ]]; then
        exit 0
    fi

    # Sleep first (avoids duplicating run_on_start trigger)
    sleep "$INTERVAL_SECONDS"

    # Re-check interval in case user disabled it during sleep
    INTERVAL=$(get_tmux_option "@speedtest_interval" "0")
    INTERVAL_SECONDS=$(parse_time_to_seconds "$INTERVAL")
    if [[ "$INTERVAL_SECONDS" -eq 0 ]]; then
        exit 0
    fi

    # Trigger speedtest (speedtest.sh handles its own lock)
    "$CURRENT_DIR/speedtest.sh" &
    disown
done
