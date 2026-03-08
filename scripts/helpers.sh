#!/usr/bin/env bash

# Get tmux option with default fallback
get_tmux_option() {
    local option="$1"
    local default_value="$2"
    local option_value

    option_value=$(tmux show-option -gqv "$option")
    if [[ -z "$option_value" ]]; then
        # If the option value is empty, it MIGHT be because it's not set,
        # OR it might be explicitly set to empty string.
        # We need to distinguish between "unset" and "set to empty".

        # Check if the option is actually set in the global options
        if tmux show-option -g "$option" >/dev/null 2>&1; then
            # It is set (but empty), so return empty
            echo ""
        else
            # It is not set, so return default
            echo "$default_value"
        fi
    else
        echo "$option_value"
    fi
}

# Set tmux option
set_tmux_option() {
    local option="$1"
    local value="$2"
    tmux set-option -gq "$option" "$value"
}

# Check if a speedtest command is the Ookla binary or sivel Python script
# Returns: "ookla", "sivel", or "unknown"
identify_speedtest_type() {
    local cmd="$1"

    # Check if it supports --format=json (Ookla-specific flag)
    if "$cmd" --help 2>&1 | grep -q -- '--format'; then
        echo "ookla"
    # Check if it supports --json (sivel-specific flag)
    elif "$cmd" --help 2>&1 | grep -q -- '--json'; then
        echo "sivel"
    else
        echo "unknown"
    fi
}

# Find the Ookla speedtest binary (checking common locations)
find_ookla_binary() {
    local paths=(
        "/opt/homebrew/opt/speedtest/bin/speedtest"                     # macOS ARM Homebrew
        "/usr/local/opt/speedtest/bin/speedtest"                        # macOS Intel Homebrew
        "$HOME/.linuxbrew/opt/speedtest/bin/speedtest"                  # Linuxbrew user
        "/home/linuxbrew/.linuxbrew/opt/speedtest/bin/speedtest"        # Linuxbrew system
        "/usr/bin/speedtest"                                            # Linux system package
        "/usr/local/bin/speedtest"                                      # Linux local install
        "/snap/bin/speedtest"                                           # Ubuntu Snap
        "/usr/sbin/speedtest"                                           # Linux sbin
    )

    local path
    for path in "${paths[@]}"; do
        if [[ -x "$path" ]]; then
            local type
            type=$(identify_speedtest_type "$path")
            if [[ "$type" == "ookla" ]]; then
                echo "$path"
                return
            fi
        fi
    done

    # PATH fallback
    if command -v speedtest &>/dev/null; then
        local type
        type=$(identify_speedtest_type speedtest)
        if [[ "$type" == "ookla" ]]; then
            echo "speedtest"
            return
        fi
    fi

    echo ""
}

# Find the sivel speedtest-cli binary
find_sivel_binary() {
    local paths=(
        "$HOME/.linuxbrew/bin/speedtest-cli"                            # Linuxbrew user
        "/home/linuxbrew/.linuxbrew/bin/speedtest-cli"                  # Linuxbrew system
        "/usr/bin/speedtest-cli"                                        # Linux system package
        "/usr/local/bin/speedtest-cli"                                  # pip system install
        "$HOME/.local/bin/speedtest-cli"                                # pip --user install
    )

    local path
    for path in "${paths[@]}"; do
        if [[ -x "$path" ]]; then
            echo "$path"
            return
        fi
    done

    # PATH fallback
    if command -v speedtest-cli &>/dev/null; then
        echo "speedtest-cli"
        return
    fi

    # Check if speedtest in PATH is sivel
    if command -v speedtest &>/dev/null; then
        local type
        type=$(identify_speedtest_type speedtest)
        if [[ "$type" == "sivel" ]]; then
            echo "speedtest"
            return
        fi
    fi

    echo ""
}

