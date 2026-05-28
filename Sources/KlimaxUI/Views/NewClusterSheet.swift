import SwiftUI

/// Modal sheet for naming a new kind cluster. Presented from the sidebar's `+`
/// button and from the home dashboard's create-cluster tile.
struct NewClusterSheet: View {
    @Bindable var model: AppModel
    @Binding var isPresented: Bool
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create kind cluster").font(.title3.bold())
            Text("Klimax assigns the next free num and API port.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("cluster name", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Create") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    isPresented = false
                    guard !trimmed.isEmpty else { return }
                    Task { await model.createCluster(named: trimmed) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
