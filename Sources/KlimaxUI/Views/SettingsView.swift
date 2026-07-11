import SwiftUI

/// The app's preferences window (⌘,). Two tabs: what's visible, and how often
/// the various background pollers refresh.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        TabView {
            Form {
                Section {
                    Toggle("Console log panel", isOn: $settings.showConsoleLog)
                    Text("Pins an aggregated, timestamped log of every action to the bottom of the main view.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Registry / pull-through mirrors", isOn: $settings.showMirrors)
                    Text("Show the mirrors section in the sidebar and overview.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Toggle("VM stats & graphs", isOn: $settings.showVMStats)
                    Text("Show the VM's load and memory rows plus the CPU/memory charts. When off, the VM is not polled over SSH.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Visibility", systemImage: "eye") }

            Form {
                Section("Refresh intervals") {
                    Stepper(
                        "Cluster list: \(Int(settings.clusterRefreshSeconds)) s",
                        value: $settings.clusterRefreshSeconds, in: 2...60, step: 1
                    )
                    Stepper(
                        "VM stats: \(Int(settings.vmPollSeconds)) s",
                        value: $settings.vmPollSeconds, in: 2...60, step: 1
                    )
                    Stepper(
                        "Cluster metrics: \(Int(settings.metricsPollSeconds)) s",
                        value: $settings.metricsPollSeconds, in: 5...120, step: 5
                    )
                }
                Section {
                    Text("Changes take effect on the next poll cycle. Shorter intervals feel more live but do more work (SSH round-trips, kubectl calls).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Refresh", systemImage: "arrow.clockwise") }
        }
        .frame(width: 460)
    }
}
