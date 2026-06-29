import SwiftUI

struct ImagesView: View {
    @EnvironmentObject var model: AppModel
    @State private var search = ""
    @State private var showPull = false
    @State private var runTarget: CTImage?
    @State private var confirmReclaim = false

    private var filtered: [CTImage] {
        model.images.filter {
            search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !model.images.isEmpty { summaryBar }
                Group {
                    if model.images.isEmpty {
                        EmptyStateView(
                            symbol: "square.stack.3d.up",
                            title: "No images",
                            message: "Pull an image from a registry to get started — for example alpine, nginx or postgres.",
                            actionTitle: "Pull Image…",
                            action: { showPull = true }
                        )
                    } else {
                        list
                    }
                }
            }
            .navigationTitle("Images")
            .toolbar {
                ToolbarItem {
                    Button { showPull = true } label: { Label("Pull", systemImage: "arrow.down.circle") }
                }
                ToolbarItem {
                    Button { Task { await model.refreshAll(showSpinner: true) } } label: {
                        if model.isRefreshing { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.clockwise") }
                    }
                }
            }
            .searchable(text: $search, prompt: "Filter images")
        }
        .sheet(isPresented: $showPull) { PullSheet() }
        .sheet(item: $runTarget) { image in RunSheet(image: image) }
        .confirmationDialog("Reclaim image space?", isPresented: $confirmReclaim, titleVisibility: .visible) {
            Button("Reclaim \(Format.bytes(model.diskUsage?.images.reclaimable ?? 0))", role: .destructive) {
                model.reclaimImages()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes all images not used by any container. This can't be undone, but the images can be pulled again.")
        }
    }

    private var summaryBar: some View {
        SummaryBar {
            MiniStat(value: "\(model.images.count)", label: "images")
            if let df = model.diskUsage?.images {
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

    private var list: some View {
        List {
            ForEach(filtered) { image in
                ImageRow(image: image, onRun: { runTarget = image })
            }
        }
        .listStyle(.inset)
    }
}

struct ImageRow: View {
    @EnvironmentObject var model: AppModel
    let image: CTImage
    let onRun: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(image.repository)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text(image.tag)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
                HStack(spacing: 8) {
                    Text(image.shortDigest)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    if image.createdDate != nil {
                        Text("· \(Format.relative(image.createdDate))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Button(action: onRun) { Label("Run", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Menu {
                    Button("Run…", action: onRun)
                    Divider()
                    Button("Delete", role: .destructive) { model.deleteImage(image) }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 26)
            }
            .opacity(hovering ? 1 : 0.7)
        }
        .padding(.vertical, 5)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Run…", action: onRun)
            Button("Delete", role: .destructive) { model.deleteImage(image) }
        }
    }
}
