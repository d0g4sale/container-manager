import SwiftUI

struct VolumesView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmReclaim = false
    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !model.volumes.isEmpty { summaryBar }
                Group {
                    if model.volumes.isEmpty {
                        EmptyStateView(
                            symbol: "externaldrive",
                            title: "No volumes",
                            message: "Volumes provide persistent storage that outlives a container. Create one here, or by adding a volume when you run a container.",
                            actionTitle: "Create Volume…",
                            action: { showCreate = true }
                        )
                    } else {
                        List {
                            ForEach(model.volumes) { vol in
                                VolumeRow(volume: vol, usage: model.usage(of: vol)) {
                                    model.deleteVolume(vol)
                                }
                                .padding(.vertical, 6)
                            }
                        }
                        .listStyle(.inset)
                    }
                }
            }
            .navigationTitle("Volumes")
            .toolbar {
                ToolbarItem {
                    Button { showCreate = true } label: { Label("Create", systemImage: "plus") }
                }
                ToolbarItem {
                    Button { Task { await model.refreshAll(showSpinner: true) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .sheet(isPresented: $showCreate) { CreateVolumeSheet() }
        .confirmationDialog("Reclaim volume space?", isPresented: $confirmReclaim, titleVisibility: .visible) {
            Button("Reclaim \(Format.bytes(model.diskUsage?.volumes.reclaimable ?? 0))", role: .destructive) {
                model.reclaimVolumes()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes volumes that aren't referenced by any container. This permanently deletes their data and can't be undone.")
        }
    }

    private var summaryBar: some View {
        SummaryBar {
            MiniStat(value: "\(model.volumes.count)", label: "volumes")
            if let df = model.diskUsage?.volumes {
                MiniStat(value: "\(df.active)", label: "in use", dot: .green)
                Divider().frame(height: 16)
                MiniStat(value: Format.bytes(df.sizeInBytes), label: "on disk")
                if df.reclaimable > 0 {
                    MiniStat(value: Format.bytes(df.reclaimable), label: "reclaimable")
                    ReclaimButton(bytes: df.reclaimable) { confirmReclaim = true }
                }
            }
        }
    }
}

// MARK: - Volume row

private struct VolumeRow: View {
    let volume: CTVolume
    let usage: [(container: CTContainer, mount: CTContainer.Mount)]
    let onDelete: () -> Void

    private var anyRunning: Bool { usage.contains { $0.container.isRunning } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: icon, name, metadata badges, status, menu.
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "externaldrive.fill")
                    .font(.title3).foregroundStyle(Color.accentColor)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 5) {
                    Text(volume.name)
                        .font(.body.weight(.semibold))
                        .textSelection(.enabled)
                    HStack(spacing: 6) {
                        if let driver = volume.driver, !driver.isEmpty { Tag(driver) }
                        if let format = volume.format, !format.isEmpty { Tag(format) }
                        if let created = volume.createdDate {
                            Text("created \(Format.relative(created))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer(minLength: 8)

                if !usage.isEmpty {
                    StatusPill(running: anyRunning,
                               label: usage.count == 1 ? "In use" : "\(usage.count) containers")
                }

                Menu {
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 26)
            }

            // Host source path.
            if let source = volume.source, !source.isEmpty {
                Label(source, systemImage: "folder")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                    .padding(.leading, 38)
            }

            // Containers using this volume.
            usedBy.padding(.leading, 38)
        }
    }

    @ViewBuilder
    private var usedBy: some View {
        if usage.isEmpty {
            Label("Not used by any container", systemImage: "minus.circle")
                .font(.caption).foregroundStyle(.tertiary)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text("USED BY")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                ForEach(usage, id: \.container.id) { item in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(item.container.isRunning ? Color.green : Color.secondary.opacity(0.6))
                            .frame(width: 6, height: 6)
                        Text(item.container.id)
                            .font(.caption.weight(.medium))
                        Image(systemName: "arrow.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                        Text(item.mount.destination ?? "—")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        if item.mount.isReadOnly { Tag("ro") }
                    }
                }
            }
        }
    }
}

// MARK: - Small metadata tag

private struct Tag: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}