# Find the fast-cli binary (Netflix fast.com)
find_fast_binary() {
    local paths=(
        "/opt/homebrew/bin/fast"                                        # Homebrew ARM64
        "$HOME/.npm-global/bin/fast"                                    # npm custom prefix
        "$HOME/.local/bin/fast"                                         # some npm configs
        "/usr/local/bin/fast"                                           # system npm install
    )

    local path
    for path in "${paths[@]}"; do
        if [[ -x "$path" ]]; then
            echo "$path"
            return
        fi
    done

    # PATH fallback
    if command -v fast &>/dev/null; then
        echo "fast"
        return
    fi

    echo ""
}

# Find the Cloudflare speedtest CLI binary
find_cloudflare_binary() {
    local paths=(
        "$HOME/.cargo/bin/cloudflare-speed-cli"                         # Cargo user install
        "$HOME/.linuxbrew/bin/cloudflare-speed-cli"                     # Linuxbrew user
        "/home/linuxbrew/.linuxbrew/bin/cloudflare-speed-cli"           # Linuxbrew system
        "/usr/local/bin/cloudflare-speed-cli"                           # manual install
        "/opt/homebrew/bin/cloudflare-speed-cli"                        # macOS Homebrew
    )

    local path
    for path in "${paths[@]}"; do
        if [[ -x "$path" ]]; then
            echo "$path"
            return
        fi
    done

    # PATH fallback
    if command -v cloudflare-speed-cli &>/dev/null; then
        echo "cloudflare-speed-cli"
        return
    fi

    echo ""
}

# Detect available speedtest CLI and return the command to use
# Returns: "ookla:<cmd>", "sivel:<cmd>", "fast:<cmd>", "cloudflare:<cmd>", or "none"
detect_speedtest_cli() {
    local provider
    provider=$(get_tmux_option "@speedtest_provider" "auto")

    # If user explicitly specifies a provider, try to find it
    if [[ "$provider" == "ookla" ]]; then
        local ookla_cmd
        ookla_cmd=$(find_ookla_binary)
        if [[ -n "$ookla_cmd" ]]; then
            echo "ookla:$ookla_cmd"
            return
        fi
    elif [[ "$provider" == "cloudflare" ]]; then
        local cf_cmd
        cf_cmd=$(find_cloudflare_binary)
        if [[ -n "$cf_cmd" ]]; then
            echo "cloudflare:$cf_cmd"
            return
        fi
    elif [[ "$provider" == "sivel" ]]; then
        local sivel_cmd
        sivel_cmd=$(find_sivel_binary)
        if [[ -n "$sivel_cmd" ]]; then
            echo "sivel:$sivel_cmd"
            return
        fi
    elif [[ "$provider" == "fast" ]]; then
        local fast_cmd
        fast_cmd=$(find_fast_binary)
        if [[ -n "$fast_cmd" ]]; then
            echo "fast:$fast_cmd"
            return
        fi
    fi

    # Auto-detect: prefer Ookla, then Cloudflare, then fast, then sivel
    local ookla_cmd
    ookla_cmd=$(find_ookla_binary)
    if [[ -n "$ookla_cmd" ]]; then
        echo "ookla:$ookla_cmd"
        return
    fi

    local cf_cmd
    cf_cmd=$(find_cloudflare_binary)
    if [[ -n "$cf_cmd" ]]; then
        echo "cloudflare:$cf_cmd"
        return
    fi

    local fast_cmd
    fast_cmd=$(find_fast_binary)
    if [[ -n "$fast_cmd" ]]; then
        echo "fast:$fast_cmd"
        return
    fi

    local sivel_cmd
    sivel_cmd=$(find_sivel_binary)
    if [[ -n "$sivel_cmd" ]]; then
        echo "sivel:$sivel_cmd"
        return
    fi

    echo "none"
}

# Get tmux major.minor version as comparable integer (e.g., 3.2 -> 302)
get_tmux_version() {
    local version_string
    version_string=$(tmux -V 2>/dev/null | grep -oE '[0-9]+\.[0-9]+')
    if [[ -z "$version_string" ]]; then
        echo "0"
        return
    fi
    local major minor
    major=$(echo "$version_string" | cut -d. -f1)
    minor=$(echo "$version_string" | cut -d. -f2)
    echo "$((major * 100 + minor))"
}

# Check if tmux supports display-popup (requires 3.2+)
supports_popup() {
    local version
    version=$(get_tmux_version)
    [[ "$version" -ge 302 ]]
}

