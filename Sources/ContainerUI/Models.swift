import Foundation

// MARK: - Container

/// A container as reported by `container list --all --format json`.
struct CTContainer: Codable, Identifiable, Hashable {
    let configuration: Configuration
    let status: Status

    var id: String { configuration.id }

    struct Configuration: Codable, Hashable {
        let id: String
        let image: ImageRef
        let initProcess: InitProcess?
        let resources: Resources?
        let labels: [String: String]?
        let networks: [NetworkConfig]?
        let publishedPorts: [PublishedPort]?
        let platform: Platform?
        let creationDate: String?
        let mounts: [Mount]?
    }

    /// A filesystem mount attached to a container. `type.volume` is present for
    /// named volumes; bind mounts use other type keys (e.g. `virtiofs`).
    struct Mount: Codable, Hashable {
        let destination: String?
        let source: String?
        let options: [String]?
        let type: MountType?

        struct MountType: Codable, Hashable {
            let volume: VolumeRef?

            struct VolumeRef: Codable, Hashable {
                let name: String?
                let format: String?
            }
        }

        /// Name of the named volume this mount references, if any.
        var volumeName: String? { type?.volume?.name }
        var isReadOnly: Bool { options?.contains("ro") ?? false }
    }

    struct ImageRef: Codable, Hashable {
        let reference: String
    }

    struct InitProcess: Codable, Hashable {
        let executable: String?
        let arguments: [String]?
        let environment: [String]?
        let workingDirectory: String?
    }

    struct Resources: Codable, Hashable {
        let cpus: Int?
        let memoryInBytes: Int64?
    }

    struct NetworkConfig: Codable, Hashable {
        let network: String?
    }

    struct Platform: Codable, Hashable {
        let architecture: String?
        let os: String?
    }

    struct Status: Codable, Hashable {
        let state: String
        let startedDate: String?
        let networks: [NetStatus]?
    }

    struct NetStatus: Codable, Hashable {
        let ipv4Address: String?
        let hostname: String?
        let network: String?
    }

    // MARK: Convenience

    var isRunning: Bool { status.state.lowercased() == "running" }

    /// Image reference without the registry/namespace noise, e.g. `alpine:latest`.
    var displayImage: String { Self.shortImageName(configuration.image.reference) }

    var command: String {
        let exe = configuration.initProcess?.executable ?? ""
        let args = configuration.initProcess?.arguments ?? []
        return ([exe] + args).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    var publishedPorts: [PublishedPort] { configuration.publishedPorts ?? [] }

    var mounts: [Mount] { configuration.mounts ?? [] }

    var primaryIPv4: String? {
        status.networks?.first?.ipv4Address?.components(separatedBy: "/").first
    }

    /// First TCP published port that we can open in a browser, if any.
    var firstWebURL: URL? {
        for port in publishedPorts where (port.proto ?? "tcp") == "tcp" {
            let host = (port.hostAddress == "0.0.0.0" || port.hostAddress == nil)
                ? "localhost" : port.hostAddress!
            return URL(string: "http://\(host):\(port.hostPort)")
        }
        return nil
    }

    var createdDate: Date? { ISO8601DateFormatter.engine.date(from: configuration.creationDate ?? "") }

    static func shortImageName(_ ref: String) -> String {
        var s = ref
        for prefix in ["docker.io/library/", "docker.io/", "registry-1.docker.io/library/"] {
            if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)) }
        }
        return s
    }
}

struct PublishedPort: Codable, Hashable {
    let containerPort: Int
    let hostPort: Int
    let hostAddress: String?
    let proto: String?

    var display: String {
        let host = (hostAddress == "0.0.0.0" || hostAddress == nil) ? "" : "\(hostAddress!):"
        return "\(host)\(hostPort) → \(containerPort)/\(proto ?? "tcp")"
    }
}

// MARK: - Stats

/// A single resource-usage reading from `container stats --format json`.
///
/// All of the byte/CPU counters are *cumulative* since the container started,
/// so meaningful CPU/disk/network rates are derived by differencing two
/// readings over wall-clock time (see `StatsMonitor`). `memoryUsageBytes` is
/// the only true gauge.
struct CTStats: Codable, Identifiable, Hashable {
    let id: String
    let cpuUsageUsec: Int64
    let memoryUsageBytes: Int64
    let memoryLimitBytes: Int64
    let blockReadBytes: Int64
    let blockWriteBytes: Int64
    let networkRxBytes: Int64
    let networkTxBytes: Int64
    let numProcesses: Int

    var memoryFraction: Double {
        guard memoryLimitBytes > 0 else { return 0 }
        return min(1, Double(memoryUsageBytes) / Double(memoryLimitBytes))
    }
}

