import SwiftUI

private struct LabelPair: Identifiable, Hashable { let id = UUID(); var key = ""; var value = "" }

struct CreateVolumeSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var size = ""
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
        .frame(width: 560, height: 480)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 26)).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading) {
                Text("Create a Volume").font(.headline)
                Text("Persistent storage that outlives a container")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var generalSection: some View {
        Section {
            TextField("Name", text: $name, prompt: Text("e.g. pgdata"))
                .font(.system(.body, design: .monospaced))
            TextField("Size", text: $size, prompt: Text("Optional — e.g. 512M, 10G"))
        } header: {
            Text("General")
        } footer: {
            Text("Size accepts an optional K, M, G, T or P suffix. Leave blank for the driver default.")
        }
    }

    private var labelsSection: some View {
        Section {
            ForEach($labels) { $l in
                HStack(spacing: 8) {
                    TextField("key", text: $l.key).font(.system(.body, design: .monospaced))
                    Text("=").foregroundStyle(.secondary)
                    TextField("value", text: $l.value)
                    Button { labels.removeAll { $0.id == l.id } } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.borderless)
                }
            }
            Button { labels.append(LabelPair()) } label: { Label("Add label", systemImage: "plus") }
        } header: {
            Text("Labels")
        } footer: {
            Text("Optional metadata attached to the volume.")
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Spacer()
            Button {
                createVolume()
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

    private func createVolume() {
        creating = true
        errorText = nil
        let name = trimmedName
        let size = self.size.trimmingCharacters(in: .whitespaces)
        let labelPairs = labels.map { ($0.key.trimmingCharacters(in: .whitespaces), $0.value) }
        Task {
            do {
                try await model.engine.createVolume(name: name, size: size, labels: labelPairs)
                model.showToast(.success, "Created volume \(name)")
                await model.refreshAll(showSpinner: false)
                dismiss()
            } catch {
                creating = false
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
