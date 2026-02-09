#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

# Retrieve stored result data
JSON=$(get_tmux_option "@speedtest_result_json" "")
TIMESTAMP=$(get_tmux_option "@speedtest_result_timestamp" "")
PROVIDER=$(get_tmux_option "@speedtest_result_provider" "")
SPEEDTEST_KEY=$(get_tmux_option "@speedtest_key" "o")

if [[ -z "$JSON" ]]; then
    tmux display-message "speedtest: No results available. Run a test first (prefix + $SPEEDTEST_KEY)"
    exit 0
fi

# Parse fields based on provider type
parse_and_display() {
    local json="$1"
    local provider="$2"
    local ts="$3"

    local download upload ping_val jitter packet_loss
    local server_name server_location isp external_ip

    case "$provider" in
        ookla)
            download=$(extract_json_field "$json" '.download.bandwidth' '"bandwidth":\s*[0-9.]+')
            upload=$(extract_json_field "$json" '.upload.bandwidth' '"bandwidth":\s*[0-9.]+')
            ping_val=$(extract_json_field "$json" '.ping.latency' '"latency":\s*[0-9.]+')
            jitter=$(extract_json_field "$json" '.ping.jitter' '"jitter":\s*[0-9.]+')
            packet_loss=$(extract_json_field "$json" '.packetLoss' '"packetLoss":\s*[0-9.]+')
            server_name=$(extract_json_field "$json" '.server.name' '"name":\s*"[^"]*"')
            server_location=$(extract_json_field "$json" '.server.location' '"location":\s*"[^"]*"')
            isp=$(extract_json_field "$json" '.isp' '"isp":\s*"[^"]*"')
            external_ip=$(extract_json_field "$json" '.interface.externalIp' '"externalIp":\s*"[^"]*"')
            ;;
        cloudflare)
            download=$(extract_json_field "$json" '.download.mbps' '"mbps":\s*[0-9.]+')
            upload=$(extract_json_field "$json" '.upload.mbps' '"mbps":\s*[0-9.]+')
            ping_val=$(extract_json_field "$json" '.idle_latency.median_ms' '"median_ms":\s*[0-9.]+')
            jitter=$(extract_json_field "$json" '.idle_latency.jitter_ms' '"jitter_ms":\s*[0-9.]+')
            ;;
        fast)
            download=$(extract_json_field "$json" '.downloadSpeed' '"downloadSpeed":\s*[0-9.]+')
            upload=$(extract_json_field "$json" '.uploadSpeed' '"uploadSpeed":\s*[0-9.]+')
            ping_val=$(extract_json_field "$json" '.latency' '"latency":\s*[0-9.]+')
            ;;
        sivel|*)
            download=$(extract_json_field "$json" '.download' '"download":\s*[0-9.]+')
            upload=$(extract_json_field "$json" '.upload' '"upload":\s*[0-9.]+')
            ping_val=$(extract_json_field "$json" '.ping' '"ping":\s*[0-9.]+')
            server_name=$(extract_json_field "$json" '.server.name' '"name":\s*"[^"]*"')
            isp=$(extract_json_field "$json" '.client.isp' '"isp":\s*"[^"]*"')
            external_ip=$(extract_json_field "$json" '.client.ip' '"ip":\s*"[^"]*"')
            ;;
    esac

    # Format values
    local dl_fmt ul_fmt ping_fmt jitter_fmt
    dl_fmt=$(format_speed "$download" "$provider")
    ul_fmt=$(format_speed "$upload" "$provider")
    ping_fmt=$(format_ping "$ping_val")
    jitter_fmt=$(format_ping "$jitter")

    local ts_fmt
    ts_fmt=$(format_timestamp "$ts")

    # Build display
    echo ""
    echo "  Speedtest Results - $ts_fmt"
    echo "  ========================================"
    echo ""
    echo "  Download:     $dl_fmt"
    echo "  Upload:       $ul_fmt"
    echo "  Ping:         $ping_fmt"
    [[ -n "$jitter" ]] && echo "  Jitter:       $jitter_fmt"
    [[ -n "$packet_loss" ]] && echo "  Packet Loss:  ${packet_loss}%"
    echo ""
    echo "  Provider:     $provider"
    [[ -n "$server_name" ]] && echo "  Server:       $server_name"
    [[ -n "$server_location" ]] && echo "  Location:     $server_location"
    [[ -n "$isp" ]] && echo "  ISP:          $isp"
    [[ -n "$external_ip" ]] && echo "  External IP:  $external_ip"
    echo ""
    echo "  Press any key to close"
    echo ""
}

# Generate content to a temp file (avoids quoting issues with special chars)
TMPFILE=$(mktemp)
TMPSCRIPT_EARLY=""
trap 'rm -f "$TMPFILE" "$TMPSCRIPT_EARLY"' EXIT
parse_and_display "$JSON" "$PROVIDER" "$TIMESTAMP" > "$TMPFILE"

# Write a self-contained display script (avoids shell compatibility issues)
TMPSCRIPT=$(mktemp)
TMPSCRIPT_EARLY="$TMPSCRIPT"
cat > "$TMPSCRIPT" <<SCRIPT
#!/usr/bin/env bash
cat '$TMPFILE'
read -rsn1
rm -f '$TMPFILE' '$TMPSCRIPT'
SCRIPT
chmod +x "$TMPSCRIPT"

# Display via popup or split-pane fallback
if supports_popup; then
    tmux display-popup -E -w 70 -h 20 "$TMPSCRIPT"
else
    tmux split-window -v -l 20 "$TMPSCRIPT"
fi