// MARK: - Image

/// An image as reported by `container image list --format json`.
struct CTImage: Codable, Identifiable, Hashable {
    let id: String
    let configuration: ImageConfig

    var name: String { configuration.name }

    struct ImageConfig: Codable, Hashable {
        let name: String
        let descriptor: Descriptor?
        let creationDate: String?
    }

    struct Descriptor: Codable, Hashable {
        let size: Int64?
        let digest: String?
    }

    var displayName: String { CTContainer.shortImageName(name) }

    var repository: String {
        let short = displayName
        return short.components(separatedBy: ":").first ?? short
    }

    var tag: String {
        let short = displayName
        let parts = short.components(separatedBy: ":")
        return parts.count > 1 ? parts.last! : "latest"
    }

    var shortDigest: String {
        let d = configuration.descriptor?.digest ?? id
        let hex = d.replacingOccurrences(of: "sha256:", with: "")
        return String(hex.prefix(12))
    }

    var createdDate: Date? { ISO8601DateFormatter.engine.date(from: configuration.creationDate ?? "") }
}

// MARK: - Volume

struct CTVolume: Decodable, Identifiable, Hashable {
    let name: String
    let driver: String?
    let format: String?
    let source: String?
    let sizeInBytes: Int64?
    let labels: [String: String]?
    let creationDate: String?

    var id: String { name }

    /// `container volume list` nests everything under a `configuration` object,
    /// e.g. `{"configuration": {"name": …, "driver": …}, "id": …}`. We also
    /// tolerate a flat shape (and a `mountpoint` alias for `source`) so the
    /// decode is robust across CLI versions.
    private enum CodingKeys: String, CodingKey {
        case configuration, name, driver, format, source, mountpoint, sizeInBytes, labels, creationDate
    }

    init(from decoder: Decoder) throws {
        let outer = try decoder.container(keyedBy: CodingKeys.self)
        let c = (try? outer.nestedContainer(keyedBy: CodingKeys.self, forKey: .configuration)) ?? outer
        name = (try? c.decode(String.self, forKey: .name)) ?? "volume"
        driver = try? c.decode(String.self, forKey: .driver)
        format = try? c.decode(String.self, forKey: .format)
        source = (try? c.decode(String.self, forKey: .source))
            ?? (try? c.decode(String.self, forKey: .mountpoint))
        sizeInBytes = try? c.decode(Int64.self, forKey: .sizeInBytes)
        labels = try? c.decode([String: String].self, forKey: .labels)
        creationDate = try? c.decode(String.self, forKey: .creationDate)
    }

    var createdDate: Date? { ISO8601DateFormatter.engine.date(from: creationDate ?? "") }
}

// MARK: - Machine

/// A container machine (a lightweight Linux VM) as reported by
/// `container machine list --format json` / `container machine inspect`.
///
/// The two commands share a base shape; `inspect` adds `image`, `homeMount`,
/// `platform` and `userSetup`, so those are optional and only populated on the
/// detail screen. Decoding is tolerant so both shapes flow through one type.
struct CTMachine: Codable, Identifiable, Hashable {
    let id: String
    let status: String
    let cpus: Int?
    let memory: Int64?
    let diskSize: Int64?
    let createdDate: String?
    let isDefault: Bool
    let ip: String?

    // Inspect-only extras.
    let image: ImageRef?
    let homeMount: String?
    let platform: Platform?
    let userSetup: UserSetup?

    struct ImageRef: Codable, Hashable {
        let reference: String
    }

    struct Platform: Codable, Hashable {
        let architecture: String?
        let os: String?
    }

    struct UserSetup: Codable, Hashable {
        let username: String?
        let uid: Int?
        let gid: Int?
    }

    private enum CodingKeys: String, CodingKey {
        case id, status, cpus, memory, diskSize, createdDate, ip, ipAddress
        case isDefault = "default"
        case image, homeMount, platform, userSetup
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        status = (try? c.decode(String.self, forKey: .status)) ?? "unknown"
        cpus = try? c.decode(Int.self, forKey: .cpus)
        memory = try? c.decode(Int64.self, forKey: .memory)
        diskSize = try? c.decode(Int64.self, forKey: .diskSize)
        createdDate = try? c.decode(String.self, forKey: .createdDate)
        isDefault = (try? c.decode(Bool.self, forKey: .isDefault)) ?? false
        ip = (try? c.decode(String.self, forKey: .ip))
            ?? (try? c.decode(String.self, forKey: .ipAddress))
        image = try? c.decode(ImageRef.self, forKey: .image)
        homeMount = try? c.decode(String.self, forKey: .homeMount)
        platform = try? c.decode(Platform.self, forKey: .platform)
        userSetup = try? c.decode(UserSetup.self, forKey: .userSetup)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(cpus, forKey: .cpus)
        try c.encodeIfPresent(memory, forKey: .memory)
        try c.encodeIfPresent(diskSize, forKey: .diskSize)
        try c.encodeIfPresent(createdDate, forKey: .createdDate)
        try c.encode(isDefault, forKey: .isDefault)
        try c.encodeIfPresent(ip, forKey: .ip)
    }

