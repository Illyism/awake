# Awake Control Center & Menu Bar App (`control/`)

Native macOS companion app (`Awake.app`) and WidgetKit Control Center extension (`AwakeControl.appex`) for `awake`.

## Targets

- **`Awake` (`App/` + `Shared/`)**:
  - Background Login Item (`LSUIElement = true`) that observes `IOPMrootDomain` clamshell notifications (`AppleClamshellState`) and `kqueue` file events on `~/.cache/awake`.
  - Calls `SACLockScreenImmediate()` in-process when the lid closes while `awake` is active, locking `loginwindow` without sleeping the display or dropping Wi-Fi.
  - Provides a native Menu Bar status item (`NSStatusItem`) with live battery `%`, temperature (`°C`), lid status, countdown timers (`30m`, `1h`, `2h`, `4h`), and a one-click Touch ID prompt to install `/etc/sudoers.d/awake`.
  - Bundles the `awake` CLI inside `Awake.app/Contents/Resources/awake` as a self-contained fallback.
- **`AwakeControl` (`Widget/` + `Shared/`)**:
  - Sandboxed macOS 26+ `ControlWidgetToggle` (`com.illyism.awake.control`) that reads `IOPMrootDomain` `SleepDisabled` + `~/.cache/awake/caffeinate.pid` (`sysctl` `KERN_PROC_PID`) so the Control Center switch never drifts out of sync.

## Building Locally

```bash
./control/install.sh
```

If an `Apple Development` signing certificate is present in your Keychain (any free Apple ID added in **Xcode → Settings → Accounts**), `install.sh` signs `Awake.app` and `AwakeControl.appex` with your team so WidgetKit registers the Control Center toggle. Otherwise it builds with ad-hoc signing (`-`) so the Menu Bar app and CLI still work immediately.
