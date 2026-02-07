# tmux-speedtest

A tmux plugin to run internet speed tests and display results in your status bar.

![Demo](https://img.shields.io/badge/status-beta-yellow)

## Screenshots

### Idle:

<img width="60" height="27" alt="Screenshot 2026-02-01 at 12 31 51 PM" src="https://github.com/user-attachments/assets/9010b068-d638-4771-80a3-d4e48e8af662" />


### Waiting for results:

<img width="156" height="25" alt="Screenshot 2026-02-01 at 12 27 52 PM" src="https://github.com/user-attachments/assets/d2eab7b3-0d04-4ca3-80ff-b7d5bce63e6f" />

### After results:

<img width="295" height="26" alt="Screenshot 2026-02-01 at 12 27 40 PM" src="https://github.com/user-attachments/assets/dcbac9b9-4b48-4907-9553-d212c3666f6b" />


## Features

- Run speedtest with a single keypress (`prefix + o` by default)
- **Non-blocking** - tmux remains fully responsive while test runs
- Results persist in status bar until next test
- Clear results with a keypress (`prefix + O` by default)
- Auto-detects available CLI (Ookla `speedtest`, `cloudflare-speed-cli`, `fast-cli`, or `speedtest-cli`)
- Auto-scales units (Mbps/Gbps)
- Fully configurable format, icons, and key bindings
- Shows progress indicator while running
- Prevents multiple concurrent tests
- **Color-coded results** - configurable thresholds for good/warn/bad speeds and ping
- **Auto-run on interval** - schedule periodic tests automatically
- **Detail popup** - view full test results including server, ISP, jitter, and packet loss (`prefix + d`)
- **Provider comparison** - run all available CLIs side-by-side (`prefix + C`)

## Requirements

One of the following speedtest CLI tools must be installed:

- [Ookla Speedtest CLI](https://www.speedtest.net/apps/cli) (recommended)
- [cloudflare-speed-cli](https://github.com/kavehtehrani/cloudflare-speed-cli) (Cloudflare)
- [fast-cli](https://github.com/sindresorhus/fast-cli) (Netflix's fast.com)
- [speedtest-cli](https://github.com/sivel/speedtest-cli) (Python)

**Optional:** [jq](https://jqlang.github.io/jq/) for more robust JSON parsing (falls back to grep if unavailable).

### Installation

**Ookla (recommended):**
```bash
# macOS
brew tap teamookla/speedtest
brew install speedtest

# Linux (Debian/Ubuntu)
curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash
sudo apt install speedtest
```

**cloudflare-speed-cli:**

Works for both Intel and Silicon Macs.

Using [Cargo](https://doc.rust-lang.org/cargo/):
```bash
cargo install --git https://github.com/kavehtehrani/cloudflare-speed-cli --features tui
```

Using [Homebrew](https://brew.sh/):
```bash
brew tap kavehtehrani/tap
brew install cloudflare-speed-cli
```

**fast-cli (Netflix fast.com):**
```bash
npm install --global fast-cli
```

> **Note:** fast-cli requires Node.js 20+

**speedtest-cli:**
```bash
pip install speedtest-cli
# or
brew install speedtest-cli
```

> **Auto-detection priority:** Ookla → Cloudflare → fast-cli → speedtest-cli

## Installation

### Using TPM (recommended)

Add to your `~/.tmux.conf`:

```bash
set -g @plugin 'YousefHadder/tmux-speedtest'
```

Press `prefix + I` to install.

### Manual

```bash
git clone https://github.com/YousefHadder/tmux-speedtest ~/.tmux/plugins/tmux-speedtest
```

Add to `~/.tmux.conf`:
```bash
run-shell ~/.tmux/plugins/tmux-speedtest/speedtest.tmux
```

## Usage

1. Add `#{speedtest_result}` to your status bar:

```bash
set -g status-right '#{speedtest_result} | %H:%M'
# or
set -g status-left '#{speedtest_result} [#S]'
```

2. Press `prefix + o` to run a speedtest

3. Results appear in status bar: `↓ 250 Mbps ↑ 25 Mbps 15ms`

### Key Bindings

| Key | Action | Option |
|-----|--------|--------|
| `prefix + o` | Run speedtest | `@speedtest_key` |
| `prefix + O` | Clear results | `@speedtest_clear_key` |
| `prefix + d` | Detail popup (full results) | `@speedtest_detail_key` |
| `prefix + C` | Compare all providers | `@speedtest_compare_key` |

## Configuration

Add these to your `~/.tmux.conf` before the plugin loads:

```bash
# Key binding (default: o)
set -g @speedtest_key 'o'

# Key binding to clear results (default: O)
set -g @speedtest_clear_key 'O'

# Key binding for detail popup (default: d)
set -g @speedtest_detail_key 'd'

# Key binding for provider comparison (default: C)
set -g @speedtest_compare_key 'C'

# Output format (default shown)
set -g @speedtest_format '↓ #{download} ↑ #{upload} #{ping}'

# Icon shown while test is running (default: ⏳)
set -g @speedtest_icon_running '⏳'

# Icon shown when no result yet (default: —)
# Set to "" (empty string) to auto-hide the plugin when idle
set -g @speedtest_icon_idle '—'

# Speedtest provider: auto, ookla, fast, cloudflare, or sivel (default: auto)
set -g @speedtest_provider 'auto'

# Use specific server ID (default: auto-select, only works with ookla/sivel)
set -g @speedtest_server ''

# Enable/Disable notifications (default: on)
set -g @speedtest_notifications 'on'

# Timeout in seconds for each test (default: 120)
set -g @speedtest_timeout '120'
```

### Auto-Run

Run tests automatically on a schedule:

```bash
# Run a test when tmux starts (default: off)
set -g @speedtest_run_on_start 'on'

# Auto-run interval (default: 0, disabled)
# Supports: seconds (e.g., 3600), minutes (e.g., 30m), hours (e.g., 1h)
set -g @speedtest_interval '30m'
```

### Color-Coded Results

Enable color-coded speeds and ping in the status bar based on configurable thresholds:

```bash
# Enable color coding (default: off)
set -g @speedtest_colors 'on'

# Speed thresholds in Mbps (values above good = green, below bad = red, between = yellow)
set -g @speedtest_threshold_good '100'
set -g @speedtest_threshold_bad '25'

# Ping thresholds in ms (values below good = green, above bad = red, between = yellow)
set -g @speedtest_ping_threshold_good '30'
set -g @speedtest_ping_threshold_bad '100'

# Custom colors (default: green, yellow, red)
set -g @speedtest_color_good 'green'
set -g @speedtest_color_warn 'yellow'
set -g @speedtest_color_bad 'red'
```

### Format Placeholders

| Placeholder | Description |
|-------------|-------------|
| `#{download}` | Download speed (e.g., `250 Mbps` or `1.5 Gbps`) |
| `#{upload}` | Upload speed |
| `#{ping}` | Latency (e.g., `15ms`) |

### Example Configurations

**Minimal:**
```bash
set -g @speedtest_format '↓#{download} ↑#{upload}'
```

**With emoji:**
```bash
set -g @speedtest_format '🌐 ⬇#{download} ⬆#{upload} 📶#{ping}'
```

**Compact:**
```bash
set -g @speedtest_format 'D:#{download} U:#{upload} P:#{ping}'
```

**Nerd Fonts:**
```bash
set -g @speedtest_icon_running '󰔟'
set -g @speedtest_format ' #{download}  #{upload} 󰛳 #{ping}'
```

### Catppuccin Theme Integration

If you're using [catppuccin/tmux](https://github.com/catppuccin/tmux), create a custom module file:

**`~/.config/tmux/custom_modules/ctp_speedtest.conf`:**
```bash
# vim:set ft=tmux:
%hidden MODULE_NAME='ctp_speedtest'

set-option -gq "@catppuccin_${MODULE_NAME}_icon" '󰓅 '
set-option -gq "@catppuccin_${MODULE_NAME}_color" '#{E:@thm_teal}'
set-option -gq "@catppuccin_${MODULE_NAME}_text" '#(~/.tmux/plugins/tmux-speedtest/scripts/speedtest_status.sh)'

source-file -F '#{TMUX_PLUGIN_MANAGER_PATH}/tmux/utils/status_module.conf'
```

Then in your `~/.tmux.conf`:
```bash
# Source the custom module
source -F '#{HOME}/.config/tmux/custom_modules/ctp_speedtest.conf'

# Add to your status bar
# To auto-hide the module when idle (if @speedtest_icon_idle is empty), use conditional logic:
set -ag status-left "#{?#(~/.tmux/plugins/tmux-speedtest/scripts/speedtest_status.sh),#{E:@catppuccin_status_ctp_speedtest},}"
# Or just display it always:
# set -ag status-left '#{E:@catppuccin_status_ctp_speedtest}'
```

## Troubleshooting

### "No CLI found" error
Install one of the required speedtest tools (see Requirements).

### Results not showing
Make sure `#{speedtest_result}` is in your `status-right` or `status-left` config, then reload tmux: `tmux source ~/.tmux.conf`

### Test fails
Check your internet connection. Try running `speedtest`, `fast`, or `speedtest-cli` directly in terminal to see detailed errors.

### Detail popup opens in a split pane instead of a popup
The `display-popup` command requires tmux 3.2 or later. On older versions, the plugin automatically falls back to a split pane.

### speedtest-cli gets 403 error
The Python `speedtest-cli` sometimes gets blocked by Speedtest.net. Use the Ookla CLI or fast-cli instead:
```bash
set -g @speedtest_provider 'ookla'  # or 'fast'
```

## License

MIT
