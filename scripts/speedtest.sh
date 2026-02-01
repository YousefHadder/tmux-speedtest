#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

# Configuration
FORMAT=$(get_tmux_option "@speedtest_format" "↓ #{download} ↑ #{upload} #{ping}")
ICON_RUNNING=$(get_tmux_option "@speedtest_icon_running" "⏳")
ICON_IDLE=$(get_tmux_option "@speedtest_icon_idle" "")
SERVER=$(get_tmux_option "@speedtest_server" "")

# Store current result (to restore on failure)
PREVIOUS_RESULT=$(get_tmux_option "@speedtest_result" "$ICON_IDLE")

# Show running indicator
set_tmux_option "@speedtest_result" "$ICON_RUNNING Testing..."
tmux refresh-client -S

# Detect CLI
CLI=$(detect_speedtest_cli)

if [[ "$CLI" == "none" ]]; then
    tmux display-message "speedtest: No CLI found (install speedtest or speedtest-cli)"
    # Revert to previous result after short delay
    sleep 2
    set_tmux_option "@speedtest_result" "$PREVIOUS_RESULT"
    tmux refresh-client -S
    exit 1
fi

# Build command based on CLI type
run_speedtest() {
    local cli="$1"
    local server_id="$2"

    if [[ "$cli" == "ookla" ]]; then
        local cmd="speedtest --format=json --accept-license --accept-gdpr"
        if [[ -n "$server_id" ]]; then
            cmd="$cmd --server-id=$server_id"
        fi
        eval "$cmd" 2>/dev/null
    else
        local cmd="speedtest-cli --json"
        if [[ -n "$server_id" ]]; then
            cmd="$cmd --server=$server_id"
        fi
        eval "$cmd" 2>/dev/null
    fi
}

# Run speedtest and capture output
OUTPUT=$(run_speedtest "$CLI" "$SERVER")
EXIT_CODE=$?

if [[ $EXIT_CODE -ne 0 || -z "$OUTPUT" ]]; then
    tmux display-message "speedtest: Test failed"
    sleep 2
    set_tmux_option "@speedtest_result" "$PREVIOUS_RESULT"
    tmux refresh-client -S
    exit 1
fi

# Parse results based on CLI type
parse_results() {
    local cli="$1"
    local json="$2"

    local download upload ping_val

    if [[ "$cli" == "ookla" ]]; then
        # Ookla JSON structure:
        # { "download": { "bandwidth": <bytes/s> }, "upload": { "bandwidth": <bytes/s> }, "ping": { "latency": <ms> } }
        download=$(echo "$json" | grep -o '"download"[^}]*}' | grep -o '"bandwidth":[0-9.]*' | cut -d: -f2)
        upload=$(echo "$json" | grep -o '"upload"[^}]*}' | grep -o '"bandwidth":[0-9.]*' | cut -d: -f2)
        ping_val=$(echo "$json" | grep -o '"ping"[^}]*}' | grep -o '"latency":[0-9.]*' | cut -d: -f2)
    else
        # sivel JSON structure:
        # { "download": <bits/s>, "upload": <bits/s>, "ping": <ms> }
        download=$(echo "$json" | grep -o '"download":[0-9.]*' | cut -d: -f2)
        upload=$(echo "$json" | grep -o '"upload":[0-9.]*' | cut -d: -f2)
        ping_val=$(echo "$json" | grep -o '"ping":[0-9.]*' | cut -d: -f2)
    fi

    echo "$download $upload $ping_val"
}

# Parse the output
read -r DOWNLOAD UPLOAD PING <<< "$(parse_results "$CLI" "$OUTPUT")"

# Format values
DOWNLOAD_FMT=$(format_speed "$DOWNLOAD" "$CLI")
UPLOAD_FMT=$(format_speed "$UPLOAD" "$CLI")
PING_FMT=$(format_ping "$PING")

# Build result string
RESULT=$(build_result_string "$FORMAT" "$DOWNLOAD_FMT" "$UPLOAD_FMT" "$PING_FMT")

# Update status bar
set_tmux_option "@speedtest_result" "$RESULT"
tmux refresh-client -S

tmux display-message "speedtest: Done"
