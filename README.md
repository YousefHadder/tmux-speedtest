# tmux-speedtest

A tmux plugin to run internet speed tests and display results in your status bar.

![Demo](https://img.shields.io/badge/status-beta-yellow)

## Features

- Run speedtest with a single keypress (`prefix + o` by default)
- Results persist in status bar until next test
- Auto-detects available CLI (Ookla `speedtest` or `speedtest-cli`)
- Auto-scales units (Mbps/Gbps)
- Fully configurable format, icons, and key bindings
- Shows progress indicator while running

## Requirements

One of the following speedtest CLI tools must be installed:

- [Ookla Speedtest CLI](https://www.speedtest.net/apps/cli) (recommended)
- [speedtest-cli](https://github.com/sivel/speedtest-cli) (Python)

### Installation

**Ookla (recommended):**
```bash
# macOS
brew install speedtest

# Linux (Debian/Ubuntu)
curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash
sudo apt install speedtest
```

**speedtest-cli:**
```bash
pip install speedtest-cli
# or
brew install speedtest-cli
```

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

## Configuration

Add these to your `~/.tmux.conf` before the plugin loads:

```bash
# Key binding (default: o)
set -g @speedtest_key 'o'

# Output format (default shown)
set -g @speedtest_format '↓ #{download} ↑ #{upload} #{ping}'

# Icon shown while test is running (default: ⏳)
set -g @speedtest_icon_running '⏳'

# Icon shown when no result yet (default: empty)
set -g @speedtest_icon_idle ''

# Force specific CLI: auto, ookla, or sivel (default: auto)
set -g @speedtest_prefer 'auto'

# Use specific server ID (default: auto-select)
set -g @speedtest_server ''
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

## Troubleshooting

### "No CLI found" error
Install one of the required speedtest tools (see Requirements).

### Results not showing
Make sure `#{speedtest_result}` is in your `status-right` or `status-left` config, then reload tmux: `tmux source ~/.tmux.conf`

### Test fails
Check your internet connection. Try running `speedtest` or `speedtest-cli` directly in terminal to see detailed errors.

## License

MIT
