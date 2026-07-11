import SwiftUI
import AppKit

@main
struct KlimaxUIApp: App {
    @State private var settings: AppSettings
    @State private var model: AppModel

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        // SwiftUI `.help()` tooltips use AppKit's default initial delay (~1s+),
        // which feels sluggish. AppKit reads this key (milliseconds) from the
        // standard defaults; set it early so all tooltips appear promptly.
        UserDefaults.standard.set(350, forKey: "NSInitialToolTipDelay")

        // Settings and model share one AppSettings instance: the views read it
        // from the environment, AppModel reads poll cadences off it directly.
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _model = State(initialValue: AppModel(settings: settings))
    }

    var body: some Scene {
        WindowGroup("Klimax") {
            RootView(model: model)
                .environment(settings)
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowResizability(.contentMinSize)

        // Standard macOS Settings scene — bound to ⌘, and the "Settings…" menu item.
        Settings {
            SettingsView()
                .environment(settings)
        }
    }
}
