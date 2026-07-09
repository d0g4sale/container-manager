import Foundation

/// Errors surfaced from the underlying `container` CLI.
enum EngineError: LocalizedError {
    case binaryNotFound
    case commandFailed(command: String, code: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "The `container` command-line tool could not be found. Install Apple Containers (e.g. `brew install container`)."
        case let .commandFailed(command, code, message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return "`container \(command)` failed (exit \(code)).\n\(trimmed.isEmpty ? "No error output." : trimmed)"
        }
    }
}

/// A thin, typed wrapper around the Apple `container` CLI.
///
/// Everything the app knows about containers, images and the engine flows
/// through here. The CLI is invoked out-of-process and its `--format json`
/// output is decoded into the model types in `Models.swift`.
struct ContainerEngine {

    // MARK: - Locating the binary

    /// Resolved path to the `container` executable, searched once.
    static let binaryPath: String? = {
        let candidates = [
            "/opt/homebrew/bin/container",
            "/usr/local/bin/container",
            "/usr/bin/container"
        ]
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        // Fall back to a PATH lookup via `/usr/bin/which`.
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["container"]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = Pipe()
        try? which.run()
        which.waitUntilExit()
        if which.terminationStatus == 0,
           let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
               .trimmingCharacters(in: .whitespacesAndNewlines),
           !out.isEmpty {
            return out
        }
        return nil
    }()

    var isInstalled: Bool { Self.binaryPath != nil }

    // MARK: - Core process runner

    /// Runs `container <args>` to completion and returns raw stdout data.
    /// Both pipes are drained concurrently to avoid buffer deadlocks.
    @discardableResult
    func run(_ args: [String]) async throws -> Data {
        guard let binary = Self.binaryPath else { throw EngineError.binaryNotFound }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: binary)
                proc.arguments = args

                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError = errPipe

