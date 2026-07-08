import SwiftUI
import AppKit

@main
struct KlimaxUIApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        // SwiftUI `.help()` tooltips use AppKit's default initial delay (~1s+),
        // which feels sluggish. AppKit reads this key (milliseconds) from the
        // standard defaults; set it early so all tooltips appear promptly.
        UserDefaults.standard.set(350, forKey: "NSInitialToolTipDelay")
    }

    var body: some Scene {
        WindowGroup("Klimax") {
            RootView()
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowResizability(.contentMinSize)
    }
}