    // MARK: Convenience

    var isRunning: Bool { status.lowercased() == "running" }

    var displayImage: String? {
        image.map { CTContainer.shortImageName($0.reference) }
    }

    var createdAt: Date? { ISO8601DateFormatter.engine.date(from: createdDate ?? "") }

    /// Memory rendered the way `machine set` accepts it (e.g. `8G`, `512M`).
    var memorySetting: String? {
        guard let memory, memory > 0 else { return nil }
        let gib: Int64 = 1_073_741_824
        if memory % gib == 0 { return "\(memory / gib)G" }
        return "\(memory / 1_048_576)M"
    }
}

// MARK: - System status

/// Output of `container system status --format json`.
struct CTSystemStatus: Codable, Hashable {
    let status: String?
    let apiServerVersion: String?
    let appRoot: String?
    let installRoot: String?

    var isRunning: Bool { (status ?? "").lowercased() == "running" }

    /// A clean semantic version (e.g. `1.0.0`) parsed from the verbose
    /// apiserver string, falling back to the raw value.
    var version: String? {
        guard let raw = apiServerVersion, !raw.isEmpty else { return nil }
        // e.g. "container-apiserver version 1.0.0 (build: release, commit: …)"
        let parts = raw.split(separator: " ")
        if let idx = parts.firstIndex(of: "version"), idx + 1 < parts.count {
            return String(parts[idx + 1])
        }
        return raw
    }
}

// MARK: - Disk usage

/// Output of `container system df --format json`.
struct CTDiskUsage: Codable, Hashable {
    let images: Entry
    let containers: Entry
    let volumes: Entry

    struct Entry: Codable, Hashable {
        let total: Int
        let active: Int
        let sizeInBytes: Int64
        let reclaimable: Int64
    }

    var totalSize: Int64 { images.sizeInBytes + containers.sizeInBytes + volumes.sizeInBytes }
    var totalReclaimable: Int64 { images.reclaimable + containers.reclaimable + volumes.reclaimable }
}

// MARK: - Network

/// A network as reported by `container network list --format json`.
struct CTNetwork: Codable, Identifiable, Hashable {
    let configuration: Configuration
    let status: Status?

    var id: String { configuration.name }

    struct Configuration: Codable, Hashable {
        let name: String
        let mode: String?
        let plugin: String?
        let labels: [String: String]?
        let creationDate: String?
    }

    struct Status: Codable, Hashable {
        let ipv4Gateway: String?
        let ipv4Subnet: String?
        let ipv6Subnet: String?
    }

    var name: String { configuration.name }
    var mode: String? { configuration.mode }
    var plugin: String? { configuration.plugin }
    var subnet: String? { status?.ipv4Subnet }
    var subnetV6: String? { status?.ipv6Subnet }
    var gateway: String? { status?.ipv4Gateway }
    var labels: [String: String]? { configuration.labels }
    var createdDate: Date? { ISO8601DateFormatter.engine.date(from: configuration.creationDate ?? "") }

    /// Networks created by the engine itself (e.g. the `default` NAT network)
    /// carry a `builtin` role label and can't be deleted.
    var isBuiltin: Bool {
        configuration.labels?["com.apple.container.resource.role"] == "builtin"
    }
}

// MARK: - Formatting helpers

extension ISO8601DateFormatter {
    static let engine: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

enum Format {
    static func bytes(_ value: Int64?) -> String {
        guard let value, value > 0 else { return "—" }
        let bcf = ByteCountFormatter()
        bcf.countStyle = .file
        return bcf.string(fromByteCount: value)
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    static func memory(_ bytes: Int64?) -> String {
        guard let bytes, bytes > 0 else { return "default" }
        return bytes >= 1_073_741_824
            ? String(format: "%.0f GB", Double(bytes) / 1_073_741_824)
            : String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }

    /// Compact byte count for live readouts, e.g. `31.3 MB`.
    static func byteCount(_ value: Double) -> String {
        let bcf = ByteCountFormatter()
        bcf.countStyle = .memory
        return bcf.string(fromByteCount: Int64(max(0, value)))
    }

    /// A throughput rate, e.g. `1.2 MB/s`.
    static func rate(_ bytesPerSecond: Double) -> String {
        byteCount(bytesPerSecond) + "/s"
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }
}
