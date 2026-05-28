import AppKit
import Foundation

/// Centralized access to bundled image resources. SwiftPM bundles live in
/// Bundle.module, not the main bundle, so `NSImage(named:)` doesn't find them.
enum AppAssets {
    static let logo: NSImage? = {
        guard let url = Bundle.module.url(forResource: "klimax-logo", withExtension: "png")
        else { return nil }
        return NSImage(contentsOf: url)
    }()
}
