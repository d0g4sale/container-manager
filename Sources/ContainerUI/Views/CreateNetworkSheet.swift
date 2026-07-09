import SwiftUI

private struct LabelPair: Identifiable, Hashable { let id = UUID(); var key = ""; var value = "" }

struct CreateNetworkSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var subnet = ""
    @State private var subnetV6 = ""
    @State private var internalOnly = false
    @State private var labels: [LabelPair] = []

    @State private var creating = false
    @State private var errorText: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                generalSection
                addressingSection
                labelsSection
            }
            .formStyle(.grouped)
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
                    .padding(.horizontal, 20).padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 560)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "network.badge.shield.half.filled")
                .font(.system(size: 26)).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading) {
                Text("Create a Network").font(.headline)
                Text("Let containers talk to each other and the host")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var generalSection: some View {
        Section {
            LabeledField("Name") {
                TextField("Name", text: $name, prompt: Text("e.g. backend"))
                    .sheetField()
                    .font(.system(.body, design: .monospaced))
            }
            Toggle("Host-only (internal)", isOn: $internalOnly)
        } header: {
            Text("General")
        } footer: {
            Text("An internal network has no outbound connectivity — containers on it can reach each other but not the internet.")
        }
    }

    private var addressingSection: some View {
        Section {
            LabeledField("Subnet") {
                TextField("Subnet", text: $subnet, prompt: Text("Optional — e.g. 10.10.0.0/24"))
                    .sheetField()
                    .font(.system(.body, design: .monospaced))
            }
            LabeledField("IPv6 subnet") {
                TextField("IPv6 subnet", text: $subnetV6, prompt: Text("Optional — e.g. fd00::/64"))
                    .sheetField()
                    .font(.system(.body, design: .monospaced))
            }
        } header: {
            Text("Addressing")
        } footer: {
            Text("Leave blank to let the engine allocate a subnet automatically.")
        }
    }

    private var labelsSection: some View {
        Section {
            ForEach($labels) { $l in
                HStack(spacing: 8) {
                    TextField("Key", text: $l.key, prompt: Text("key"))
                        .sheetField()
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity)
                    Text("=").foregroundStyle(.secondary)
                    TextField("Value", text: $l.value, prompt: Text("value"))
                        .sheetField()
                        .frame(maxWidth: .infinity)
                    Button { $labels.removeDeferred(l.id) } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.borderless)
                }
            }
            Button { labels.append(LabelPair()) } label: { Label("Add label", systemImage: "plus") }
        } header: {
            Text("Labels")
        } footer: {
            Text("Optional metadata attached to the network.")
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Spacer()
            Button {
                createNetwork()
            } label: {
                if creating { ProgressView().controlSize(.small) }
                else { Label("Create", systemImage: "plus") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(creating || trimmedName.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private func createNetwork() {
        creating = true
        errorText = nil
        let name = trimmedName
        let subnet = self.subnet.trimmingCharacters(in: .whitespaces)
        let subnetV6 = self.subnetV6.trimmingCharacters(in: .whitespaces)
        let internalOnly = self.internalOnly
        let labelPairs = labels.map { ($0.key.trimmingCharacters(in: .whitespaces), $0.value) }
        Task {
            do {
                try await model.engine.createNetwork(name: name, subnet: subnet,
                                                      subnetV6: subnetV6,
                                                      internalOnly: internalOnly,
                                                      labels: labelPairs)
                model.showToast(.success, "Created network \(name)")
                await model.refreshAll(showSpinner: false)
                dismiss()
            } catch {
                creating = false
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