                // Drain stderr on a separate queue so a chatty stderr can't
                // block the stdout reader (or vice-versa).
                var errData = Data()
                let errQueue = DispatchQueue(label: "engine.stderr")
                let group = DispatchGroup()
                group.enter()
                errQueue.async {
                    errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                do {
                    try proc.run()
                } catch {
                    cont.resume(throwing: error)
                    return
                }

                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                proc.waitUntilExit()

                if proc.terminationStatus == 0 {
                    cont.resume(returning: outData)
                } else {
                    let message = String(data: errData, encoding: .utf8)
                        ?? String(data: outData, encoding: .utf8)
                        ?? ""
                    cont.resume(throwing: EngineError.commandFailed(
                        command: args.joined(separator: " "),
                        code: proc.terminationStatus,
                        message: message))
                }
            }
        }
    }

    /// Convenience: run and decode JSON.
    private func runJSON<T: Decodable>(_ args: [String], as type: T.Type) async throws -> T {
        let data = try await run(args)
        let decoder = JSONDecoder()
        if data.isEmpty { // some commands print nothing for empty results
            // Try to coerce empty into an empty array if T is an array.
            if let empty = "[]".data(using: .utf8), let decoded = try? decoder.decode(T.self, from: empty) {
                return decoded
            }
        }
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Engine / system service

    /// Whether the background apiserver is running.
    func systemRunning() async -> Bool {
        guard isInstalled else { return false }
        // `system status` exits 0 and prints a running message when up.
        do {
            let data = try await run(["system", "status"])
            let text = String(data: data, encoding: .utf8)?.lowercased() ?? ""
            return !text.contains("not running")
        } catch {
            return false
        }
    }

    func startSystem() async throws { try await run(["system", "start"]) }
    func stopSystem() async throws { try await run(["system", "stop"]) }

    /// Detailed system status: version and storage paths.
    func systemStatus() async throws -> CTSystemStatus {
        try await runJSON(["system", "status", "--format", "json"], as: CTSystemStatus.self)
    }

    /// Disk usage for images, containers and volumes (size + reclaimable).
    func diskUsage() async throws -> CTDiskUsage {
        try await runJSON(["system", "df", "--format", "json"], as: CTDiskUsage.self)
    }

    // MARK: - Networks

    /// Configured container networks.
    func listNetworks() async -> [CTNetwork] {
        (try? await runJSON(["network", "list", "--format", "json"], as: [CTNetwork].self)) ?? []
    }

    func deleteNetwork(_ name: String) async throws { try await run(["network", "delete", name]) }

    /// Create a new network. `subnet`/`subnetV6` set the IPv4/IPv6 ranges;
    /// `internal` restricts it to host-only; `labels` pass through as `--label`.
    func createNetwork(name: String, subnet: String? = nil, subnetV6: String? = nil,
                       internalOnly: Bool = false,
                       labels: [(String, String)] = []) async throws {
        var args = ["network", "create"]
        if internalOnly { args.append("--internal") }
        for (k, v) in labels where !k.isEmpty { args += ["--label", "\(k)=\(v)"] }
        if let subnet, !subnet.isEmpty { args += ["--subnet", subnet] }
        if let subnetV6, !subnetV6.isEmpty { args += ["--subnet-v6", subnetV6] }
        args.append(name)
        try await run(args)
    }

    /// Remove networks with no container connections.
    func pruneNetworks() async throws { try await run(["network", "prune"]) }

    // MARK: - Containers

    func listContainers() async throws -> [CTContainer] {
        try await runJSON(["list", "--all", "--format", "json"], as: [CTContainer].self)
    }

    func startContainer(_ id: String) async throws { try await run(["start", id]) }
    func stopContainer(_ id: String) async throws { try await run(["stop", id]) }
    func killContainer(_ id: String) async throws { try await run(["kill", id]) }
    func deleteContainer(_ id: String, force: Bool) async throws {
        try await run(force ? ["delete", "--force", id] : ["delete", id])
    }
    func restartContainer(_ id: String) async throws {
        try? await stopContainer(id)
        try await startContainer(id)
    }

    /// One-shot resource-usage snapshot for a single container.
    /// `--no-stream` returns the first reading and exits rather than streaming.
    func stats(_ id: String) async throws -> CTStats? {
        let readings = try await runJSON(
            ["stats", "--no-stream", "--format", "json", id], as: [CTStats].self)
        return readings.first { $0.id == id } ?? readings.first
    }

    func inspectContainerRaw(_ id: String) async throws -> String {
        let data = try await run(["inspect", id])
        return prettyJSON(data)
    }

    // MARK: - Images

    func listImages() async throws -> [CTImage] {
        try await runJSON(["image", "list", "--format", "json"], as: [CTImage].self)
    }

    func deleteImage(_ reference: String) async throws { try await run(["image", "delete", reference]) }

    /// Remove unused images. `all` removes every unreferenced image, not just
    /// dangling (untagged) ones.
    func pruneImages(all: Bool) async throws {
        try await run(all ? ["image", "prune", "--all"] : ["image", "prune"])
    }

    func inspectImageRaw(_ reference: String) async throws -> String {
        let data = try await run(["image", "inspect", reference])
        return prettyJSON(data)
    }

    // MARK: - Machines

    func listMachines() async -> [CTMachine] {
        (try? await runJSON(["machine", "list", "--format", "json"], as: [CTMachine].self)) ?? []
    }

    /// Full details for one machine. `machine inspect` prints a JSON array
    /// (there's no `--format` flag) with fields the list command omits.
    func inspectMachine(_ id: String) async throws -> CTMachine? {
        try await runJSON(["machine", "inspect", id], as: [CTMachine].self).first
    }

    func inspectMachineRaw(_ id: String) async throws -> String {
        let data = try await run(["machine", "inspect", id])
        return prettyJSON(data)
    }

    /// Boot a stopped machine. There is no `machine start`; `machine run`
    /// boots the VM if necessary, so running a trivial command starts it and
    /// leaves it running (until `machine stop`). `machine run` performs TTY
    /// ioctls on stdin even for non-interactive commands and fails with
    /// "Operation not supported by device" on a plain pipe, so it must run
    /// attached to a pseudo-terminal.
    func startMachine(_ id: String) async throws {
        try await runWithPTY(["machine", "run", "-n", id, "--", "uname"])
    }

    func stopMachine(_ id: String) async throws { try await run(["machine", "stop", id]) }
    func deleteMachine(_ id: String) async throws { try await run(["machine", "delete", id]) }
    func setDefaultMachine(_ id: String) async throws { try await run(["machine", "set-default", id]) }

    /// Apply `key=value` settings (cpus, memory, home-mount). The CLI stores
    /// them immediately; they take effect the next time the machine boots.
    func configureMachine(_ id: String, settings: [String]) async throws {
        guard !settings.isEmpty else { return }
        try await run(["machine", "set", "-n", id] + settings)
    }

    // MARK: - Volumes

    func listVolumes() async -> [CTVolume] {
        (try? await runJSON(["volume", "list", "--format", "json"], as: [CTVolume].self)) ?? []
    }

    func deleteVolume(_ name: String) async throws { try await run(["volume", "delete", name]) }

    /// Create a new volume. `size` accepts an optional K/M/G/T/P suffix;
    /// `labels` and `opts` are passed through as `--label`/`--opt` pairs.
    func createVolume(name: String, size: String? = nil,
                      labels: [(String, String)] = [],
                      opts: [(String, String)] = []) async throws {
        var args = ["volume", "create"]
        for (k, v) in labels where !k.isEmpty { args += ["--label", "\(k)=\(v)"] }
        for (k, v) in opts where !k.isEmpty { args += ["--opt", "\(k)=\(v)"] }
        if let size, !size.isEmpty { args += ["-s", size] }
        args.append(name)
        try await run(args)
    }

    /// Remove volumes with no container references.
    func pruneVolumes() async throws { try await run(["volume", "prune"]) }

    /// Runs `container <args>` with stdio attached to a pseudo-terminal, for
    /// subcommands that refuse plain pipes (`machine run`). Output is drained
    /// from the PTY so the child never blocks on a full buffer.
    @discardableResult
    private func runWithPTY(_ args: [String]) async throws -> Data {
        guard let binary = Self.binaryPath else { throw EngineError.binaryNotFound }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var primary: Int32 = 0
                var replica: Int32 = 0
                guard openpty(&primary, &replica, nil, nil, nil) == 0 else {
                    cont.resume(throwing: EngineError.commandFailed(
                        command: args.joined(separator: " "), code: -1,
                        message: "Could not allocate a pseudo-terminal."))
                    return
                }

                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: binary)
                proc.arguments = args
                let replicaHandle = FileHandle(fileDescriptor: replica, closeOnDealloc: false)
                proc.standardInput = replicaHandle
                proc.standardOutput = replicaHandle
                proc.standardError = replicaHandle

                do {
                    try proc.run()
                } catch {
                    close(primary); close(replica)
                    cont.resume(throwing: error)
                    return
                }
                // The child holds its own copy of the replica side.
                close(replica)

                // Drain until EOF (reading the primary after the child exits
                // raises EIO, which surfaces here as nil/empty and ends the loop).
                var output = Data()
                let primaryHandle = FileHandle(fileDescriptor: primary, closeOnDealloc: true)
                while let chunk = try? primaryHandle.read(upToCount: 4096), !chunk.isEmpty {
                    output.append(chunk)
                }
                proc.waitUntilExit()

                if proc.terminationStatus == 0 {
                    cont.resume(returning: output)
                } else {
                    let message = String(data: output, encoding: .utf8) ?? ""
                    cont.resume(throwing: EngineError.commandFailed(
                        command: args.joined(separator: " "),
                        code: proc.terminationStatus,
                        message: message))
                }
            }
        }
    }

    // MARK: - Streaming (pull / build / follow logs)

    /// Runs a command and streams merged stdout+stderr lines as they arrive.
    /// Returns the `Process` so callers can cancel, plus an async line stream.
    func stream(_ args: [String]) throws -> (process: Process, lines: AsyncStream<String>) {
        guard let binary = Self.binaryPath else { throw EngineError.binaryNotFound }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        let stream = AsyncStream<String> { continuation in
            let handle = pipe.fileHandleForReading
            var buffer = Data()
            handle.readabilityHandler = { fh in
                let chunk = fh.availableData
                if chunk.isEmpty {
                    // EOF — flush remainder and finish.
                    if !buffer.isEmpty, let s = String(data: buffer, encoding: .utf8) {
                        continuation.yield(s)
                    }
                    handle.readabilityHandler = nil
                    continuation.finish()
                    return
                }
                buffer.append(chunk)
                // Emit complete lines, keep the partial tail buffered.
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer[buffer.startIndex...nl]
                    if let line = String(data: lineData, encoding: .utf8) {
                        continuation.yield(line)
                    }
                    buffer.removeSubrange(buffer.startIndex...nl)
                }
            }
            continuation.onTermination = { _ in
                handle.readabilityHandler = nil
                if proc.isRunning { proc.terminate() }
            }
        }

        try proc.run()
        return (proc, stream)
    }

    // MARK: - Helpers

    private func prettyJSON(_ data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj,
                                                       options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8)
        else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return str
    }
}
