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
    # Check Homebrew opt path first (handles shadowing by Python version)
    local brew_path="/opt/homebrew/opt/speedtest/bin/speedtest"
    if [[ -x "$brew_path" ]]; then
        local type
        type=$(identify_speedtest_type "$brew_path")
        if [[ "$type" == "ookla" ]]; then
            echo "$brew_path"
            return
        fi
    fi

    # Check Intel Homebrew path
    local brew_intel_path="/usr/local/opt/speedtest/bin/speedtest"
    if [[ -x "$brew_intel_path" ]]; then
        local type
        type=$(identify_speedtest_type "$brew_intel_path")
        if [[ "$type" == "ookla" ]]; then
            echo "$brew_intel_path"
            return
        fi
    fi

    # Check if speedtest in PATH is Ookla
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
    if command -v fast &>/dev/null; then
        echo "fast"
        return
    fi

    echo ""
}

# Find the Cloudflare speedtest CLI binary
find_cloudflare_binary() {
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
        mbps=$(echo "scale=2; $value * 8 / 1000000" | bc)
    elif [[ "$source" == "fast" || "$source" == "cloudflare" ]]; then
        # fast-cli and cloudflare-speed-cli report directly in Mbps
        mbps="$value"
    else
        # sivel reports in bits per second, convert to Mbps
        mbps=$(echo "scale=2; $value / 1000000" | bc)
    fi

    # Auto-scale to Gbps if >= 1000 Mbps
    local gbps
    gbps=$(echo "$mbps >= 1000" | bc)
    if [[ "$gbps" -eq 1 ]]; then
        local formatted
        formatted=$(echo "scale=2; $mbps / 1000" | bc)
        echo "${formatted} Gbps"
    else
        # Round to integer for cleaner display
        local rounded
        rounded=$(echo "scale=0; ($mbps + 0.5) / 1" | bc)
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
    rounded=$(echo "scale=0; ($value + 0.5) / 1" | bc)
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
