import SwiftUI
import Combine

/// Sidebar destinations.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard, containers, images, volumes, build

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .containers: return "Containers"
        case .images: return "Images"
        case .volumes: return "Volumes"
        case .build: return "Build"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .containers: return "shippingbox.fill"
        case .images: return "square.stack.3d.up.fill"
        case .volumes: return "externaldrive.fill"
        case .build: return "hammer.fill"
        }
    }
}

/// A transient banner/toast message.
struct Toast: Identifiable, Equatable {
    enum Kind { case info, success, error }
    let id = UUID()
    let kind: Kind
    let message: String
}

@MainActor
final class AppModel: ObservableObject {
    let engine = ContainerEngine()

    // Navigation
    @Published var selection: SidebarItem? = .dashboard

    // Engine state
    @Published var engineInstalled: Bool = true
    @Published var engineRunning: Bool = false
    @Published var engineBusy: Bool = false

    // Data
    @Published var containers: [CTContainer] = []
    @Published var images: [CTImage] = []
    @Published var volumes: [CTVolume] = []

    // Engine / system info
    @Published var systemStatus: CTSystemStatus?
    @Published var diskUsage: CTDiskUsage?
    @Published var networks: [CTNetwork] = []

    // UI state
    @Published var isRefreshing: Bool = false
    @Published var lastError: String?
    @Published var toast: Toast?

    private var refreshTask: Task<Void, Never>?

    init() {
        engineInstalled = engine.isInstalled
    }

    // MARK: - Lifecycle

    func start() {
        Task { await refreshEngineStatus() }
        startAutoRefresh()
    }

    func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAll(showSpinner: false)
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    func stopAutoRefresh() { refreshTask?.cancel() }

    // MARK: - Engine status

    func refreshEngineStatus() async {
        engineInstalled = engine.isInstalled
        guard engineInstalled else { engineRunning = false; return }
        engineRunning = await engine.systemRunning()
        if engineRunning { await refreshAll(showSpinner: true) }
    }

    func startEngine() async {
        engineBusy = true
        defer { engineBusy = false }
        do {
            try await engine.startSystem()
            engineRunning = true
            showToast(.success, "Engine started")
            await refreshAll(showSpinner: true)
        } catch {
            present(error)
        }
    }

    func stopEngine() async {
        engineBusy = true
        defer { engineBusy = false }
        do {
            try await engine.stopSystem()
            engineRunning = false
            containers = []; images = []; volumes = []
            systemStatus = nil; diskUsage = nil; networks = []
            showToast(.info, "Engine stopped")
        } catch {
            present(error)
        }
    }

    // MARK: - Refresh

    func refreshAll(showSpinner: Bool) async {
        guard engineInstalled, engineRunning else { return }
        if showSpinner { isRefreshing = true }
        defer { if showSpinner { isRefreshing = false } }

        async let c = engine.listContainers()
        async let i = engine.listImages()
        async let v = engine.listVolumes()
        async let st = engine.systemStatus()
        async let du = engine.diskUsage()
        async let nw = engine.listNetworks()

        if let newContainers = try? await c {
            containers = newContainers.sorted { sortKey($0) < sortKey($1) }
        }
        if let newImages = try? await i {
            images = newImages.sorted { $0.displayName < $1.displayName }
        }
        volumes = await v
        systemStatus = try? await st
        diskUsage = try? await du
        networks = await nw
    }

    private func sortKey(_ c: CTContainer) -> String {
        // Running first, then by name.
        (c.isRunning ? "0" : "1") + c.id
    }

    /// Containers that mount `volume`, paired with the specific mount so the UI
    /// can show where the volume lands inside each container. Running first.
    func usage(of volume: CTVolume) -> [(container: CTContainer, mount: CTContainer.Mount)] {
        containers.compactMap { c in
            guard let mount = c.mounts.first(where: { $0.volumeName == volume.name }) else { return nil }
            return (c, mount)
        }
        .sorted { ($0.container.isRunning ? 0 : 1, $0.container.id) < ($1.container.isRunning ? 0 : 1, $1.container.id) }
    }

    // MARK: - Container actions

    func perform(_ label: String, success: String? = nil,
                 _ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
                await refreshAll(showSpinner: false)
                if let success { showToast(.success, success) }
            } catch {
                present(error)
            }
        }
    }

    // MARK: - Reclaim disk space

    func reclaimImages() {
        let freed = diskUsage?.images.reclaimable ?? 0
        perform("prune images", success: reclaimedMessage(freed)) {
            try await self.engine.pruneImages(all: true)
        }
    }

    func reclaimVolumes() {
        let freed = diskUsage?.volumes.reclaimable ?? 0
        perform("prune volumes", success: reclaimedMessage(freed)) {
            try await self.engine.pruneVolumes()
        }
    }

    private func reclaimedMessage(_ bytes: Int64) -> String {
        bytes > 0 ? "Reclaimed \(Format.bytes(bytes))" : "Nothing to reclaim"
    }

    func startContainer(_ c: CTContainer) {
        perform("start") { try await self.engine.startContainer(c.id) }
    }
    func stopContainer(_ c: CTContainer) {
        perform("stop") { try await self.engine.stopContainer(c.id) }
    }
    func restartContainer(_ c: CTContainer) {
        perform("restart") { try await self.engine.restartContainer(c.id) }
    }
    func deleteContainer(_ c: CTContainer) {
        perform("delete") { try await self.engine.deleteContainer(c.id, force: c.isRunning) }
    }
    func deleteImage(_ image: CTImage) {
        perform("delete image") { try await self.engine.deleteImage(self.imageRef(image)) }
    }
    func deleteVolume(_ v: CTVolume) {
        perform("delete volume") { try await self.engine.deleteVolume(v.name) }
    }

    /// Reference usable by `image delete` / `run` — prefer repo:tag.
    func imageRef(_ image: CTImage) -> String {
        image.name.isEmpty ? image.id : image.name
    }

    // MARK: - Errors & toasts

    func present(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        lastError = message
        showToast(.error, message)
    }

    func showToast(_ kind: Toast.Kind, _ message: String) {
        let toast = Toast(kind: kind, message: message)
        self.toast = toast
        Task {
            try? await Task.sleep(nanoseconds: kind == .error ? 6_000_000_000 : 3_000_000_000)
            if self.toast?.id == toast.id { self.toast = nil }
        }
    }
}
