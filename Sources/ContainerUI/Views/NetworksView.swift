import SwiftUI

struct NetworksView: View {
    @EnvironmentObject var model: AppModel
    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !model.networks.isEmpty { summaryBar }
                Group {
                    if model.networks.isEmpty {
                        EmptyStateView(
                            symbol: "network",
                            title: "No networks",
                            message: "Networks let containers talk to each other and the host. Create one here, then attach containers to it when you run them.",
                            actionTitle: "Create Network…",
                            action: { showCreate = true }
                        )
                    } else {
                        List {
                            ForEach(model.networks) { net in
                                NetworkRow(network: net, usage: model.usage(of: net)) {
                                    model.deleteNetwork(net)
                                }
                                .padding(.vertical, 6)
                            }
                        }
                        .listStyle(.inset)
                    }
                }
            }
            .navigationTitle("Networks")
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
        .sheet(isPresented: $showCreate) { CreateNetworkSheet() }
    }

    private var summaryBar: some View {
        SummaryBar {
            MiniStat(value: "\(model.networks.count)", label: "networks")
            let inUse = model.networks.filter { !model.usage(of: $0).isEmpty }.count
            if inUse > 0 {
                MiniStat(value: "\(inUse)", label: "in use", dot: .green)
            }
        }
    }
}

// MARK: - Network row

private struct NetworkRow: View {
    let network: CTNetwork
    let usage: [(container: CTContainer, address: String?)]
    let onDelete: () -> Void

    private var anyRunning: Bool { usage.contains { $0.container.isRunning } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: icon, name, metadata badges, status, menu.
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "network")
                    .font(.title3).foregroundStyle(Color.accentColor)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(network.name)
                            .font(.body.weight(.semibold))
                            .textSelection(.enabled)
                        if network.isBuiltin { Tag("built-in") }
                    }
                    HStack(spacing: 6) {
                        if let mode = network.mode, !mode.isEmpty { Tag(mode.uppercased()) }
                        if let plugin = network.plugin, !plugin.isEmpty { Tag(plugin) }
                        if let created = network.createdDate {
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
                        .disabled(network.isBuiltin)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 26)
            }

            // Addressing.
            addressing.padding(.leading, 38)

            // Containers attached to this network.
            usedBy.padding(.leading, 38)
        }
    }

    @ViewBuilder
    private var addressing: some View {
        HStack(spacing: 16) {
            if let subnet = network.subnet, !subnet.isEmpty {
                labeled("subnet", subnet)
            }
            if let gateway = network.gateway, !gateway.isEmpty {
                labeled("gateway", gateway)
            }
            if let v6 = network.subnetV6, !v6.isEmpty {
                labeled("IPv6", v6)
            }
        }
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1).truncationMode(.middle)
        }
    }

    @ViewBuilder
    private var usedBy: some View {
        if usage.isEmpty {
            Label("Not connected to any container", systemImage: "minus.circle")
                .font(.caption).foregroundStyle(.tertiary)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text("CONNECTED")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                ForEach(usage, id: \.container.id) { item in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(item.container.isRunning ? Color.green : Color.secondary.opacity(0.6))
                            .frame(width: 6, height: 6)
                        Text(item.container.id)
                            .font(.caption.weight(.medium))
                        if let address = item.address, !address.isEmpty {
                            Image(systemName: "arrow.right")
                                .font(.caption2).foregroundStyle(.tertiary)
                            Text(address)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
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
