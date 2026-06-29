import SwiftUI

struct ContainerDetailView: View {
    @EnvironmentObject var model: AppModel
    let containerID: String

    @State private var tab = 0
    @State private var rawJSON = ""
    /// Lives at the detail level (not inside the Stats tab) so the metrics
    /// history keeps accumulating while you're on other tabs and isn't reset
    /// when you switch back. Fresh per container thanks to the navigation push.
    @StateObject private var monitor: StatsMonitor

    init(containerID: String) {
        self.containerID = containerID
        _monitor = StateObject(wrappedValue: StatsMonitor(containerID: containerID))
    }

    private var container: CTContainer? {
        model.containers.first { $0.id == containerID }
    }

    var body: some View {
        Group {
            if let c = container {
                content(c)
            } else {
                EmptyStateView(symbol: "questionmark.folder", title: "Container unavailable",
                               message: "This container no longer exists.")
            }
        }
        .navigationTitle(containerID)
    }

    private func content(_ c: CTContainer) -> some View {
        VStack(spacing: 0) {
            header(c)
            Picker("", selection: $tab) {
                Text("Overview").tag(0)
                Text("Stats").tag(1)
                Text("Logs").tag(2)
                Text("Console").tag(3)
                Text("Inspect").tag(4)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            Divider()

            switch tab {
            case 1: StatsView(container: c, monitor: monitor)
            case 2: LogsView(containerID: c.id)
            case 3: consoleTab(c)
            case 4: inspectTab(c)
            default: overviewTab(c)
            }
        }
        // Start collecting as soon as the container opens (a head start before
        // the user reaches the Stats tab) and keep running across tab switches.
        .onAppear { if c.isRunning { monitor.start() } }
        .onDisappear { monitor.stop() }
        .onChange(of: c.isRunning) { _, running in
            if running { monitor.start() } else { monitor.stop() }
        }
    }

    // MARK: Header

    private func header(_ c: CTContainer) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 30))
                .foregroundStyle(c.isRunning ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(c.id).font(.title2.weight(.bold))
                HStack(spacing: 8) {
                    StatusPill(running: c.isRunning)
                    Text(c.displayImage).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            controls(c)
        }
        .padding(20)
    }

    private func controls(_ c: CTContainer) -> some View {
        HStack(spacing: 10) {
            if let url = c.firstWebURL, c.isRunning {
                Button { NSWorkspace.shared.open(url) } label: {
                    Label("Open", systemImage: "safari")
                }
            }
            if c.isRunning {
                Button { model.restartContainer(c) } label: { Label("Restart", systemImage: "arrow.clockwise") }
                Button { model.stopContainer(c) } label: { Label("Stop", systemImage: "stop.fill") }
                    .tint(.orange)
            } else {
                Button { model.startContainer(c) } label: { Label("Start", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
            }
            Menu {
                Button("Delete", role: .destructive) { model.deleteContainer(c) }
            } label: { Image(systemName: "ellipsis.circle") }
            .frame(width: 30)
        }
    }

    // MARK: Overview

    private func overviewTab(_ c: CTContainer) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    Text("General").font(.headline)
                    MetaRow("Name", c.id)
                    MetaRow("Image", c.displayImage)
                    MetaRow("Command", c.command, mono: true)
                    MetaRow("State", c.status.state.capitalized)
                    MetaRow("Created", Format.relative(c.createdDate))
                    if let arch = c.configuration.platform?.architecture {
                        MetaRow("Platform", "\(c.configuration.platform?.os ?? "linux")/\(arch)")
                    }
                }

                Card {
                    Text("Resources").font(.headline)
                    MetaRow("CPUs", c.configuration.resources?.cpus.map(String.init) ?? "default")
                    MetaRow("Memory", Format.memory(c.configuration.resources?.memoryInBytes))
                }

                Card {
                    Text("Network").font(.headline)
                    MetaRow("IP Address", c.primaryIPv4 ?? "—", mono: true)
                    if c.publishedPorts.isEmpty {
                        MetaRow("Ports", "None published")
                    } else {
                        ForEach(c.publishedPorts, id: \.self) { port in
                            MetaRow("Port", port.display, mono: true)
                        }
                    }
                }

                if let env = c.configuration.initProcess?.environment, !env.isEmpty {
                    Card {
                        Text("Environment").font(.headline)
                        ForEach(env, id: \.self) { line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: Console (interactive shell)

    @ViewBuilder
    private func consoleTab(_ c: CTContainer) -> some View {
        if c.isRunning {
            ConsoleView(containerID: c.id)
        } else {
            EmptyStateView(symbol: "terminal",
                           title: "Container not running",
                           message: "Start the container to open an interactive shell.")
        }
    }

    // MARK: Inspect (raw JSON)

    private func inspectTab(_ c: CTContainer) -> some View {
        ScrollView {
            Text(rawJSON.isEmpty ? "Loading…" : rawJSON)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .clipped()
        .task(id: c.id) {
            rawJSON = (try? await model.engine.inspectContainerRaw(c.id)) ?? "Failed to load."
        }
    }
}