# Format a timestamp for display (cross-platform)
format_timestamp() {
    local ts="$1"
    if [[ -z "$ts" || "$ts" == "0" ]]; then
        echo "N/A"
        return
    fi
    # macOS uses -r, Linux uses -d @
    if date -r "$ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null; then
        return
    fi
    date -d "@$ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "N/A"
}

# Extract a field from JSON using jq or grep
# Usage: extract_json_field <json> <jq_path> <grep_pattern>
extract_json_field() {
    local json="$1"
    local jq_path="$2"
    local grep_pattern="$3"

    # Try jq first
    if command -v jq &>/dev/null; then
        local val
        val=$(echo "$json" | jq -re "$jq_path" 2>/dev/null)
        if [[ $? -eq 0 && "$val" != "null" ]]; then
            echo "$val"
            return
        fi
    fi

    # Fallback to grep
    if [[ -n "$grep_pattern" ]]; then
        echo "$json" | grep -oE "$grep_pattern" | head -1 | grep -oE '[^:]+$' | tr -d '", '
        return
    fi

    echo ""
}

# Detect if jq is available for JSON parsing
# Returns: "jq" if available, "grep" otherwise
detect_json_parser() {
    if command -v jq &>/dev/null; then
        echo "jq"
    else
        echo "grep"
    fi
}

# Evaluate arithmetic expression (bc with awk fallback)
# Supports bc "scale=N;" syntax. Returns empty + exit 1 on failure.
calc() {
    local expr="$1"
    local result

    if command -v bc &>/dev/null; then
        result=$(echo "$expr" | bc 2>/dev/null)
    else
        local awk_expr="$expr"
        local scale=""
        if [[ "$awk_expr" =~ ^scale=([0-9]+)\;[[:space:]]*(.*) ]]; then
            scale="${BASH_REMATCH[1]}"
            awk_expr="${BASH_REMATCH[2]}"
        fi
        if [[ "$scale" == "0" ]]; then
            result=$(awk "BEGIN {print int($awk_expr)}" 2>/dev/null)
        elif [[ -n "$scale" ]]; then
            result=$(awk "BEGIN {printf \"%.${scale}f\", $awk_expr}" 2>/dev/null)
        else
            result=$(awk "BEGIN {print $awk_expr}" 2>/dev/null)
        fi
    fi

    if [[ -z "$result" ]]; then
        return 1
    fi
    echo "$result"
}

# Format speed with auto-scaling (bps to Mbps/Gbps)
# Input: speed in bits per second (for sivel), bytes per second (for ookla), or Mbps (for fast)
# Usage: format_speed <value> <source: ookla|sivel|fast>
format_speed() {
    local value="$1"
    local source="$2"
    local mbps

    if [[ -z "$value" || "$value" == "null" ]]; then
        echo "?"
        return
    fi

    # Convert to Mbps based on source
    if [[ "$source" == "ookla" ]]; then
        # Ookla reports in bytes per second, convert to Mbps
        mbps=$(calc "scale=2; $value * 8 / 1000000") || { echo "?"; return; }
    elif [[ "$source" == "fast" || "$source" == "cloudflare" ]]; then
        # fast-cli and cloudflare-speed-cli report directly in Mbps
        mbps="$value"
    else
        # sivel reports in bits per second, convert to Mbps
        mbps=$(calc "scale=2; $value / 1000000") || { echo "?"; return; }
    fi

    # Auto-scale to Gbps if >= 1000 Mbps
    if [[ "$(calc "$mbps >= 1000")" == "1" ]]; then
        local formatted
        formatted=$(calc "scale=2; $mbps / 1000") || { echo "?"; return; }
        echo "${formatted} Gbps"
    else
        # Round to integer for cleaner display
        local rounded
        rounded=$(calc "scale=0; ($mbps + 0.5) / 1") || { echo "?"; return; }
        echo "${rounded} Mbps"
    fi
}

# Format ping (round to integer)
format_ping() {
    local value="$1"

    if [[ -z "$value" || "$value" == "null" ]]; then
        echo "?"
        return
    fi

    local rounded
    rounded=$(calc "scale=0; ($value + 0.5) / 1") || { echo "?"; return; }
    echo "${rounded}ms"
}

