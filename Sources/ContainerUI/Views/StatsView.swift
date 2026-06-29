import SwiftUI
import Charts

// MARK: - Sample

/// A single derived metrics point for plotting. CPU / disk / network values are
/// *rates* computed from the difference between two cumulative readings; memory
/// is an instantaneous gauge.
struct StatsSample: Identifiable, Equatable {
    let id = UUID()
    let time: Date
    let cpuPercent: Double      // may exceed 100% across multiple cores
    let memoryBytes: Double
    let memoryLimitBytes: Double
    let netRxRate: Double       // bytes/sec
    let netTxRate: Double       // bytes/sec
    let diskReadRate: Double    // bytes/sec
    let diskWriteRate: Double   // bytes/sec
    let processes: Int

    var netTotalRate: Double { netRxRate + netTxRate }
    var diskTotalRate: Double { diskReadRate + diskWriteRate }
}

// MARK: - Monitor

/// Polls `container stats` for one container on a timer and maintains a rolling
/// history of derived samples. Lives for as long as the Stats tab is on screen.
@MainActor
final class StatsMonitor: ObservableObject {
    @Published private(set) var samples: [StatsSample] = []
    @Published private(set) var latest: StatsSample?
    @Published private(set) var failed = false

    /// Roughly two minutes of history at the effective polling interval.
    private let maxSamples = 60
    /// Small pause *between* calls. Each `container stats` call already blocks
    /// ~2s (it samples over an internal window), so this need not be large —
    /// the command latency itself provides the `dt` for rate calculations.
    private let interval: UInt64 = 250_000_000 // 0.25s

    private let engine: ContainerEngine
    private let containerID: String
    private var previous: (stats: CTStats, time: Date)?
    private var task: Task<Void, Never>?

    init(containerID: String, engine: ContainerEngine = ContainerEngine()) {
        self.containerID = containerID
        self.engine = engine
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(nanoseconds: self?.interval ?? 2_000_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func poll() async {
        let now = Date()
        let reading: CTStats?
        do {
            reading = try await engine.stats(containerID)
        } catch {
            failed = true
            return
        }
        guard let current = reading else { failed = true; return }
        failed = false

        defer { previous = (current, now) }

        // First reading establishes a baseline; we need two to compute rates.
        guard let prev = previous else { return }
        let dt = now.timeIntervalSince(prev.time)
        guard dt > 0 else { return }

        // Counters reset on restart — clamp negative deltas to zero.
        func delta(_ a: Int64, _ b: Int64) -> Double { max(0, Double(a - b)) }

        let cpuPercent = delta(current.cpuUsageUsec, prev.stats.cpuUsageUsec) / (dt * 1_000_000) * 100
        let sample = StatsSample(
            time: now,
            cpuPercent: cpuPercent,
            memoryBytes: Double(current.memoryUsageBytes),
            memoryLimitBytes: Double(current.memoryLimitBytes),
            netRxRate: delta(current.networkRxBytes, prev.stats.networkRxBytes) / dt,
            netTxRate: delta(current.networkTxBytes, prev.stats.networkTxBytes) / dt,
            diskReadRate: delta(current.blockReadBytes, prev.stats.blockReadBytes) / dt,
            diskWriteRate: delta(current.blockWriteBytes, prev.stats.blockWriteBytes) / dt,
            processes: current.numProcesses)

        samples.append(sample)
        if samples.count > maxSamples { samples.removeFirst(samples.count - maxSamples) }
        latest = sample
    }
}

// MARK: - Stats tab

struct StatsView: View {
    let container: CTContainer
    /// Owned by `ContainerDetailView` so history survives tab switches.
    @ObservedObject var monitor: StatsMonitor

    var body: some View {
        Group {
            if !container.isRunning {
                EmptyStateView(symbol: "bolt.slash",
                               title: "Container not running",
                               message: "Start the container to see live CPU, memory, network and disk usage.")
            } else if monitor.failed && monitor.samples.isEmpty {
                EmptyStateView(symbol: "exclamationmark.triangle",
                               title: "Stats unavailable",
                               message: "Couldn't read resource statistics for this container.")
            } else {
                charts
            }
        }
    }

    private var charts: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if monitor.samples.isEmpty {
                    Label("Collecting live data…", systemImage: "waveform.path.ecg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                summaryTiles
                cpuChart
                memoryChart
                networkChart
                diskChart
            }
            .padding(20)
        }
    }

    // MARK: Summary tiles

    private var summaryTiles: some View {
        let s = monitor.latest
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                         spacing: 12) {
            StatTile(title: "CPU", value: s.map { Format.percent($0.cpuPercent) } ?? "—",
                     caption: "\(s?.processes ?? 0) processes", color: .blue, symbol: "cpu")
            StatTile(title: "Memory",
                     value: s.map { Format.byteCount($0.memoryBytes) } ?? "—",
                     caption: s.map { "of \(Format.byteCount($0.memoryLimitBytes))" } ?? "",
                     color: .purple, symbol: "memorychip")
            StatTile(title: "Network",
                     value: s.map { Format.rate($0.netTotalRate) } ?? "—",
                     caption: s.map { "↓\(Format.rate($0.netRxRate))  ↑\(Format.rate($0.netTxRate))" } ?? "",
                     color: .green, symbol: "network")
            StatTile(title: "Disk",
                     value: s.map { Format.rate($0.diskTotalRate) } ?? "—",
                     caption: s.map { "R \(Format.rate($0.diskReadRate))  W \(Format.rate($0.diskWriteRate))" } ?? "",
                     color: .orange, symbol: "internaldrive")
        }
    }

