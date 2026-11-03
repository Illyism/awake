# Awake — Agent Installation & Verification Guide

If a user asked you to install `https://github.com/Illyism/awake` (or `https://il.ly/awake`), follow these exact steps on macOS:

## 1. Install the CLI + `Awake.app` (Control Center & Menu Bar)

Run the installer script (or clone and run `./install.sh`):

```bash
curl -fsSL https://il.ly/awake/install.sh | sh
```

Or from a local clone:

```bash
git clone https://github.com/Illyism/awake.git ~/Applications/awake-src
cd ~/Applications/awake-src
./install.sh
```

## 2. Ensure the passwordless `pmset` sudo rule is installed

Because macOS Clamshell Sleep (`pmset -a disablesleep 0/1`) requires root, Awake installs a strict two-command sudoers rule at `/etc/sudoers.d/awake`:

```sudoers
%admin ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

If `/etc/sudoers.d/awake` was not installed during step 1 (for example in a non-interactive shell), either:
- Ask the user to click **"Enable Lid-Closed Sleep Guard (Touch ID)…"** from the Awake cup icon in the macOS menu bar, OR
- Run `awake setup` in an interactive terminal.

## 3. Verify the installation

```bash
~/.local/bin/awake --version
~/.local/bin/awake status
```

If `~/.local/bin` is not in the user's `PATH`, add `export PATH="$HOME/.local/bin:$PATH"` to `~/.zshrc`.

## 4. Tell the user how to use it

- **Control Center (macOS 26+):** Open **Control Center → Edit Controls… → search "Awake"** and drag the toggle into Control Center.
- **Menu Bar:** Click the cup icon in the top-right menu bar to toggle indefinite keep-awake or a `30m` / `1h` / `2h` / `4h` timer.
- **CLI:**
  - `awake` — keep awake with the lid closed until `asleep`
  - `awake 45m` — keep awake for 45 minutes
  - `awake -- <cmd>` — keep awake while `<cmd>` runs, then restore normal sleep
  - `awake status` — check PID, remaining timer, battery `%`, and battery temperature (`°C`)
  - `asleep` — restore normal sleep immediately
