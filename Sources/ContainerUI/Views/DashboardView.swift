import SwiftUI

// MARK: - Fleet stats monitor

/// Polls `container stats` across *all* running containers on a timer and
/// maintains a rolling aggregate of their combined resource usage.
///
/// Each `container stats --no-stream` call blocks ~2s, so the running
/// containers are polled concurrently — a round takes roughly as long as the
/// slowest single container rather than the sum. Cumulative counters are
/// differenced per-container (the same technique as `StatsMonitor`) and the
/// derived rates are summed into one fleet-wide figure.
@MainActor
final class FleetStatsMonitor: ObservableObject {

    /// A combined reading across every running container at one instant.
    struct Aggregate: Equatable {
        var time: Date
        var cpuPercent: Double      // summed across containers; may exceed 100%
        var memoryBytes: Double
        var memoryLimitBytes: Double
        var netRxRate: Double       // bytes/sec
        var netTxRate: Double       // bytes/sec
        var diskReadRate: Double    // bytes/sec
        var diskWriteRate: Double   // bytes/sec
        var processes: Int
        var containerCount: Int     // containers contributing to this reading

        var netTotalRate: Double { netRxRate + netTxRate }
        var diskTotalRate: Double { diskReadRate + diskWriteRate }
        var memoryFraction: Double {
            guard memoryLimitBytes > 0 else { return 0 }
            return min(1, memoryBytes / memoryLimitBytes)
        }
    }

    @Published private(set) var latest: Aggregate?
    @Published private(set) var samples: [Aggregate] = []

    private let maxSamples = 60
    /// Pause between rounds. The `container stats` latency itself supplies the
    /// `dt` used for rate derivation, so this only paces successive rounds.
    private let interval: UInt64 = 1_000_000_000 // 1s

    private let engine: ContainerEngine
    private var idsProvider: (() -> [String])?
    private var previous: [String: (stats: CTStats, time: Date)] = [:]
    private var task: Task<Void, Never>?

    init(engine: ContainerEngine = ContainerEngine()) {
        self.engine = engine
    }

    /// Begin polling. `ids` is evaluated each round so the monitor tracks
    /// containers as they start and stop.
    func start(ids: @escaping () -> [String]) {
        idsProvider = ids
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(nanoseconds: self?.interval ?? 1_000_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func poll() async {
        let ids = idsProvider?() ?? []
        let now = Date()

        guard !ids.isEmpty else {
            previous.removeAll()
            latest = Aggregate(time: now, cpuPercent: 0, memoryBytes: 0, memoryLimitBytes: 0,
                               netRxRate: 0, netTxRate: 0, diskReadRate: 0, diskWriteRate: 0,
                               processes: 0, containerCount: 0)
            return
        }

        // Poll every running container concurrently.
        let engine = self.engine
        let readings: [(String, CTStats)] = await withTaskGroup(of: (String, CTStats?).self) { group in
            for id in ids {
                group.addTask { (id, try? await engine.stats(id)) }
            }
            var out: [(String, CTStats)] = []
            for await (id, reading) in group {
                if let reading { out.append((id, reading)) }
            }
            return out
        }

        var agg = Aggregate(time: now, cpuPercent: 0, memoryBytes: 0, memoryLimitBytes: 0,
                            netRxRate: 0, netTxRate: 0, diskReadRate: 0, diskWriteRate: 0,
                            processes: 0, containerCount: readings.count)
        var newPrevious: [String: (stats: CTStats, time: Date)] = [:]

        // Counters reset on restart — clamp negative deltas to zero.
        func delta(_ a: Int64, _ b: Int64) -> Double { max(0, Double(a - b)) }

        for (id, current) in readings {
            agg.memoryBytes += Double(current.memoryUsageBytes)
            agg.memoryLimitBytes += Double(current.memoryLimitBytes)
            agg.processes += current.numProcesses

            if let prev = previous[id] {
                let dt = now.timeIntervalSince(prev.time)
                if dt > 0 {
                    agg.cpuPercent += delta(current.cpuUsageUsec, prev.stats.cpuUsageUsec) / (dt * 1_000_000) * 100
                    agg.netRxRate += delta(current.networkRxBytes, prev.stats.networkRxBytes) / dt
                    agg.netTxRate += delta(current.networkTxBytes, prev.stats.networkTxBytes) / dt
                    agg.diskReadRate += delta(current.blockReadBytes, prev.stats.blockReadBytes) / dt
                    agg.diskWriteRate += delta(current.blockWriteBytes, prev.stats.blockWriteBytes) / dt
                }
            }
            newPrevious[id] = (current, now)
        }

        previous = newPrevious
        latest = agg
        samples.append(agg)
        if samples.count > maxSamples { samples.removeFirst(samples.count - maxSamples) }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var fleet = FleetStatsMonitor()

    private var running: Int { model.containers.filter(\.isRunning).count }
    private var stopped: Int { model.containers.count - running }
    private var totalImageSize: Int64 {
        model.images.reduce(0) { $0 + ($1.configuration.descriptor?.size ?? 0) }
    }
    /// Prefer the engine's real disk figure, falling back to a descriptor sum.
    private var imageSizeText: String? {
        if let s = model.diskUsage?.images.sizeInBytes, s > 0 { return "\(Format.bytes(s)) on disk" }
        return totalImageSize > 0 ? "\(Format.bytes(totalImageSize)) on disk" : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    heroBanner
                    kpiGrid
                    librarySection
                    diskUsageSection
                    networksSection
                    engineSection
                }
                .padding(24)
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button { Task { await model.refreshAll(showSpinner: true) } } label: {
                        if model.isRefreshing { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.clockwise") }
                    }
                    .help("Refresh")
                }
            }
        }
        .onAppear { fleet.start { model.containers.filter(\.isRunning).map(\.id) } }
        .onDisappear { fleet.stop() }
    }

