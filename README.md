<p align="center">
  <img src="assets/awake-icon.png" alt="Awake icon" width="128" height="128" />
</p>

<h1 align="center">Awake</h1>

<p align="center">
  <strong>Close the lid. Keep running.</strong><br />
  Lid-closed keep-awake for macOS — with a native Control Center toggle, Menu Bar timer, CLI, instant screen lock on lid close, and a backpack thermal &amp; battery circuit breaker.
</p>

<p align="center">
  <a href="https://il.ly/awake">Website</a> ·
  <a href="https://github.com/Illyism/awake/releases/latest">Download DMG</a> ·
  <a href="#install">Install</a> ·
  <a href="#why-bare-caffeinate-is-not-enough">How it works</a> ·
  <a href="#security--privacy">Security</a>
</p>

![Awake — Close the lid. Keep running.](assets/awake-hero.jpg)

---

## Why bare `caffeinate` is not enough

When you kick off a long coding agent session (`claude`, `codex`, `cursor`, `opencode`), an SSH tunnel, or a large upload and close your MacBook lid on battery:

1. **Bare `caffeinate` only blocks *idle* sleep.** Closing the lid triggers **Clamshell Sleep**, drops Wi-Fi within seconds, and kills every in-flight CLI and network call.
2. **`caffeinate -ims` without `-d` lets `powerd` enter low-power display-sleep mode**, which causes `WiFiAgent` to drop weak hotel or tether connections.
3. **Raw `sudo pmset -a disablesleep 1` is dangerous on its own:**
   - Because `SleepDisabled = 1` and `caffeinate -d` suppress `SystemWillSleep` and `kCGSDisplayWillSleep`, closing the lid leaves `loginwindow` **unlocked** (`IOConsoleLocked = No`).
   - If you toss your MacBook into a backpack and forget to run `pmset -a disablesleep 0`, it will cook itself past $45^\circ\text{C}$ or drain the battery to $0\%$.

**Awake** fixes all four:

- **True lid-closed keep-awake:** Combines `pmset -a disablesleep 1`, `caffeinate -dims` (keeping `powerd` in unrestricted Wi-Fi performance mode), and IOKit `kPMSetClamshellSleepState`.
- **Instant screen lock on lid close:** Observes `IOPMrootDomain` (`AppleClamshellState` `No → Yes`) and calls `SACLockScreenImmediate()` in-process so your Mac locks the instant the lid closes — without sleeping the display or dropping Wi-Fi.
- **Backpack thermal & battery guard with auto-resume:** Checks battery `%`, `AppleSmartBattery` temperature ($^\circ\text{C}$), and macOS thermal pressure every 30 seconds. If battery drops to $\le 10\%$ on battery power, or a closed lid reaches $\ge 40^\circ\text{C}$ or thermal pressure $\ge 1$, Awake automatically pauses and restores normal sleep — then **resumes automatically** once plugged in or cooled down ($+4\%$ battery / $-2^\circ\text{C}$ hysteresis).
- **Zero-drift UI (`Awake.app`):** Native macOS 26 **Control Center widget** (`ControlWidgetToggle`) + **Menu Bar timer** backed by in-process IORegistry reads, `sysctl` PID checks, and a `kqueue` watcher on `~/.cache/awake`.

---

## Install

### Option 1 — One-line script (recommended)

Builds `Awake.app` locally with your Xcode certificate (for the macOS 26 Control Center widget) or downloads the prebuilt release bundle, links `~/.local/bin/awake` and `~/.local/bin/asleep`, and installs `/etc/sudoers.d/awake`:

```bash
curl -fsSL https://il.ly/awake/install.sh | sh
```

### Option 2 — Point your AI agent at this repo

Paste into Claude Code, Cursor, Codex, or OpenCode:

```text
Install https://github.com/Illyism/awake on my Mac
```

### Option 3 — Homebrew

```bash
brew tap illyism/awake https://github.com/Illyism/awake
brew install --cask illyism/awake/awake
awake setup
```

*(Or `brew install --formula illyism/awake/awake` for the CLI formula only.)*

### Option 4 — Download DMG

