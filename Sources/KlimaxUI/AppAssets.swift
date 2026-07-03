import AppKit
import Foundation

/// Centralized access to bundled image resources.
///
/// We deliberately avoid SwiftPM's generated `Bundle.module` accessor: it looks
/// for a `KlimaxUI_KlimaxUI.bundle` next to the executable (or a hardcoded
/// `.build` path) and calls `fatalError` when neither exists. swift-bundler
/// never produces that nested bundle — it flattens our `Resources/` straight
/// into the app's `Contents/Resources` — so touching `Bundle.module` in the
/// shipped `.app` crashes on first access. We resolve resources by hand across
/// the layouts we actually ship/run under instead.
enum AppAssets {
    static let logo: NSImage? = loadImage(named: "klimax-logo", withExtension: "png")

    /// The app's marketing version (CFBundleShortVersionString), e.g. "0.1.4".
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private static func loadImage(named name: String, withExtension ext: String) -> NSImage? {
        // 1. swift-bundler / normal .app layout: resource sits in Contents/Resources.
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return NSImage(contentsOf: url)
        }
        // 2. `swift run` / test layout: SwiftPM resource bundle beside the binary.
        let bases = [
            Bundle.main.bundleURL,
            Bundle.main.executableURL?.deletingLastPathComponent(),
        ].compactMap { $0 }
        for base in bases {
            let bundleURL = base.appendingPathComponent("KlimaxUI_KlimaxUI.bundle")
            if let bundle = Bundle(url: bundleURL),
               let url = bundle.url(forResource: name, withExtension: ext) {
                return NSImage(contentsOf: url)
            }
        }
        return nil
    }
}
