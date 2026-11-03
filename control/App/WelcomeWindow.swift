import AppKit
import ServiceManagement
import SwiftUI

final class WelcomeModel: ObservableObject {
    @Published var on = false
    @Published var statusText = ""
    @Published var detailText = ""
    @Published var sudoReady = false
    @Published var cliReady = false
    @Published var launchAtLogin = false
    @Published var menuBarIconHidden = false
    @Published var busy = false

    var setAwake: (Bool, String?) -> Void = { _, _ in }
    var enableGuard: () -> Void = {}
    var installCLI: () -> Void = {}
    var toggleLaunchAtLogin: () -> Void = {}
    var quit: () -> Void = {}
    var isStatusItemHidden: () -> Bool = { false }

    func refresh() {
        on = AwakeState.isOn
        let rem = AwakeState.remainingFormatted
        if on {
            statusText = rem.map { "Awake for \($0)" } ?? "Awake until you turn it off"
        } else if let paused = AwakeState.pausedReason {
            statusText = "Paused: \(paused)"
        } else {
            statusText = "Off. Your Mac sleeps normally."
        }
        let telem = AwakeState.batteryTelemetry()
        var parts: [String] = []
        if let pct = telem.percent { parts.append("Battery \(pct)%\(telem.onAC ? " (charging)" : "")") }
        if let temp = telem.tempC { parts.append("\(temp)°C") }
        parts.append(AwakeState.isClamshellClosed ? "Lid closed" : "Lid open")
        detailText = parts.joined(separator: " · ")
        sudoReady = AwakeState.isSudoRuleInstalled
        cliReady = AwakeState.isCLIInstalled
        launchAtLogin = SMAppService.mainApp.status == .enabled
        menuBarIconHidden = isStatusItemHidden()
    }
}

struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Awake").font(.title2.bold())
                    Text(model.statusText).foregroundStyle(model.on ? .primary : .secondary)
                    Text(model.detailText).font(.caption).foregroundStyle(.tertiary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    model.setAwake(!model.on, nil)
                } label: {
                    Text(model.on ? "Turn Off" : "Keep Awake")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(model.on ? .gray : .accentColor)
                .disabled(model.busy)

                HStack(spacing: 8) {
                    ForEach(["30m", "1h", "2h", "4h"], id: \.self) { spec in
                        Button(spec) { model.setAwake(true, spec) }
                            .frame(maxWidth: .infinity)
                            .disabled(model.busy)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                SetupRow(
                    done: model.sudoReady,
                    title: "Lid-closed sleep guard",
                    detail: model.sudoReady
                        ? "Installed. Closing the lid will not sleep the Mac while Awake is on."
                        : "One-time admin approval so Awake can stop lid-close sleep.",
                    action: model.sudoReady ? nil : ("Enable…", model.enableGuard)
                )
                SetupRow(
                    done: !model.menuBarIconHidden,
                    title: "Menu bar",
                    detail: model.menuBarIconHidden
                        ? "The cup icon is hidden, usually behind the camera notch when the menu bar is full. Hold ⌘ and drag other icons out to make room, or allow Awake in System Settings › Menu Bar."
                        : "Click the cup icon in the menu bar for timers and settings.",
                    action: nil
                )
                SetupRow(
                    done: nil,
                    title: "Control Center",
                    detail: "Open Control Center, click Edit Controls at the bottom, search for Awake and drag it in.",
                    action: nil
                )
                SetupRow(
                    done: model.cliReady,
                    title: "Command line",
                    detail: model.cliReady
                        ? "`awake` and `asleep` are installed."
                        : "Adds `awake` and `asleep` to ~/.local/bin.",
                    action: model.cliReady ? nil : ("Install", model.installCLI)
                )
            }

            Divider()

            HStack {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { _ in model.toggleLaunchAtLogin() }
                ))
                .toggleStyle(.checkbox)
                Spacer()
                Button("Quit Awake", action: model.quit)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct SetupRow: View {
    let done: Bool?
    let title: String
    let detail: String
    let action: (String, () -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.body.weight(.semibold))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(LocalizedStringKey(detail))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let action {
                Button(action.0, action: action.1)
            }
        }
    }

    private var icon: String {
        switch done {
        case .some(true): "checkmark.circle.fill"
        case .some(false): "exclamationmark.circle.fill"
        case .none: "info.circle.fill"
        }
    }

    private var color: Color {
        switch done {
        case .some(true): .green
        case .some(false): .orange
        case .none: .secondary
        }
    }
}
