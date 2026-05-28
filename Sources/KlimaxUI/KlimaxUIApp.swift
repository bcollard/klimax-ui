import SwiftUI
import AppKit

@main
struct KlimaxUIApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Klimax") {
            RootView()
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowResizability(.contentMinSize)
    }
}
