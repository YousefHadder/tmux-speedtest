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

# Check if provider response indicates throttling/rate limiting
is_rate_limit_error() {
    local raw="$1"
    local normalized
    normalized=$(echo "$raw" | tr '[:upper:]' '[:lower:]')

    [[ "$normalized" == *"rate limit"* || \
       "$normalized" == *"too many request"* || \
       "$normalized" == *"too many test"* || \
       "$normalized" == *"try again later"* || \
       "$normalized" == *"quota"* || \
       "$normalized" == *"http 429"* || \
       "$normalized" == *"error 429"* || \
       "$normalized" == *"429 too many"* || \
       "$normalized" == *"status code: 429"* ]]
}

# Run the actual speedtest in background
run_speedtest_background() {
    NOTIFICATIONS_ENABLED=$(get_tmux_option "@speedtest_notifications" "on")

    # Respect temporary backoff after provider throttling
    BACKOFF_REMAINING=$(get_backoff_remaining_seconds)
    if [[ "$BACKOFF_REMAINING" -gt 0 ]]; then
        if [[ "$NOTIFICATIONS_ENABLED" != "off" ]]; then
            tmux display-message "speedtest: Backoff active (${BACKOFF_REMAINING}s remaining)"
        fi
        exit 0
    fi

    # Optional minimum time between tests (survives tmux restart)
    MIN_INTERVAL_OPTION=$(get_tmux_option "@speedtest_min_interval" "0")
    MIN_INTERVAL_SECS=$(parse_time_to_seconds "$MIN_INTERVAL_OPTION")
    if [[ "$MIN_INTERVAL_SECS" -gt 0 ]]; then
        LAST_RUN_TS=$(get_last_run_timestamp)
        if [[ "$LAST_RUN_TS" -gt 0 ]]; then
            NOW_TS=$(get_current_timestamp)
            AGE_SECS=$((NOW_TS - LAST_RUN_TS))
            if [[ "$AGE_SECS" -lt "$MIN_INTERVAL_SECS" ]]; then
                REMAINING_SECS=$((MIN_INTERVAL_SECS - AGE_SECS))
                if [[ "$NOTIFICATIONS_ENABLED" != "off" ]]; then
                    tmux display-message "speedtest: Cooldown active (${REMAINING_SECS}s remaining)"
                fi
                exit 0
            fi
        fi
    fi

    # Atomically acquire lock — exit if another process won the race
    if ! acquire_lock; then
        tmux display-message "speedtest: Already running..."
        exit 0
    fi
    local stdout_file=""
    local stderr_file=""
    cleanup_run() {
        [[ -n "$stdout_file" ]] && rm -f "$stdout_file"
        [[ -n "$stderr_file" ]] && rm -f "$stderr_file"
        release_lock
    }
    trap cleanup_run EXIT

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

    if [[ "$NOTIFICATIONS_ENABLED" != "off" ]]; then
        tmux display-message "speedtest: Starting..."
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

    # Warn if explicit provider wasn't found and fallback was used
    local requested_provider
    requested_provider=$(get_tmux_option "@speedtest_provider" "auto")
    if [[ "$requested_provider" != "auto" && "$CLI_TYPE" != "$requested_provider" ]]; then
        if [[ "$NOTIFICATIONS_ENABLED" != "off" ]]; then
            tmux display-message "speedtest: '$requested_provider' not found, using $CLI_TYPE instead"
        fi
    fi

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
    local EXIT_CODE
    local ERROR_OUTPUT
    stdout_file=$(mktemp)
    stderr_file=$(mktemp)

    if command -v timeout &>/dev/null; then
        timeout "$TIMEOUT_SECS" "${cmd[@]}" > "$stdout_file" 2> "$stderr_file"
        EXIT_CODE=$?
    else
        "${cmd[@]}" > "$stdout_file" 2> "$stderr_file" &
        local child=$!
        ( sleep "$TIMEOUT_SECS" && kill "$child" 2>/dev/null ) &
        local watcher=$!
        wait "$child" 2>/dev/null
        EXIT_CODE=$?
        kill "$watcher" 2>/dev/null
        wait "$watcher" 2>/dev/null
    fi

    OUTPUT=$(cat "$stdout_file")
    ERROR_OUTPUT=$(cat "$stderr_file")

    if [[ $EXIT_CODE -ne 0 || -z "$OUTPUT" ]]; then
        if is_rate_limit_error "$ERROR_OUTPUT$OUTPUT"; then
            BACKOFF_OPTION=$(get_tmux_option "@speedtest_rate_limit_backoff" "10m")
            BACKOFF_SECS=$(parse_time_to_seconds "$BACKOFF_OPTION")
            if [[ "$BACKOFF_SECS" -gt 0 ]]; then
                set_backoff_until_timestamp "$(( $(get_current_timestamp) + BACKOFF_SECS ))"
                tmux display-message "speedtest: Rate-limited; backing off for ${BACKOFF_SECS}s"
            else
                tmux display-message "speedtest: Rate-limited by provider"
            fi
        else
            tmux display-message "speedtest: Test failed"
        fi
        sleep 2
        set_tmux_option "@speedtest_result" "$PREVIOUS_RESULT"
        tmux refresh-client -S
        exit 1
    fi

    clear_backoff_until_timestamp

    # Parse results based on CLI type
    local download upload ping_val

    local parser
    parser=$(detect_json_parser)

    if [[ "$CLI_TYPE" == "ookla" ]]; then
        # Ookla JSON: { "download": { "bandwidth": <bytes/s> }, "upload": { "bandwidth": <bytes/s> }, "ping": { "latency": <ms> } }
        if [[ "$parser" == "jq" ]]; then
            download=$(echo "$OUTPUT" | jq -r '.download.bandwidth' 2>/dev/null)
            upload=$(echo "$OUTPUT" | jq -r '.upload.bandwidth' 2>/dev/null)
            ping_val=$(echo "$OUTPUT" | jq -r '.ping.latency' 2>/dev/null)
        fi
        if [[ -z "$download" || "$download" == "null" ]]; then
            download=$(echo "$OUTPUT" | grep -oE '"bandwidth":\s*[0-9.]+' | head -1 | grep -oE '[0-9.]+')
            upload=$(echo "$OUTPUT" | grep -oE '"bandwidth":\s*[0-9.]+' | tail -1 | grep -oE '[0-9.]+')
            ping_val=$(echo "$OUTPUT" | grep -oE '"latency":\s*[0-9.]+' | head -1 | grep -oE '[0-9.]+')
        fi
    elif [[ "$CLI_TYPE" == "fast" ]]; then
        # fast-cli JSON: { "downloadSpeed": <Mbps>, "uploadSpeed": <Mbps>, "latency": <ms> }
        if [[ "$parser" == "jq" ]]; then
            download=$(echo "$OUTPUT" | jq -r '.downloadSpeed' 2>/dev/null)
            upload=$(echo "$OUTPUT" | jq -r '.uploadSpeed' 2>/dev/null)
            ping_val=$(echo "$OUTPUT" | jq -r '.latency' 2>/dev/null)
        fi
        if [[ -z "$download" || "$download" == "null" ]]; then
            download=$(echo "$OUTPUT" | grep -oE '"downloadSpeed":\s*[0-9.]+' | grep -oE '[0-9.]+')
            upload=$(echo "$OUTPUT" | grep -oE '"uploadSpeed":\s*[0-9.]+' | grep -oE '[0-9.]+')
            ping_val=$(echo "$OUTPUT" | grep -oE '"latency":\s*[0-9.]+' | grep -oE '[0-9.]+')
        fi
    elif [[ "$CLI_TYPE" == "cloudflare" ]]; then
        # cloudflare-speed-cli JSON: nested structure with download.mbps, upload.mbps, idle_latency.median_ms
        if [[ "$parser" == "jq" ]]; then
            download=$(echo "$OUTPUT" | jq -r '.download.mbps // 0' 2>/dev/null)
            upload=$(echo "$OUTPUT" | jq -r '.upload.mbps // 0' 2>/dev/null)
            ping_val=$(echo "$OUTPUT" | jq -r '.idle_latency.median_ms // 0' 2>/dev/null)
        fi
        if [[ -z "$download" || "$download" == "null" ]]; then
            download=$(echo "$OUTPUT" | grep -oE '"mbps":\s*[0-9.]+' | head -1 | grep -oE '[0-9.]+')
            upload=$(echo "$OUTPUT" | grep -oE '"mbps":\s*[0-9.]+' | tail -1 | grep -oE '[0-9.]+')
            ping_val=$(echo "$OUTPUT" | grep -oE '"median_ms":\s*[0-9.]+' | head -1 | grep -oE '[0-9.]+')
        fi
    else
        # sivel JSON: { "download": <bits/s>, "upload": <bits/s>, "ping": <ms> }
        if [[ "$parser" == "jq" ]]; then
            download=$(echo "$OUTPUT" | jq -r '.download' 2>/dev/null)
            upload=$(echo "$OUTPUT" | jq -r '.upload' 2>/dev/null)
            ping_val=$(echo "$OUTPUT" | jq -r '.ping' 2>/dev/null)
        fi
        if [[ -z "$download" || "$download" == "null" ]]; then
            download=$(echo "$OUTPUT" | grep -oE '"download":\s*[0-9.]+' | grep -oE '[0-9.]+')
            upload=$(echo "$OUTPUT" | grep -oE '"upload":\s*[0-9.]+' | grep -oE '[0-9.]+')
            ping_val=$(echo "$OUTPUT" | grep -oE '"ping":\s*[0-9.]+' | grep -oE '[0-9.]+')
        fi
    fi

    # Format values
    DOWNLOAD_FMT=$(format_speed "$download" "$CLI_TYPE")
    UPLOAD_FMT=$(format_speed "$upload" "$CLI_TYPE")
    PING_FMT=$(format_ping "$ping_val")

    # Apply color coding if enabled
    if [[ "$(get_tmux_option "@speedtest_colors" "off")" == "on" ]]; then
        local speed_good speed_bad ping_good ping_bad
        local color_good color_warn color_bad
        speed_good=$(get_tmux_option "@speedtest_threshold_good" "100")
        speed_bad=$(get_tmux_option "@speedtest_threshold_bad" "25")
        ping_good=$(get_tmux_option "@speedtest_ping_threshold_good" "30")
        ping_bad=$(get_tmux_option "@speedtest_ping_threshold_bad" "100")
        color_good=$(get_tmux_option "@speedtest_color_good" "green")
        color_warn=$(get_tmux_option "@speedtest_color_warn" "yellow")
        color_bad=$(get_tmux_option "@speedtest_color_bad" "red")

        local dl_mbps ul_mbps ping_ms
        dl_mbps=$(speed_to_mbps "$DOWNLOAD_FMT")
        ul_mbps=$(speed_to_mbps "$UPLOAD_FMT")
        ping_ms=$(ping_to_ms "$PING_FMT")

        local dl_color ul_color ping_color
        dl_color=$(get_speed_color "$dl_mbps" "$speed_good" "$speed_bad" "$color_good" "$color_warn" "$color_bad")
        ul_color=$(get_speed_color "$ul_mbps" "$speed_good" "$speed_bad" "$color_good" "$color_warn" "$color_bad")
        ping_color=$(get_ping_color "$ping_ms" "$ping_good" "$ping_bad" "$color_good" "$color_warn" "$color_bad")

        DOWNLOAD_FMT=$(colorize_text "$DOWNLOAD_FMT" "$dl_color")
        UPLOAD_FMT=$(colorize_text "$UPLOAD_FMT" "$ul_color")
        PING_FMT=$(colorize_text "$PING_FMT" "$ping_color")
    fi

    # Build result string
    RESULT=$(build_result_string "$FORMAT" "$DOWNLOAD_FMT" "$UPLOAD_FMT" "$PING_FMT")

    # Update status bar
    set_tmux_option "@speedtest_result" "$RESULT"
    persist_last_run_timestamp "$(get_current_timestamp)"
    tmux refresh-client -S

    # Store full results for detail popup
    set_tmux_option "@speedtest_result_json" "$OUTPUT"
    set_tmux_option "@speedtest_result_timestamp" "$(date +%s)"
    set_tmux_option "@speedtest_result_provider" "$CLI_TYPE"

    # Show notification if not disabled
    if [[ "$NOTIFICATIONS_ENABLED" != "off" ]]; then
        tmux display-message "speedtest: Done - $RESULT"
    fi
}

# Launch in background and detach
run_speedtest_background &
disown