    // MARK: Hero banner

    /// The brand gradient: fresh aqua → blue → deep indigo (matches the app icon).
    private var brandGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.20, green: 0.84, blue: 0.75),
                Color(red: 0.17, green: 0.56, blue: 0.90),
                Color(red: 0.36, green: 0.18, blue: 0.77)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var heroBanner: some View {
        HStack(spacing: 20) {
            if let logo = NSImage.appLogo {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 88, height: 88)
                    .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Skipper")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                Text("Apple Containers, images and volumes — all in one place.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.engineRunning ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                        .shadow(color: model.engineRunning ? .green.opacity(0.7) : .clear, radius: 3)
                    Text(model.engineRunning ? "Engine running" : "Engine stopped")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(.white.opacity(0.18)))

                if let version = model.systemStatus?.version {
                    Text("v\(version)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(brandGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
    }

    // MARK: Primary KPIs

    private var kpiGrid: some View {
        let s = fleet.latest
        let history = fleet.samples
        return VStack(alignment: .leading, spacing: 10) {
            Text("Overview").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                      spacing: 12) {
                KPITile(title: "Containers",
                        value: "\(model.containers.count)",
                        caption: "\(running) running · \(stopped) stopped",
                        symbol: "shippingbox.fill", tint: .accentColor,
                        spark: history.map { Double($0.containerCount) },
                        action: { model.selection = .containers })
                KPITile(title: "Memory",
                        value: s.map { Format.byteCount($0.memoryBytes) } ?? "—",
                        caption: liveCaption(running == 0 ? "no running containers"
                                             : "of \(Format.byteCount(s?.memoryLimitBytes ?? 0)) limit"),
                        symbol: "memorychip", tint: .purple,
                        spark: history.map(\.memoryBytes),
                        action: { model.selection = .containers })
                KPITile(title: "CPU",
                        value: s.map { Format.percent($0.cpuPercent) } ?? "—",
                        caption: liveCaption("\(s?.processes ?? 0) processes"),
                        symbol: "cpu", tint: .blue,
                        spark: history.map(\.cpuPercent),
                        action: { model.selection = .containers })
                KPITile(title: "Network",
                        value: s.map { Format.rate($0.netTotalRate) } ?? "—",
                        caption: s.map { "↓\(Format.rate($0.netRxRate))  ↑\(Format.rate($0.netTxRate))" }
                            ?? "—",
                        symbol: "network", tint: .green,
                        spark: history.map(\.netTotalRate),
                        action: { model.selection = .containers })
            }
        }
    }

    /// Tags a caption as live data once a reading exists.
    private func liveCaption(_ text: String) -> String {
        running > 0 && fleet.latest != nil ? "live · \(text)" : text
    }

    // MARK: Library (images / volumes)

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Library").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                      spacing: 12) {
                KPITile(title: "Images",
                        value: "\(model.images.count)",
                        caption: imageSizeText,
                        symbol: "square.stack.3d.up.fill", tint: .orange,
                        action: { model.selection = .images })
                KPITile(title: "Volumes",
                        value: "\(model.volumes.count)",
                        caption: model.volumes.isEmpty ? "none" : "persistent storage",
                        symbol: "externaldrive.fill", tint: .teal,
                        action: { model.selection = .volumes })
            }
        }
    }

    // MARK: Disk usage

    @ViewBuilder
    private var diskUsageSection: some View {
        if let df = model.diskUsage {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Disk Usage").font(.headline)
                    Spacer()
                    if df.totalReclaimable > 0 {
                        Text("\(Format.bytes(df.totalReclaimable)) reclaimable")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Card {
                    DiskUsageRow(symbol: "square.stack.3d.up.fill", tint: .orange,
                                 name: "Images", entry: df.images)
                    Divider()
                    DiskUsageRow(symbol: "shippingbox.fill", tint: .accentColor,
                                 name: "Containers", entry: df.containers)
                    Divider()
                    DiskUsageRow(symbol: "externaldrive.fill", tint: .teal,
                                 name: "Volumes", entry: df.volumes)
                }
            }
        }
    }

    // MARK: Networks

    @ViewBuilder
    private var networksSection: some View {
        if !model.networks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Networks").font(.headline)
                Card {
                    ForEach(Array(model.networks.enumerated()), id: \.element.id) { index, net in
                        if index > 0 { Divider() }
                        NetworkRow(network: net)
                    }
                }
            }
        }
    }

    // MARK: Engine

    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Engine").font(.headline)
            Card {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.title2)
                        .foregroundStyle(model.engineRunning ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Containers")
                            .font(.body.weight(.semibold))
                        Text(model.engineRunning ? "Engine is running" : "Engine is stopped")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(running: model.engineRunning,
                               label: model.engineRunning ? "Running" : "Stopped")
                }
                if let status = model.systemStatus {
                    Divider()
                    if let version = status.version { MetaRow("Version", version) }
                    if let path = status.appRoot { MetaRow("App data", path, mono: true) }
                    if let path = status.installRoot { MetaRow("Install root", path, mono: true) }
                }
            }
        }
    }
}

