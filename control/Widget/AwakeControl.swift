import AppIntents
import SwiftUI
import WidgetKit

@main
struct AwakeWidgets: WidgetBundle {
    var body: some Widget {
        AwakeControl()
    }
}

struct AwakeControl: ControlWidget {
    static let kind = "com.illyism.awake.control"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: Provider()) { isOn in
            ControlWidgetToggle("Awake", isOn: isOn, action: SetAwakeIntent()) { isOn in
                Label(isOn ? "On" : "Off",
                      systemImage: isOn ? "cup.and.heat.waves.fill" : "cup.and.saucer")
            }
        }
        .displayName("Awake")
        .description("Keep this Mac awake, including with the lid closed.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }

        func currentValue() async throws -> Bool {
            AwakeState.isOn
        }
    }
}
