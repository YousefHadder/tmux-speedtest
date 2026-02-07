#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

# Check if a test is already running
if [[ -f "$LOCK_FILE" ]]; then
    if ! is_lock_stale; then
        tmux display-message "speedtest: Test already running..."
        exit 0
    fi
    release_lock
fi

run_comparison() {
    acquire_lock
    trap 'release_lock' EXIT

    # Detect all available providers
    local PROVIDERS=()
    while IFS= read -r line; do
        PROVIDERS+=("$line")
    done < <(detect_all_speedtest_clis)

    if [[ ${#PROVIDERS[@]} -eq 0 ]]; then
        tmux display-message "speedtest: No CLI tools found"
        exit 1
    fi

    if [[ ${#PROVIDERS[@]} -lt 2 ]]; then
        tmux display-message "speedtest: Only one provider available, no comparison needed"
        exit 0
    fi

    tmux display-message "speedtest: Comparing ${#PROVIDERS[@]} providers..."

    TIMEOUT_SECS=$(get_tmux_option "@speedtest_timeout" "120")
    if ! [[ "$TIMEOUT_SECS" =~ ^[0-9]+$ ]]; then
        TIMEOUT_SECS=120
    fi

    local results_file
    results_file=$(mktemp)

    # Header
    cat > "$results_file" <<HEADER

  Provider Comparison - $(date "+%Y-%m-%d %H:%M:%S")
  ==================================================

  Provider       Download      Upload        Ping
  --------------------------------------------------
HEADER

    # Test each provider sequentially
    local provider_info cli_type cli_cmd
    for provider_info in "${PROVIDERS[@]}"; do
        cli_type="${provider_info%%:*}"
        cli_cmd="${provider_info#*:}"

        tmux display-message "speedtest: Testing $cli_type..."

        # Build command
        local cmd=()
        case "$cli_type" in
            ookla)      cmd=( "$cli_cmd" --format=json --accept-license --accept-gdpr ) ;;
            fast)       cmd=( "$cli_cmd" --json --upload ) ;;
            cloudflare) cmd=( "$cli_cmd" --json ) ;;
            sivel|*)    cmd=( "$cli_cmd" --json ) ;;
        esac

        # Execute with timeout
        local output=""
        if command -v timeout &>/dev/null; then
            output=$(timeout "$TIMEOUT_SECS" "${cmd[@]}" 2>/dev/null) || true
        else
            local tmpfile
            tmpfile=$(mktemp)
            "${cmd[@]}" > "$tmpfile" 2>/dev/null &
            local child=$!
            ( sleep "$TIMEOUT_SECS" && kill "$child" 2>/dev/null ) &
            local watcher=$!
            wait "$child" 2>/dev/null && output=$(cat "$tmpfile")
            kill "$watcher" 2>/dev/null
            wait "$watcher" 2>/dev/null
            rm -f "$tmpfile"
        fi

        # Parse results
        local download="" upload="" ping_val=""
        if [[ -n "$output" ]]; then
            case "$cli_type" in
                ookla)
                    download=$(extract_json_field "$output" '.download.bandwidth' '"bandwidth":\s*[0-9.]+')
                    upload=$(extract_json_field "$output" '.upload.bandwidth' '"bandwidth":\s*[0-9.]+')
                    ping_val=$(extract_json_field "$output" '.ping.latency' '"latency":\s*[0-9.]+')
                    ;;
                fast)
                    download=$(extract_json_field "$output" '.downloadSpeed' '"downloadSpeed":\s*[0-9.]+')
                    upload=$(extract_json_field "$output" '.uploadSpeed' '"uploadSpeed":\s*[0-9.]+')
                    ping_val=$(extract_json_field "$output" '.latency' '"latency":\s*[0-9.]+')
                    ;;
                cloudflare)
                    download=$(extract_json_field "$output" '.download.mbps' '"mbps":\s*[0-9.]+')
                    upload=$(extract_json_field "$output" '.upload.mbps' '"mbps":\s*[0-9.]+')
                    ping_val=$(extract_json_field "$output" '.idle_latency.median_ms' '"median_ms":\s*[0-9.]+')
                    ;;
                sivel|*)
                    download=$(extract_json_field "$output" '.download' '"download":\s*[0-9.]+')
                    upload=$(extract_json_field "$output" '.upload' '"upload":\s*[0-9.]+')
                    ping_val=$(extract_json_field "$output" '.ping' '"ping":\s*[0-9.]+')
                    ;;
            esac
        fi

        # Format
        local dl_fmt ul_fmt ping_fmt
        dl_fmt=$(format_speed "$download" "$cli_type")
        ul_fmt=$(format_speed "$upload" "$cli_type")
        ping_fmt=$(format_ping "$ping_val")

        printf "  %-14s %-13s %-13s %s\n" "$cli_type" "$dl_fmt" "$ul_fmt" "$ping_fmt" >> "$results_file"
    done

    cat >> "$results_file" <<FOOTER

  ==================================================
  Press any key to close

FOOTER

    # Display results
    local height=$(( ${#PROVIDERS[@]} + 12 ))
    if supports_popup; then
        tmux display-popup -E -w 60 -h "$height" \
            "cat '$results_file'; read -rsn1; rm -f '$results_file'"
    else
        tmux split-window -v -l "$height" \
            "cat '$results_file'; read -rsn1; rm -f '$results_file'"
    fi
}

# Launch in background
run_comparison &
disown
