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

    tmux display-message "speedtest: Comparing ${#PROVIDERS[@]} providers in parallel..."

    TIMEOUT_SECS=$(get_tmux_option "@speedtest_timeout" "120")
    if ! [[ "$TIMEOUT_SECS" =~ ^[0-9]+$ ]]; then
        TIMEOUT_SECS=120
    fi

    # Launch all providers in parallel, each writing JSON to its own temp file
    local pids=()
    local output_files=()
    local cli_types=()

    local provider_info cli_type cli_cmd
    for provider_info in "${PROVIDERS[@]}"; do
        cli_type="${provider_info%%:*}"
        cli_cmd="${provider_info#*:}"
        cli_types+=("$cli_type")

        local outfile
        outfile=$(mktemp)
        output_files+=("$outfile")

        # Build and execute command in background
        (
            local cmd=()
            case "$cli_type" in
                ookla)      cmd=( "$cli_cmd" --format=json --accept-license --accept-gdpr ) ;;
                fast)       cmd=( "$cli_cmd" --json --upload ) ;;
                cloudflare) cmd=( "$cli_cmd" --json ) ;;
                sivel|*)    cmd=( "$cli_cmd" --json ) ;;
            esac

            if command -v timeout &>/dev/null; then
                timeout "$TIMEOUT_SECS" "${cmd[@]}" > "$outfile" 2>/dev/null || true
            else
                "${cmd[@]}" > "$outfile" 2>/dev/null &
                local child=$!
                ( sleep "$TIMEOUT_SECS" && kill "$child" 2>/dev/null ) &
                local watcher=$!
                wait "$child" 2>/dev/null
                kill "$watcher" 2>/dev/null
                wait "$watcher" 2>/dev/null
            fi
        ) &
        pids+=($!)
    done

    # Wait for all providers to finish
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null
    done

    # Build results table
    local results_file
    results_file=$(mktemp)

    cat > "$results_file" <<HEADER

  Provider Comparison - $(date "+%Y-%m-%d %H:%M:%S")
  ==================================================

  Provider       Download      Upload        Ping
  --------------------------------------------------
HEADER

    local i
    for i in "${!cli_types[@]}"; do
        cli_type="${cli_types[$i]}"
        local output
        output=$(cat "${output_files[$i]}" 2>/dev/null)
        rm -f "${output_files[$i]}"

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
    local tmpscript
    tmpscript=$(mktemp)
    cat > "$tmpscript" <<SCRIPT
#!/usr/bin/env bash
cat '$results_file'
read -rsn1
rm -f '$results_file' '$tmpscript'
SCRIPT
    chmod +x "$tmpscript"

    if supports_popup; then
        tmux display-popup -E -w 60 -h "$height" "$tmpscript"
    else
        tmux split-window -v -l "$height" "$tmpscript"
    fi
}

# Launch in background
run_comparison &
disown
