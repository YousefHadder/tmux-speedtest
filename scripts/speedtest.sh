#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

# Check if already running (prevent multiple concurrent tests)
if [[ -f "$LOCK_FILE" ]]; then
    if ! is_lock_stale; then
        tmux display-message "speedtest: Already running..."
        exit 0
    fi
    release_lock
fi

# Run the actual speedtest in background
run_speedtest_background() {
    # Write PID to lock file
    acquire_lock
    trap 'release_lock' EXIT

    # Configuration
    FORMAT=$(get_tmux_option "@speedtest_format" "↓ #{download} ↑ #{upload} #{ping}")
    ICON_RUNNING=$(get_tmux_option "@speedtest_icon_running" "⏳")
    ICON_IDLE=$(get_tmux_option "@speedtest_icon_idle" "—")
    SERVER=$(get_tmux_option "@speedtest_server" "")

    # Store current result (to restore on failure)
    # If currently hidden (empty), use idle icon as fallback
    CURRENT_VAL=$(get_tmux_option "@speedtest_result" "")
    if [[ -z "$CURRENT_VAL" ]]; then
        PREVIOUS_RESULT="$ICON_IDLE"
    else
        PREVIOUS_RESULT="$CURRENT_VAL"
    fi

    # Show running indicator
    set_tmux_option "@speedtest_result" "$ICON_RUNNING Testing..."
    tmux refresh-client -S

    # Detect CLI - returns "type:command" (e.g., "ookla:/opt/homebrew/opt/speedtest/bin/speedtest")
    CLI_RESULT=$(detect_speedtest_cli)

    if [[ "$CLI_RESULT" == "none" ]]; then
        tmux display-message "speedtest: No CLI found (install speedtest, speedtest-cli, or fast-cli)"
        sleep 2
        set_tmux_option "@speedtest_result" "$PREVIOUS_RESULT"
        tmux refresh-client -S
        exit 1
    fi

    # Parse CLI type and command
    CLI_TYPE="${CLI_RESULT%%:*}"
    CLI_CMD="${CLI_RESULT#*:}"

    # Timeout for CLI execution (prevents hung tests)
    TIMEOUT_SECS=$(get_tmux_option "@speedtest_timeout" "120")
    if ! [[ "$TIMEOUT_SECS" =~ ^[0-9]+$ ]]; then
        TIMEOUT_SECS=120
    fi

    # Run speedtest based on CLI type
    local cmd=()
    if [[ "$CLI_TYPE" == "ookla" ]]; then
        cmd=( "$CLI_CMD" --format=json --accept-license --accept-gdpr )
        if [[ -n "$SERVER" ]]; then
            cmd+=( --server-id="$SERVER" )
        fi
    elif [[ "$CLI_TYPE" == "fast" ]]; then
        # fast-cli (Netflix fast.com)
        cmd=( "$CLI_CMD" --json --upload )
    elif [[ "$CLI_TYPE" == "cloudflare" ]]; then
        # cloudflare-speed-cli
        cmd=( "$CLI_CMD" --json )
    else
        # sivel speedtest-cli
        cmd=( "$CLI_CMD" --json )
        if [[ -n "$SERVER" ]]; then
            cmd+=( --server="$SERVER" )
        fi
    fi

    # Execute with timeout — try coreutils timeout first, fall back to bg+sleep+kill
    if command -v timeout &>/dev/null; then
        OUTPUT=$(timeout "$TIMEOUT_SECS" "${cmd[@]}" 2>/dev/null)
    else
        local tmpfile
        tmpfile=$(mktemp)
        "${cmd[@]}" > "$tmpfile" 2>/dev/null &
        local child=$!
        ( sleep "$TIMEOUT_SECS" && kill "$child" 2>/dev/null ) &
        local watcher=$!
        wait "$child" 2>/dev/null
        local child_exit=$?
        if [[ $child_exit -eq 0 ]]; then
            OUTPUT=$(cat "$tmpfile")
        else
            OUTPUT=""
        fi
        kill "$watcher" 2>/dev/null
        wait "$watcher" 2>/dev/null
        rm -f "$tmpfile"
    fi
    EXIT_CODE=$?

    if [[ $EXIT_CODE -ne 0 || -z "$OUTPUT" ]]; then
        tmux display-message "speedtest: Test failed"
        sleep 2
        set_tmux_option "@speedtest_result" "$PREVIOUS_RESULT"
        tmux refresh-client -S
        exit 1
    fi

    # Parse results based on CLI type
    local download upload ping_val

    if [[ "$CLI_TYPE" == "ookla" ]]; then
        # Ookla JSON structure:
        # { "download": { "bandwidth": <bytes/s> }, "upload": { "bandwidth": <bytes/s> }, "ping": { "latency": <ms> } }
        download=$(echo "$OUTPUT" | grep -oE '"bandwidth":\s*[0-9.]+' | head -1 | grep -oE '[0-9.]+')
        upload=$(echo "$OUTPUT" | grep -oE '"bandwidth":\s*[0-9.]+' | tail -1 | grep -oE '[0-9.]+')
        ping_val=$(echo "$OUTPUT" | grep -oE '"latency":\s*[0-9.]+' | head -1 | grep -oE '[0-9.]+')
    elif [[ "$CLI_TYPE" == "fast" ]]; then
        # fast-cli JSON structure:
        # { "downloadSpeed": <Mbps>, "uploadSpeed": <Mbps>, "latency": <ms>, ... }
        download=$(echo "$OUTPUT" | grep -oE '"downloadSpeed":\s*[0-9.]+' | grep -oE '[0-9.]+')
        upload=$(echo "$OUTPUT" | grep -oE '"uploadSpeed":\s*[0-9.]+' | grep -oE '[0-9.]+')
        ping_val=$(echo "$OUTPUT" | grep -oE '"latency":\s*[0-9.]+' | grep -oE '[0-9.]+')
    elif [[ "$CLI_TYPE" == "cloudflare" ]]; then
        # cloudflare-speed-cli JSON structure:
        # Use python for robust JSON parsing
        local PYTHON_CMD=""
        if command -v python3 &>/dev/null; then
             PYTHON_CMD="python3"
        elif command -v python &>/dev/null; then
             PYTHON_CMD="python"
        fi

        if [[ -n "$PYTHON_CMD" ]]; then
            # Use '<<< "$OUTPUT"' to pass string to stdin, avoiding echo pipe issues or content display
            download=$($PYTHON_CMD -c "import sys, json; print(json.load(sys.stdin).get('download', {}).get('mbps', 0))" <<< "$OUTPUT")
            upload=$($PYTHON_CMD -c "import sys, json; print(json.load(sys.stdin).get('upload', {}).get('mbps', 0))" <<< "$OUTPUT")
            ping_val=$($PYTHON_CMD -c "import sys, json; print(json.load(sys.stdin).get('idle_latency', {}).get('median_ms', 0))" <<< "$OUTPUT")
        else
            # Fallback to grep if no python (less robust)
            download=$(echo "$OUTPUT" | grep -oE '"mbps":\s*[0-9.]+' | head -1 | grep -oE '[0-9.]+')
            upload=$(echo "$OUTPUT" | grep -oE '"mbps":\s*[0-9.]+' | tail -1 | grep -oE '[0-9.]+')
            ping_val=$(echo "$OUTPUT" | grep -oE '"median_ms":\s*[0-9.]+' | head -1 | grep -oE '[0-9.]+')
        fi
    else
        # sivel JSON structure:
        # { "download": <bits/s>, "upload": <bits/s>, "ping": <ms> }
        download=$(echo "$OUTPUT" | grep -oE '"download":\s*[0-9.]+' | grep -oE '[0-9.]+')
        upload=$(echo "$OUTPUT" | grep -oE '"upload":\s*[0-9.]+' | grep -oE '[0-9.]+')
        ping_val=$(echo "$OUTPUT" | grep -oE '"ping":\s*[0-9.]+' | grep -oE '[0-9.]+')
    fi

    # Format values
    DOWNLOAD_FMT=$(format_speed "$download" "$CLI_TYPE")
    UPLOAD_FMT=$(format_speed "$upload" "$CLI_TYPE")
    PING_FMT=$(format_ping "$ping_val")

    # Build result string
    RESULT=$(build_result_string "$FORMAT" "$DOWNLOAD_FMT" "$UPLOAD_FMT" "$PING_FMT")

    # Update status bar
    set_tmux_option "@speedtest_result" "$RESULT"
    set_tmux_option "@speedtest_last_run" "$(get_current_timestamp)"
    tmux refresh-client -S

    # Show notification if not disabled
    if [[ "$(get_tmux_option "@speedtest_notifications" "on")" != "off" ]]; then
        tmux display-message "speedtest: Done - $RESULT"
    fi
}

# Launch in background and detach
run_speedtest_background &
disown

if [[ "$(get_tmux_option "@speedtest_notifications" "on")" != "off" ]]; then
    tmux display-message "speedtest: Starting..."
fi
