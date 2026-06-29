import SwiftUI

struct ContainersView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var fleet = FleetStatsMonitor()
    @State private var search = ""
    @State private var showStopped = true

    private var filtered: [CTContainer] {
        model.containers.filter { c in
            (showStopped || c.isRunning) &&
            (search.isEmpty
                || c.id.localizedCaseInsensitiveContains(search)
                || c.displayImage.localizedCaseInsensitiveContains(search))
        }
    }

    private var running: Int { model.containers.filter(\.isRunning).count }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !model.containers.isEmpty { summaryBar }
                Group {
                    if model.containers.isEmpty {
                        EmptyStateView(
                            symbol: "shippingbox",
                            title: "No containers yet",
                            message: "Run an image from the Images tab to create your first container. They’ll show up here, ready to start, stop and inspect."
                        )
                    } else if filtered.isEmpty {
                        EmptyStateView(symbol: "magnifyingglass", title: "No matches",
                                       message: "No containers match your filter.")
                    } else {
                        list
                    }
                }
            }
            .navigationTitle("Containers")
            .navigationDestination(for: CTContainer.self) { c in
                ContainerDetailView(containerID: c.id)
            }
            .toolbar { toolbar }
            .searchable(text: $search, placement: .toolbar, prompt: "Filter containers")
        }
        .onAppear { fleet.start { model.containers.filter(\.isRunning).map(\.id) } }
        .onDisappear { fleet.stop() }
    }

    // MARK: - Summary strip

    private var summaryBar: some View {
        let s = fleet.latest
        return SummaryBar {
            MiniStat(value: "\(model.containers.count)", label: "total")
            MiniStat(value: "\(running)", label: "running", dot: .green)
            MiniStat(value: "\(model.containers.count - running)", label: "stopped",
                     dot: .secondary.opacity(0.6))
            if running > 0, let s {
                Divider().frame(height: 16)
                MiniStat(value: Format.byteCount(s.memoryBytes), label: "memory")
                MiniStat(value: Format.percent(s.cpuPercent), label: "CPU")
            }
        }
    }

    private var list: some View {
        List {
            ForEach(filtered) { c in
                NavigationLink(value: c) {
                    ContainerRow(container: c)
                }
            }
        }
        .listStyle(.inset)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Toggle(isOn: $showStopped) {
                Label("Show stopped", systemImage: "eye")
            }
            .toggleStyle(.button)
            .help("Show stopped containers")
        }
        ToolbarItem(placement: .automatic) {
            Button { Task { await model.refreshAll(showSpinner: true) } } label: {
                if model.isRefreshing { ProgressView().controlSize(.small) }
                else { Image(systemName: "arrow.clockwise") }
            }
            .help("Refresh")
        }
    }
}

// MARK: - Row

struct ContainerRow: View {
    @EnvironmentObject var model: AppModel
    let container: CTContainer
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.title3)
                .foregroundStyle(container.isRunning ? Color.accentColor : .secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(container.id)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    StatusPill(running: container.isRunning)
                }
                HStack(spacing: 6) {
                    Text(container.displayImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let port = container.publishedPorts.first {
                        Text("· \(port.display)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            actions
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { menu }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 4) {
            if container.isRunning {
                if let url = container.firstWebURL {
                    CircleIconButton(symbol: "safari", help: "Open \(url.absoluteString)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                CircleIconButton(symbol: "stop.fill", help: "Stop", tint: .orange) {
                    model.stopContainer(container)
                }
            } else {
                CircleIconButton(symbol: "play.fill", help: "Start", tint: .green) {
                    model.startContainer(container)
                }
            }
            Menu {
                menu
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26)
            .menuIndicator(.hidden)
        }
        .opacity(hovering ? 1 : 0.55)
    }

    @ViewBuilder
    private var menu: some View {
        if container.isRunning {
            Button("Stop") { model.stopContainer(container) }
            Button("Restart") { model.restartContainer(container) }
        } else {
            Button("Start") { model.startContainer(container) }
        }
        if let url = container.firstWebURL {
            Button("Open in Browser") { NSWorkspace.shared.open(url) }
        }
        Divider()
        Button("Delete", role: .destructive) { model.deleteContainer(container) }
    }
}
