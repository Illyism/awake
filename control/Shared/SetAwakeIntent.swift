import AppIntents

struct SetAwakeIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Keep Awake"
    // Run in the app, not the sandboxed widget extension.
    static let openAppWhenRun = true

    @Parameter(title: "Awake")
    var value: Bool

    func perform() async throws -> some IntentResult {
        try AwakeState.set(value)
        return .result()
    }
}
