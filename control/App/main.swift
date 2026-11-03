import AppKit
import IOKit
import ServiceManagement
import SwiftUI
import WidgetKit

// `Awake --lock` locks the screen immediately on lid close.
if CommandLine.arguments.contains("--lock") {
    AwakeState.lockScreen()
    exit(0)
}

// `Awake --reload` refreshes the Control Center widget after the CLI changes state.
if CommandLine.arguments.contains("--reload") {
    AwakeState.setClamshellSleepDisabled(AwakeState.isOn)
    ControlCenter.shared.reloadAllControls()
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    exit(0)
}

/// Keeps the Control Center toggle and Menu Bar item on the real kernel + caffeinate state.
/// The `awake` watcher reloads the control when it pauses, resumes, or stops caffeinate
/// itself, and this monitor covers external kills, reboots, and wake-ups using event-driven
/// IOKit + kqueue notifications (with a 30s safety fallback timer).
final class Monitor: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var lastOn: Bool?
    private var wasClamshellClosed = AwakeState.isClamshellClosed
    private var staleSince: Date?
    private var timer: Timer?
    private var dirSource: DispatchSourceFileSystemObject?
    private var notifyPort: IONotificationPortRef?
    private var rootNote: io_object_t = IO_OBJECT_NULL
    private var statusItem: NSStatusItem?
    private var welcomeWindow: NSWindow?
    private let welcome = WelcomeModel()
    private let hideMenuBarKey = "hideMenuBarIcon"
    private let didConfigureLoginItemKey = "didConfigureLaunchAtLogin"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundlePath = Bundle.main.bundlePath
        let isMountedVolume = bundlePath.hasPrefix("/Volumes/") || bundlePath.contains("/AppTranslocation/")
        if !isMountedVolume, !UserDefaults.standard.bool(forKey: didConfigureLoginItemKey) {
            UserDefaults.standard.set(true, forKey: didConfigureLoginItemKey)
            if SMAppService.mainApp.status != .enabled {
                try? SMAppService.mainApp.register()
            }
        }
        if !UserDefaults.standard.bool(forKey: hideMenuBarKey) {
            setupStatusItem()
        }
        configureWelcome()
        start()
        if !launchedAsLoginItem, ProcessInfo.processInfo.systemUptime > 180 {
            showWelcomeUnlessIntent()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWelcomeUnlessIntent()
        return false
    }

    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == kAEOpenApplication
        else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    /// SetAwakeIntent (openAppWhenRun) also launches or reopens the app, so wait briefly for it to record itself.
    private func showWelcomeUnlessIntent() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, Date().timeIntervalSince(AwakeState.lastIntentRun) > 5 else { return }
            self.showWelcome()
        }
    }

    private func configureWelcome() {
        welcome.setAwake = { [weak self] on, duration in
            self?.welcome.busy = true
            DispatchQueue.global().async {
                try? AwakeState.set(on, duration: duration)
                DispatchQueue.main.async {
                    self?.welcome.busy = false
                    self?.check()
                }
            }
        }
        welcome.enableGuard = { [weak self] in self?.setupSudoRule() }
        welcome.installCLI = { [weak self] in
            self?.installCLI()
            self?.welcome.refresh()
        }
        welcome.toggleLaunchAtLogin = { [weak self] in
            self?.toggleLaunchAtLogin()
            self?.welcome.refresh()
        }
        welcome.quit = { NSApplication.shared.terminate(nil) }
        welcome.isStatusItemHidden = { [weak self] in self?.isStatusItemHidden ?? true }
    }

    @objc private func showWelcome() {
        if statusItem == nil {
            UserDefaults.standard.set(false, forKey: hideMenuBarKey)
            setupStatusItem()
        }
        let window = welcomeWindow ?? {
            let window = NSWindow(contentViewController: NSHostingController(rootView: WelcomeView(model: welcome)))
            window.title = "Awake"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            welcomeWindow = window
            return window
        }()
        welcome.refresh()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // Cooperative activation is refused when the launcher keeps focus (Terminal, Raycast).
        window.orderFrontRegardless()
        // The status item gets its final menu bar position a moment after it is created.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.welcome.refresh() }
    }

    /// True when the menu bar icon cannot be seen: not placed, not allowed in the menu bar,
    /// or pushed behind the camera notch by a full menu bar.
    private var isStatusItemHidden: Bool {
        guard let window = statusItem?.button?.window,
              window.occlusionState.contains(.visible),
              let screen = window.screen
        else { return true }
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return false }
        let x = window.frame.midX - screen.frame.minX
        return x > left.width && x < screen.frame.width - right.width
    }

    func start() {
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.check() }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        observeClamshell()
        observeCacheDir()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { _ in
            AwakeState.lockScreen()
            DispatchQueue.global().async { AwakeState.runSleepHook() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.lastOn = nil
            self?.check()
        }
        check()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let on = AwakeState.isOn
        let paused = AwakeState.pausedReason != nil
        let symbol = on ? "cup.and.heat.waves.fill" : (paused ? "pause.circle" : "cup.and.saucer")
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Awake") {
            image.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
        }
        if on, let rem = AwakeState.remainingFormatted {
            button.title = " \(rem)"
        } else {
            button.title = ""
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let on = AwakeState.isOn
        let paused = AwakeState.pausedReason
        let rem = AwakeState.remainingFormatted

        let titleText: String
        if on {
            titleText = rem.map { "Awake · \($0) remaining" } ?? "Awake · Lid Sleep Disabled"
        } else if let paused {
            titleText = "Paused · \(paused)"
        } else {
            titleText = "Asleep · Normal Sleep"
        }
        let header = NSMenuItem(title: titleText, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let telem = AwakeState.batteryTelemetry()
        var parts: [String] = []
        if let pct = telem.percent {
            parts.append("Battery \(pct)% (\(telem.onAC ? "AC" : "Battery"))")
        }
        if let temp = telem.tempC {
            parts.append("\(temp)°C")
        }
        parts.append(AwakeState.isClamshellClosed ? "Lid Closed" : "Lid Open")
        let sub = NSMenuItem(title: parts.joined(separator: " · "), action: nil, keyEquivalent: "")
        sub.isEnabled = false
        menu.addItem(sub)

        if let lastStop = AwakeState.lastAutoStop, paused == nil {
            let stopItem = NSMenuItem(title: "Last safety pause: \(lastStop)", action: nil, keyEquivalent: "")
            stopItem.isEnabled = false
            menu.addItem(stopItem)
        }

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open Awake…", action: #selector(showWelcome), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let keepOn = NSMenuItem(title: "Keep Awake Indefinitely", action: #selector(turnOnIndefinite), keyEquivalent: "")
        keepOn.target = self
        keepOn.state = (on && rem == nil) ? .on : .off
        menu.addItem(keepOn)

        for (label, spec) in [
            ("For 30 Minutes", "30m"),
            ("For 1 Hour", "1h"),
            ("For 2 Hours", "2h"),
            ("For 4 Hours", "4h"),
        ] {
            let item = NSMenuItem(title: label, action: #selector(turnOnDuration(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = spec
            menu.addItem(item)
        }

        let offItem = NSMenuItem(title: "Turn Off (Restore Sleep)", action: #selector(turnOff), keyEquivalent: "")
        offItem.target = self
        offItem.isEnabled = on || paused != nil
        menu.addItem(offItem)

        menu.addItem(.separator())

        if !AwakeState.isSudoRuleInstalled {
            let sudoItem = NSMenuItem(title: "Enable Lid-Closed Sleep Guard (Touch ID)…", action: #selector(setupSudoRule), keyEquivalent: "")
            sudoItem.target = self
            menu.addItem(sudoItem)
        }

        if !AwakeState.isCLIInstalled {
            let cliItem = NSMenuItem(title: "Install Command Line Tool (~/.local/bin/awake)", action: #selector(installCLI), keyEquivalent: "")
            cliItem.target = self
            menu.addItem(cliItem)
        }

        if !AwakeState.isSudoRuleInstalled || !AwakeState.isCLIInstalled {
            menu.addItem(.separator())
        }

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(loginItem)

        let hideItem = NSMenuItem(title: "Hide Menu Bar Icon (Control Center Only)", action: #selector(hideMenuBar), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Awake", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func turnOnIndefinite() {
        DispatchQueue.global().async { [weak self] in
            try? AwakeState.set(true)
            DispatchQueue.main.async { self?.check() }
        }
    }

    @objc private func turnOnDuration(_ sender: NSMenuItem) {
        guard let spec = sender.representedObject as? String else { return }
        DispatchQueue.global().async { [weak self] in
            try? AwakeState.set(true, duration: spec)
            DispatchQueue.main.async { self?.check() }
        }
    }

    @objc private func turnOff() {
        DispatchQueue.global().async { [weak self] in
            try? AwakeState.set(false)
            DispatchQueue.main.async { self?.check() }
        }
    }

    @objc private func setupSudoRule() {
        DispatchQueue.global().async { [weak self] in
            _ = AwakeState.installSudoRuleInteractive()
            DispatchQueue.main.async { self?.check() }
        }
    }

    @objc private func installCLI() {
        _ = AwakeState.installCLISymlinks()
    }

    @objc private func toggleLaunchAtLogin() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
    }

    @objc private func hideMenuBar() {
        UserDefaults.standard.set(true, forKey: hideMenuBarKey)
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func observeCacheDir() {
        try? FileManager.default.createDirectory(at: AwakeState.cacheDir, withIntermediateDirectories: true)
        let fd = open(AwakeState.cacheDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.check() }
        source.setCancelHandler { close(fd) }
        source.resume()
        dirSource = source
    }

    private func observeClamshell() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard service != IO_OBJECT_NULL,
              let port = IONotificationPortCreate(kIOMainPortDefault)
        else {
            if service != IO_OBJECT_NULL { IOObjectRelease(service) }
            return
        }
        defer { IOObjectRelease(service) }
        notifyPort = port
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            IONotificationPortGetRunLoopSource(port).takeUnretainedValue(),
            .commonModes
        )
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        IOServiceAddInterestNotification(
            port,
            service,
            kIOGeneralInterest,
            { refcon, _, _, _ in
                guard let refcon else { return }
                Unmanaged<Monitor>.fromOpaque(refcon).takeUnretainedValue().check()
            },
            refcon,
            &rootNote
        )
    }

    func check() {
        let (on, stale, pausedOrphan) = AwakeState.status()
        let closed = AwakeState.isClamshellClosed
        if closed, !wasClamshellClosed {
            if on {
                AwakeState.lockScreen()
            }
            DispatchQueue.global().async { AwakeState.runSleepHook() }
        }
        wasClamshellClosed = closed

        if on {
            // Re-assert IOKit clamshell sleep disable in case powerd
            // re-evaluated clamshell state on power or display change.
            AwakeState.setClamshellSleepDisabled(true)
        }
        if on != lastOn {
            lastOn = on
            ControlCenter.shared.reloadAllControls()
        }
        updateStatusItem()
        if welcomeWindow?.isVisible == true {
            welcome.refresh()
        }
        if pausedOrphan {
            DispatchQueue.global().async { AwakeState.resumeWatcher() }
        }
        if stale, !AwakeState.isTransitioning {
            if let since = staleSince {
                if Date().timeIntervalSince(since) >= 8 {
                    staleSince = nil
                    DispatchQueue.global().async { try? AwakeState.set(false) }
                }
            } else {
                staleSince = Date()
            }
        } else {
            staleSince = nil
        }
    }
}

let app = NSApplication.shared
let monitor = Monitor()
app.delegate = monitor
app.setActivationPolicy(.accessory)
app.run()