# Build result string from template
# Replaces #{download}, #{upload}, #{ping} in format string
build_result_string() {
    local format="$1"
    local download="$2"
    local upload="$3"
    local ping="$4"

    local result="$format"
    result="${result//\#\{download\}/$download}"
    result="${result//\#\{upload\}/$upload}"
    result="${result//\#\{ping\}/$ping}"

    echo "$result"
}

# --- Color helpers ---

# Wrap text in tmux color formatting
# Usage: colorize_text <text> <fg_color>
colorize_text() {
    local text="$1"
    local color="$2"

    if [[ -z "$color" || "$color" == "none" ]]; then
        echo "$text"
    else
        echo "#[fg=${color}]${text}#[fg=default]"
    fi
}

# Determine color for a speed value (higher is better)
# Usage: get_speed_color <mbps_numeric> <good_threshold> <bad_threshold>
# Returns: color name from good/warn/bad config
get_speed_color() {
    local mbps="$1"
    local good_threshold="$2"
    local bad_threshold="$3"
    local color_good="$4"
    local color_warn="$5"
    local color_bad="$6"

    if [[ -z "$mbps" || "$mbps" == "?" || ! "$mbps" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        echo "none"
        return
    fi

    if [[ "$(calc "$mbps >= $good_threshold")" == "1" ]]; then
        echo "$color_good"
    elif [[ "$(calc "$mbps >= $bad_threshold")" == "1" ]]; then
        echo "$color_warn"
    else
        echo "$color_bad"
    fi
}

# Determine color for a ping value (lower is better)
# Usage: get_ping_color <ms_numeric> <good_threshold> <bad_threshold>
get_ping_color() {
    local ms="$1"
    local good_threshold="$2"
    local bad_threshold="$3"
    local color_good="$4"
    local color_warn="$5"
    local color_bad="$6"

    if [[ -z "$ms" || "$ms" == "?" || ! "$ms" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        echo "none"
        return
    fi

    if [[ "$(calc "$ms <= $good_threshold")" == "1" ]]; then
        echo "$color_good"
    elif [[ "$(calc "$ms <= $bad_threshold")" == "1" ]]; then
        echo "$color_warn"
    else
        echo "$color_bad"
    fi
}

# Convert formatted speed string back to Mbps numeric value for threshold comparison
# Input: "250 Mbps" or "1.50 Gbps" or "?"
# Output: numeric Mbps value or empty
speed_to_mbps() {
    local formatted="$1"

    if [[ "$formatted" == "?" ]]; then
        echo ""
        return
    fi

    if [[ "$formatted" =~ ([0-9.]+)[[:space:]]*Gbps ]]; then
        local result
        if ! result=$(calc "${BASH_REMATCH[1]} * 1000"); then
            echo ""
        else
            echo "$result"
        fi
    elif [[ "$formatted" =~ ([0-9.]+)[[:space:]]*Mbps ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# Convert formatted ping string back to numeric ms value
# Input: "15ms" or "?"
# Output: numeric ms value or empty
ping_to_ms() {
    local formatted="$1"

    if [[ "$formatted" == "?" ]]; then
        echo ""
        return
    fi

    if [[ "$formatted" =~ ([0-9.]+)ms ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# --- Lock file management ---

LOCK_FILE="/tmp/tmux-speedtest.lock"
LOCK_MAX_AGE=300
CURRENT_UID="${UID:-0}"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/tmux-speedtest-${CURRENT_UID}"

if [[ -L "$STATE_DIR" ]]; then
    STATE_DIR=""
elif [[ -d "$STATE_DIR" ]]; then
    state_owner_uid=$(stat -f %u "$STATE_DIR" 2>/dev/null)
    if [[ -z "$state_owner_uid" ]]; then
        state_owner_uid=$(stat -c %u "$STATE_DIR" 2>/dev/null)
    fi

    if [[ "$state_owner_uid" != "$CURRENT_UID" || ! -w "$STATE_DIR" ]]; then
        STATE_DIR=""
    else
        chmod 700 "$STATE_DIR" 2>/dev/null
    fi
else
    if mkdir -p "$STATE_DIR" 2>/dev/null; then
        chmod 700 "$STATE_DIR" 2>/dev/null
    else
        STATE_DIR=""
    fi
fi

if [[ -n "$STATE_DIR" ]]; then
    LAST_RUN_FILE="$STATE_DIR/last-run"
    BACKOFF_UNTIL_FILE="$STATE_DIR/backoff-until"
else
    LAST_RUN_FILE=""
    BACKOFF_UNTIL_FILE=""
fi

# Get age of a file in seconds (cross-platform)
file_age_seconds() {
    local file="$1"
    local mod_time
    # macOS
    mod_time=$(stat -f %m "$file" 2>/dev/null)
    if [[ -z "$mod_time" ]]; then
        # Linux
        mod_time=$(stat -c %Y "$file" 2>/dev/null)
    fi
    if [[ -z "$mod_time" ]]; then
        echo "0"
        return
    fi
    echo $(( $(date +%s) - mod_time ))
}

# Check if the lock file is stale (dead PID, too old, or corrupt)
# Returns 0 (true) if stale, 1 (false) if active
is_lock_stale() {
    local pid
    pid=$(cat "$LOCK_FILE" 2>/dev/null)

    # Corrupt or empty lock file
    if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
        return 0
    fi

    # Lock file older than LOCK_MAX_AGE seconds (hung process)
    local age
    age=$(file_age_seconds "$LOCK_FILE")
    if [[ "$age" -ge "$LOCK_MAX_AGE" ]]; then
        return 0
    fi

    # PID no longer alive
    if ! kill -0 "$pid" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Atomically acquire lock file (fails if lock already exists)
# Returns 0 on success, 1 if lock already held
acquire_lock() {
    if (set -C; echo "${BASHPID:-$$}" > "$LOCK_FILE") 2>/dev/null; then
        return 0
    fi
    return 1
}

# Remove lock file
release_lock() {
    rm -f "$LOCK_FILE"
}

# --- Time and expiry helpers ---

# Parse human-friendly time string to seconds
# Supports: 30s, 5m, 1h, 2d, combinations like 1h30m
# Special values: 0, off, disabled return 0
parse_time_to_seconds() {
    local time_str="$1"

    if [[ -z "$time_str" || "$time_str" == "0" || "$time_str" == "off" || "$time_str" == "disabled" ]]; then
        echo "0"
        return
    fi

    # If it's just a plain number, treat as seconds
    if [[ "$time_str" =~ ^[0-9]+$ ]]; then
        echo "$time_str"
        return
    fi

    local total=0
    while [[ "$time_str" =~ ([0-9]+)([smhd]) ]]; do
        local value="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]}"

        case "$unit" in
            s) total=$((total + value)) ;;
            m) total=$((total + value * 60)) ;;
            h) total=$((total + value * 3600)) ;;
            d) total=$((total + value * 86400)) ;;
        esac

        # Remove matched portion to continue parsing
        time_str="${time_str/${BASH_REMATCH[0]}/}"
    done

    echo "$total"
}

# Get current Unix timestamp
get_current_timestamp() {
    date +%s
}

# Return whether a state file is a regular file and not a symlink
is_safe_state_file() {
    local file="$1"
    [[ -n "$file" && -f "$file" && ! -L "$file" ]]
}

# Remove state file only when it is a regular non-symlink
remove_state_file() {
    local file="$1"
    if is_safe_state_file "$file"; then
        rm -f "$file"
    fi
}

# Read a Unix timestamp from file
# Returns 0 if file is missing/corrupt
read_timestamp_file() {
    local file="$1"
    local value

    if ! is_safe_state_file "$file"; then
        echo "0"
        return
    fi

    value=$(cat "$file" 2>/dev/null)
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "$value"
    else
        echo "0"
    fi
}

# Write Unix timestamp to file (best effort)
write_timestamp_file() {
    local file="$1"
    local timestamp="$2"

    if ! [[ "$timestamp" =~ ^[0-9]+$ ]]; then
        return
    fi

    if [[ -z "$file" ]]; then
        return
    fi

    if [[ -e "$file" && ! -f "$file" ]]; then
        return
    fi

    if [[ -L "$file" ]]; then
        return
    fi

    printf "%s" "$timestamp" > "$file" 2>/dev/null
}

# Get last successful run timestamp from tmux option or persisted file
get_last_run_timestamp() {
    local tmux_last_run
    local file_last_run

    tmux_last_run=$(get_tmux_option "@speedtest_last_run" "0")
    file_last_run=$(read_timestamp_file "$LAST_RUN_FILE")

    if ! [[ "$tmux_last_run" =~ ^[0-9]+$ ]]; then
        tmux_last_run="0"
    fi

    if [[ "$tmux_last_run" -ge "$file_last_run" ]]; then
        echo "$tmux_last_run"
    else
        echo "$file_last_run"
    fi
}

# Persist last successful run timestamp in tmux and /tmp for restart survival
persist_last_run_timestamp() {
    local timestamp="$1"

    if ! [[ "$timestamp" =~ ^[0-9]+$ ]]; then
        return
    fi

    set_tmux_option "@speedtest_last_run" "$timestamp"

    if [[ "$timestamp" == "0" ]]; then
        remove_state_file "$LAST_RUN_FILE"
    else
        write_timestamp_file "$LAST_RUN_FILE" "$timestamp"
    fi
}

# Get active backoff-until timestamp from tmux option or persisted file
get_backoff_until_timestamp() {
    local tmux_backoff_until
    local file_backoff_until

    tmux_backoff_until=$(get_tmux_option "@speedtest_backoff_until" "0")
    file_backoff_until=$(read_timestamp_file "$BACKOFF_UNTIL_FILE")

    if ! [[ "$tmux_backoff_until" =~ ^[0-9]+$ ]]; then
        tmux_backoff_until="0"
    fi

    if [[ "$tmux_backoff_until" -ge "$file_backoff_until" ]]; then
        echo "$tmux_backoff_until"
    else
        echo "$file_backoff_until"
    fi
}

# Persist backoff-until timestamp in tmux and /tmp for restart survival
set_backoff_until_timestamp() {
    local timestamp="$1"

    if ! [[ "$timestamp" =~ ^[0-9]+$ ]]; then
        return
    fi

    set_tmux_option "@speedtest_backoff_until" "$timestamp"
    if [[ "$timestamp" == "0" ]]; then
        remove_state_file "$BACKOFF_UNTIL_FILE"
    else
        write_timestamp_file "$BACKOFF_UNTIL_FILE" "$timestamp"
    fi
}

# Clear persisted backoff state
clear_backoff_until_timestamp() {
    set_tmux_option "@speedtest_backoff_until" "0"
    remove_state_file "$BACKOFF_UNTIL_FILE"
}

# Return backoff remaining seconds, clearing stale backoff automatically
get_backoff_remaining_seconds() {
    local backoff_until
    local now

    backoff_until=$(get_backoff_until_timestamp)
    if [[ "$backoff_until" -eq 0 ]]; then
        echo "0"
        return
    fi

    now=$(get_current_timestamp)
    if [[ "$backoff_until" -le "$now" ]]; then
        clear_backoff_until_timestamp
        echo "0"
        return
    fi

    echo $((backoff_until - now))
}

# Check if speedtest result has expired
# Returns 0 (true) if expired, 1 (false) if still valid
is_result_expired() {
    local expire_option
    expire_option=$(get_tmux_option "@speedtest_expire" "0")

    local expire_seconds
    expire_seconds=$(parse_time_to_seconds "$expire_option")

    # Expiry disabled
    if [[ "$expire_seconds" -eq 0 ]]; then
        return 1
    fi

    local last_run
    last_run=$(get_last_run_timestamp)

    # No test has been run
    if [[ "$last_run" == "0" || -z "$last_run" ]]; then
        return 1
    fi

    local current_time age
    current_time=$(get_current_timestamp)
    age=$((current_time - last_run))

    if [[ "$age" -ge "$expire_seconds" ]]; then
        return 0
    else
        return 1
    fi
}