    // MARK: Charts

    private var cpuChart: some View {
        ChartCard(title: "CPU Usage", subtitle: "percent") {
            Chart(monitor.samples) { s in
                AreaMark(x: .value("Time", s.time), y: .value("CPU", s.cpuPercent))
                    .foregroundStyle(.linearGradient(
                        colors: [.blue.opacity(0.4), .blue.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", s.time), y: .value("CPU", s.cpuPercent))
                    .foregroundStyle(.blue)
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: 0...cpuMax)
            .chartYAxis { AxisMarks(format: Decimal.FormatStyle.Percent.percent.scale(1)) }
            .chartXAxis(.hidden)
        }
    }

    private var memoryChart: some View {
        let limit = monitor.latest?.memoryLimitBytes ?? 0
        return ChartCard(title: "Memory Usage", subtitle: "bytes") {
            Chart(monitor.samples) { s in
                AreaMark(x: .value("Time", s.time), y: .value("Memory", s.memoryBytes))
                    .foregroundStyle(.linearGradient(
                        colors: [.purple.opacity(0.4), .purple.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", s.time), y: .value("Memory", s.memoryBytes))
                    .foregroundStyle(.purple)
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: 0...(limit > 0 ? limit : (memoryMax * 1.2)))
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let bytes = value.as(Double.self) {
                            Text(Format.byteCount(bytes))
                        }
                    }
                }
            }
            .chartXAxis(.hidden)
        }
    }

    private var networkChart: some View {
        ChartCard(title: "Network I/O", subtitle: "per second") {
            Chart(monitor.samples) { s in
                LineMark(x: .value("Time", s.time), y: .value("Rate", s.netRxRate),
                         series: .value("Dir", "Download"))
                    .foregroundStyle(.green)
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", s.time), y: .value("Rate", s.netTxRate),
                         series: .value("Dir", "Upload"))
                    .foregroundStyle(.teal)
                    .interpolationMethod(.monotone)
            }
            .chartForegroundStyleScale(["Download": Color.green, "Upload": Color.teal])
            .chartYAxis { rateAxis }
            .chartXAxis(.hidden)
        }
    }

    private var diskChart: some View {
        ChartCard(title: "Disk I/O", subtitle: "per second") {
            Chart(monitor.samples) { s in
                LineMark(x: .value("Time", s.time), y: .value("Rate", s.diskReadRate),
                         series: .value("Op", "Read"))
                    .foregroundStyle(.orange)
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", s.time), y: .value("Rate", s.diskWriteRate),
                         series: .value("Op", "Write"))
                    .foregroundStyle(.pink)
                    .interpolationMethod(.monotone)
            }
            .chartForegroundStyleScale(["Read": Color.orange, "Write": Color.pink])
            .chartYAxis { rateAxis }
            .chartXAxis(.hidden)
        }
    }

    private var rateAxis: some AxisContent {
        AxisMarks { value in
            AxisGridLine()
            AxisValueLabel {
                if let bytes = value.as(Double.self) {
                    Text(Format.rate(bytes))
                }
            }
        }
    }

    // MARK: Y-axis domains

    private var cpuMax: Double {
        max(100, (monitor.samples.map(\.cpuPercent).max() ?? 0) * 1.2)
    }

    private var memoryMax: Double {
        max(1, monitor.samples.map(\.memoryBytes).max() ?? 1)
    }
}

// MARK: - Components

/// A compact headline metric with a caption, used in the summary grid.
private struct StatTile: View {
    let title: String
    let value: String
    let caption: String
    let color: Color
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(color)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// A titled card wrapping a fixed-height chart.
private struct ChartCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content
                .frame(height: 160)
        }
    }
}