// MARK: - Bundled app logo

extension NSImage {
    /// The app logo (squircle with transparent corners), loaded once from the
    /// SwiftPM resource bundle for use in-app (e.g. the dashboard hero banner).
    static let appLogo: NSImage? = {
        guard let url = Bundle.module.url(forResource: "SkipperLogo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
}

// MARK: - Row helpers

/// One line in the Disk Usage card: a resource type with its size and
/// reclaimable space.
private struct DiskUsageRow: View {
    let symbol: String
    let tint: Color
    let name: String
    let entry: CTDiskUsage.Entry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body.weight(.medium))
                Text("\(entry.active) of \(entry.total) active")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.bytes(entry.sizeInBytes))
                    .font(.body.weight(.semibold).monospacedDigit())
                if entry.reclaimable > 0 {
                    Text("\(Format.bytes(entry.reclaimable)) reclaimable")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("fully in use").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

/// One line in the Networks card.
private struct NetworkRow: View {
    let network: CTNetwork

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "network").foregroundStyle(.green).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(network.name).font(.body.weight(.medium))
                    if let mode = network.mode {
                        Text(mode.uppercased())
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                if let subnet = network.subnet {
                    Text(subnet)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let gateway = network.gateway {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("gateway").font(.caption2).foregroundStyle(.tertiary)
                    Text(gateway)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