Download **[Awake-1.0.0-macos-arm64.dmg](https://github.com/Illyism/awake/releases/download/v1.0.0/Awake-1.0.0-macos-arm64.dmg)** (Developer ID signed and notarized by Apple), drag `Awake.app` to `Applications`, launch it, and click **Enable Lid-Closed Sleep Guard (Touch ID)…** in the Awake menu bar icon.

### Option 5 — Nix (`flake.nix` / `nix-darwin`)

```bash
nix profile install github:Illyism/awake
```

Or in `nix-darwin`:

```nix
services.awake.enable = true;
```

---

## Usage

### Control Center & Menu Bar

1. **Menu Bar:** Click the cup icon (`cup.and.heat.waves.fill`) in the menu bar to toggle **Keep Awake Indefinitely** or start a **30m / 1h / 2h / 4h** countdown, view live battery `%` and temperature ($^\circ\text{C}$), or hide the menu bar icon if you only use Control Center.
2. **Control Center (macOS 26+):** Open **Control Center → Edit Controls… → search "Awake"** and drag the toggle into Control Center.

### CLI (`awake` & `asleep`)

```bash
awake                  # Keep awake indefinitely (lid can close, Wi-Fi stays up)
awake 45m              # Keep awake for 45 minutes (s / m / h, or minutes)
awake -- codex exec …  # Keep awake while a command runs, then restore sleep
awake status           # Show caffeinate PID, timer, lid state, temp °C, and battery
asleep                 # Restore normal sleep immediately (alias for `awake stop`)
awake setup            # Install /etc/sudoers.d/awake (validated via visudo -cf)
```

```text
$ awake status
awake  caffeinate pid 22253 (42m left)
lid    sleep disabled
temp   30C (lid limit 40C)
last   auto-stop: battery at 10%, Mon 21:08
power  Now drawing from 'AC Power'
power   -InternalBattery-0 (id=23003235)	87%; charging; 0:51 remaining present: true
```

### Environment Overrides

| Variable | Default | Description |
|---|---|---|
| `AWAKE_MIN_BATTERY` | `10` | Pause when on battery at or below this `%` (resumes on AC or at $+4\%$) |
| `AWAKE_MIN_BATTERY_LID` | `10` | Pause when lid is closed on battery at or below this `%` |
| `AWAKE_MAX_BATT_TEMP_LID` | `40` | Pause when lid is closed and battery reaches this temperature ($^\circ\text{C}$) |
| `AWAKE_MAX_THERMAL_LID` | `1` | Pause when lid is closed and macOS thermal pressure reaches this level (`0` nominal, `1` moderate) |

### Optional Sleep / Lid-Close Hook (`~/.config/awake/on-sleep`)

If you create an executable script owned by your user at `~/.config/awake/on-sleep` (`chmod 700`), Awake runs it automatically:
- `on-sleep idle` — when `asleep` runs or when the lid closes while `awake` is active
- `on-sleep sleep` — when the Mac enters normal sleep or pauses on a battery/thermal safety threshold (useful for auto-unmounting encrypted volumes or locking vaults when closing the lid)

---

## Security & Privacy

- **Zero network requests or telemetry:** Neither `awake`, `Awake.app`, nor `AwakeControl.appex` makes any network calls.
- **Minimal, exact-match `sudoers` rule:** `/etc/sudoers.d/awake` is validated with `/usr/sbin/visudo -cf` before installation and permits only two exact commands with no wildcards or flags:
  ```sudoers
  %admin ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
  ```
- **Sandboxed WidgetKit extension:** `AwakeControl.appex` runs inside the macOS App Sandbox (`com.apple.security.app-sandbox = true`) with a single read-only exception for `~/.cache/awake/` (`0700` user-owned directory).
- **Hardware SMC safety intact:** Kernel SMC emergency thermal protection remains active at all times, with Awake's user-space watcher pausing keep-awake long before hardware limits ($40^\circ\text{C}$ battery / moderate thermal pressure).

---

## Uninstall

```bash
curl -fsSL https://il.ly/awake/install.sh | sh -s -- uninstall
```

## License

[MIT](LICENSE) © [Ilias Ism](https://il.ly)
