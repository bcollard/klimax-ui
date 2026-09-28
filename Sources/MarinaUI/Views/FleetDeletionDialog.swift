import SwiftUI

extension View {
    /// Confirmation for `marina fleet delete`, shared by the sidebar and the
    /// overview. Lists the members the UI knows about; marina resolves the real
    /// set by label in the guest, so when some cluster's labels haven't loaded
    /// the message says the list may be incomplete rather than claim it's exact.
    func fleetDeletionDialog(model: AppModel, pending: Binding<ClusterGroup?>) -> some View {
        let group = pending.wrappedValue
        let fleet = group?.fleet ?? ""
        let count = group?.clusters.count ?? 0
        return confirmationDialog(
            "Delete fleet \"\(fleet)\"?",
            isPresented: Binding(
                get: { pending.wrappedValue != nil },
                set: { if !$0 { pending.wrappedValue = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete \(count) cluster\(count == 1 ? "" : "s")", role: .destructive) {
                Task { await model.deleteFleet(named: fleet) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let names = group?.clusters.map(\.name).joined(separator: ", ") ?? ""
            let caveat = model.hasClustersWithUnknownFleet
                ? "\n\nSome clusters' labels haven't loaded yet; marina will also delete any of them labeled marina.run/fleet=\(fleet)."
                : ""
            Text("This tears down \(names). This cannot be undone.\(caveat)")
        }
    }
}
