import SwiftUI

struct MachinesView: View {
    @EnvironmentObject var model: AppModel
    @State private var search = ""
    @State private var showCreate = false
    /// Explicit stack path so deleted machines can be popped out of it.
    @State private var path: [CTMachine] = []

    private var filtered: [CTMachine] {
        model.machines.filter { m in
            search.isEmpty
                || m.id.localizedCaseInsensitiveContains(search)
        }
    }

    private var running: Int { model.machines.filter(\.isRunning).count }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                if !model.machines.isEmpty { summaryBar }
                Group {
                    if model.machines.isEmpty {
                        EmptyStateView(
                            symbol: "desktopcomputer",
                            title: "No machines yet",
                            message: "Container machines are lightweight Linux virtual machines with your home folder mounted inside. Create one from an init-capable image (like alpine) and open a shell — no terminal setup required.",
                            actionTitle: "Create Machine…",
                            action: { showCreate = true }
                        )
                    } else if filtered.isEmpty {
                        EmptyStateView(symbol: "magnifyingglass", title: "No matches",
                                       message: "No machines match your filter.")
                    } else {
                        list
                    }
                }
            }
            .navigationTitle("Machines")
            .navigationDestination(for: CTMachine.self) { m in
                MachineDetailView(machineID: m.id)
            }
            .toolbar { toolbar }
            .searchable(text: $search, placement: .toolbar, prompt: "Filter machines")
        }
        // If a machine on the stack is deleted (from its own detail page or
        // externally), pop it so the user isn't stranded on a dead page.
        .onChange(of: model.machines) { _, machines in
            let ids = Set(machines.map(\.id))
            let pruned = path.filter { ids.contains($0.id) }
            if pruned.count != path.count { path = pruned }
        }
        .sheet(isPresented: $showCreate) { CreateMachineSheet() }
    }

    // MARK: - Summary strip

    private var summaryBar: some View {
        let disk = model.machines.reduce(Int64(0)) { $0 + ($1.diskSize ?? 0) }
        return SummaryBar {
            MiniStat(value: "\(model.machines.count)", label: "total")
            MiniStat(value: "\(running)", label: "running", dot: .green)
            MiniStat(value: "\(model.machines.count - running)", label: "stopped",
                     dot: .secondary.opacity(0.6))
            if disk > 0 {
                Divider().frame(height: 16)
                MiniStat(value: Format.bytes(disk), label: "on disk")
            }
        }
    }

    private var list: some View {
        List {
            ForEach(filtered) { m in
                NavigationLink(value: m) {
                    MachineRow(machine: m)
                }
            }
        }
        .listStyle(.inset)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button { showCreate = true } label: { Label("Create", systemImage: "plus") }
                .help("Create a new machine")
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

struct MachineRow: View {
    @EnvironmentObject var model: AppModel
    let machine: CTMachine
    @State private var hovering = false

    private var busy: Bool { model.busyMachines.contains(machine.id) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.title3)
                .foregroundStyle(machine.isRunning ? Color.accentColor : .secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(machine.id)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if machine.isDefault {
                        DefaultBadge()
                    }
                    StatusPill(running: machine.isRunning)
                }
                HStack(spacing: 6) {
                    if let cpus = machine.cpus {
                        Text("\(cpus) CPUs")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let mem = machine.memory {
                        Text("· \(Format.memory(mem))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let disk = machine.diskSize, disk > 0 {
                        Text("· \(Format.bytes(disk)) disk")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    if let ip = machine.ip, !ip.isEmpty {
                        Text("· \(ip)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
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
            if busy {
                ProgressView().controlSize(.small).frame(width: 26)
            } else if machine.isRunning {
                CircleIconButton(symbol: "stop.fill", help: "Stop", tint: .orange) {
                    model.stopMachine(machine)
                }
            } else {
                CircleIconButton(symbol: "play.fill", help: "Boot", tint: .green) {
                    model.startMachine(machine)
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
        .opacity(hovering || busy ? 1 : 0.55)
    }

    @ViewBuilder
    private var menu: some View {
        if machine.isRunning {
            Button("Stop") { model.stopMachine(machine) }
            Button("Restart") { model.restartMachine(machine) }
        } else {
            Button("Boot") { model.startMachine(machine) }
        }
        if !machine.isDefault {
            Button("Set as Default") { model.setDefaultMachine(machine) }
        }
        Divider()
        Button("Delete", role: .destructive) { model.deleteMachine(machine) }
    }
}

// MARK: - Default badge

/// A small star chip marking the default machine (the one CLI commands target
/// when no name is given).
struct DefaultBadge: View {
    var body: some View {
        Label("Default", systemImage: "star.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.yellow)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.yellow.opacity(0.13), in: Capsule())
            .help("Commands without a machine name target this machine")
    }
}
