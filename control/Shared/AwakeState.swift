import Darwin
import Foundation
import IOKit

/// State lives in the `awake` script's cache dir, so the CLI, the menu bar item,
/// and the Control Center toggle always agree. The widget extension reads it
/// through a sandbox exception; only the app (unsandboxed) runs the script.
enum AwakeState {
    static var isTransitioning = false
    static var lastIntentRun = Date.distantPast

    private static var home: URL {
        if let dir = getpwuid(getuid())?.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var cacheDir: URL {
        home.appendingPathComponent(".cache/awake")
    }

    private static var pidFile: URL {
        cacheDir.appendingPathComponent("caffeinate.pid")
    }

    private static var pausedFile: URL {
        cacheDir.appendingPathComponent("paused")
    }

    private static var watchFile: URL {
        cacheDir.appendingPathComponent("watch.pid")
    }

    private static var untilFile: URL {
        cacheDir.appendingPathComponent("until")
    }

    private static var lastStopFile: URL {
        cacheDir.appendingPathComponent("last_stop")
    }

    /// On only while the recorded caffeinate is alive AND kernel
    /// SleepDisabled is set. Either half missing means lid close can
    /// still sleep the Mac and drop Wi-Fi.
    static var isOn: Bool { status().on }

    /// Single-pass state check for the monitor:
    /// - `on`: both caffeinate and kernel SleepDisabled are active.
    /// - `stale`: only one half is active (dead pid, cleared SleepDisabled,
    ///   or SleepDisabled left on with no pid file).
    /// - `pausedOrphan`: `paused` is set (waiting to resume when calm),
    ///   but the watcher died (e.g. after a reboot).
    static func status() -> (on: Bool, stale: Bool, pausedOrphan: Bool) {
        let sleepDisabled = isSleepDisabled
        guard let pid = readPID(pidFile) else {
            let paused = FileManager.default.fileExists(atPath: pausedFile.path)
            let watcherAlive = readPID(watchFile).map { kill($0, 0) == 0 || errno == EPERM } ?? false
            return (false, sleepDisabled, paused && !watcherAlive)
        }
        let on = isCaffeinate(pid) && sleepDisabled
        return (on, !on, false)
    }

    static var pausedReason: String? {
        guard let text = try? String(contentsOf: pausedFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return nil }
        return text
    }

    static var lastAutoStop: String? {
        guard let text = try? String(contentsOf: lastStopFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return nil }
        return text
    }

    static var remainingSeconds: Int? {
        guard let text = try? String(contentsOf: untilFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let until = Int(text)
        else { return nil }
        let now = Int(Date().timeIntervalSince1970)
        return until > now ? (until - now) : nil
    }

    static var remainingFormatted: String? {
        guard let secs = remainingSeconds else { return nil }
        if secs >= 3600 {
            let h = secs / 3600
            let m = (secs % 3600 + 59) / 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return "\((max(1, secs) + 59) / 60)m"
    }

    static var isSudoRuleInstalled: Bool {
        FileManager.default.fileExists(atPath: "/etc/sudoers.d/awake")
    }

    static var isCLIInstalled: Bool {
        let paths = [
            home.appendingPathComponent(".local/bin/awake").path,
            "/opt/homebrew/bin/awake",
            "/usr/local/bin/awake",
        ]
        return paths.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    @discardableResult
    static func installCLISymlinks() -> Bool {
        guard let bundled = Bundle.main.url(forResource: "awake", withExtension: nil),
              isTrustedExecutable(bundled)
        else { return false }
        let binDir = home.appendingPathComponent(".local/bin")
        do {
            try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
            let awakeDest = binDir.appendingPathComponent("awake")
            let asleepDest = binDir.appendingPathComponent("asleep")
            try? FileManager.default.removeItem(at: awakeDest)
            try? FileManager.default.removeItem(at: asleepDest)
            try FileManager.default.createSymbolicLink(atPath: awakeDest.path, withDestinationPath: bundled.path)
            try FileManager.default.createSymbolicLink(atPath: asleepDest.path, withDestinationPath: "awake")
            return true
        } catch {
            return false
        }
    }

    private static func isTrustedExecutable(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        var st = stat()
        guard stat(resolved.path, &st) == 0 else { return false }
        let uid = getuid()
        guard st.st_uid == uid || st.st_uid == 0 else { return false }
        guard (st.st_mode & S_IWOTH) == 0 else { return false }
        return FileManager.default.isExecutableFile(atPath: resolved.path)
    }

    static var scriptURL: URL {
        let candidates = [
            Bundle.main.url(forResource: "awake", withExtension: nil),
            home.appendingPathComponent(".local/bin/awake"),
            URL(fileURLWithPath: "/opt/homebrew/bin/awake"),
            URL(fileURLWithPath: "/usr/local/bin/awake"),
        ].compactMap { $0 }
        for url in candidates where isTrustedExecutable(url) {
            return url.resolvingSymlinksInPath()
        }
        return home.appendingPathComponent(".local/bin/awake")
    }

    @discardableResult
    private static func runCLI(_ args: [String]) -> Int32 {
        let script = scriptURL
        guard isTrustedExecutable(script) else { return -1 }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path] + args
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    static func resumeWatcher() {
        runCLI(["--resume"])
    }

    static func runSleepHook() {
        let hook = home.appendingPathComponent(".config/awake/on-sleep")
        guard isTrustedExecutable(hook) else { return }
        runCLI(["--on-sleep"])
    }

    /// Reads `SleepDisabled` directly from `IOPMrootDomain` in IORegistry
    /// (in-process, works inside the widget sandbox without spawning pmset).
    static var isSleepDisabled: Bool { rootBool("SleepDisabled") }

    /// True while the MacBook lid is closed (`AppleClamshellState = Yes`).
    static var isClamshellClosed: Bool { rootBool("AppleClamshellState") }

    /// In-process battery % and temperature (C) from `AppleSmartBattery`.
    static func batteryTelemetry() -> (percent: Int?, onAC: Bool, tempC: Int?) {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else { return (nil, false, nil) }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any]
        else { return (nil, false, nil) }
        let onAC = (dict["ExternalConnected"] as? Bool) == true
        let cur = dict["CurrentCapacity"] as? Int
        let max = dict["MaxCapacity"] as? Int
        let pct: Int? = {
            guard let cur else { return nil }
            if let max, max > 0, max != 100 {
                return min(100, Int(Double(cur) * 100.0 / Double(max) + 0.5))
            }
            return min(100, cur)
        }()
        let tempC = (dict["Temperature"] as? Int).map { $0 / 100 }
        return (pct, onAC, tempC)
    }

    /// True while the loginwindow session is locked (`IOConsoleLocked = Yes`).
    static var isConsoleLocked: Bool {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(root) }
        let prop = IORegistryEntryCreateCFProperty(
            root,
            "IOConsoleLocked" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()
        return (prop as? Bool) == true
    }

    private static let sacLockScreenImmediate: (@convention(c) () -> Void)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY),
              let sym = dlsym(handle, "SACLockScreenImmediate")
        else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) () -> Void).self)
    }()

    /// Locks the loginwindow session immediately without sleeping the display
    /// or dropping `caffeinate -d`'s `PreventUserIdleDisplaySleep` assertion.
    static func lockScreen() {
        guard !isConsoleLocked else { return }
        sacLockScreenImmediate?()
    }

    private static func rootBool(_ key: String) -> Bool {
        withRootDomain { service in
            let prop = IORegistryEntryCreateCFProperty(
                service,
                key as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue()
            return (prop as? Bool) == true
        } ?? false
    }

    /// Belt-and-suspenders: sets the kernel's `clamshellSleepDisableMask`
    /// via `IOPMrootDomain` selector `kPMSetClamshellSleepState` (12)
    /// (no root or entitlement required).
    @discardableResult
    static func setClamshellSleepDisabled(_ disabled: Bool) -> Bool {
        withRootDomain { service in
            var conn: io_connect_t = IO_OBJECT_NULL
            guard IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS else {
                return false
            }
            defer { IOServiceClose(conn) }
            var input: UInt64 = disabled ? 1 : 0
            var outCount: UInt32 = 0
            return IOConnectCallScalarMethod(conn, 12, &input, 1, nil, &outCount) == kIOReturnSuccess
        } ?? false
    }

    private static func withRootDomain<T>(_ body: (io_service_t) -> T) -> T? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        return body(service)
    }

    private static func readPID(_ file: URL) -> pid_t? {
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0
        else { return nil }
        return pid
    }

    private static func isCaffeinate(_ pid: pid_t) -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else {
            // Sandbox may deny sysctl; EPERM still means the pid exists.
            return kill(pid, 0) == 0 || errno == EPERM
        }
        guard size > 0 else { return false }
        let name = withUnsafeBytes(of: info.kp_proc.p_comm) {
            String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
        }
        return name == "caffeinate"
    }

    /// Prompts via native macOS Touch ID / Administrator dialog to install
    /// `/etc/sudoers.d/awake` (validated with `visudo -cf`) if missing.
    @discardableResult
    static func installSudoRuleInteractive() -> Bool {
        let cmd = """
        tmp=$(mktemp /tmp/awake-sudoers.XXXXXX) || exit 1
        printf '%s\\n' '# Awake lid-sleep rule (exact commands only)' '%admin ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1' > "$tmp"
        /usr/sbin/visudo -cf "$tmp" >/dev/null 2>&1 && /usr/bin/install -m 0440 -o root -g wheel "$tmp" /etc/sudoers.d/awake
        rc=$?
        rm -f "$tmp"
        exit $rc
        """
        let escaped = cmd
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 && isSudoRuleInstalled
        } catch {
            return false
        }
    }

    static func set(_ on: Bool, duration: String? = nil) throws {
        isTransitioning = true
        defer { isTransitioning = false }
        setClamshellSleepDisabled(on)
        var args: [String] = []
        if on {
            if let duration { args.append(duration) }
        } else {
            args.append("stop")
        }
        _ = runCLI(args)
        var active = isOn
        if on, !active, !isSudoRuleInstalled {
            if installSudoRuleInteractive() {
                _ = runCLI(args)
                active = isOn
            }
        }
        setClamshellSleepDisabled(active)
        if on, !active {
            throw AwakeError.needsSudoRule
        }
    }
}

enum AwakeError: Error, CustomLocalizedStringResourceConvertible {
    case needsSudoRule

    var localizedStringResource: LocalizedStringResource {
        "Could not disable lid sleep. Run `awake setup` to install /etc/sudoers.d/awake."
    }
}
