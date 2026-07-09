import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            detail
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.toast)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $model.selection) {
            Section("Library") {
                ForEach(SidebarItem.allCases) { item in
                    NavigationLink(value: item) {
                        Label(item.title, systemImage: item.symbol)
                            .badge(badge(for: item))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            EngineFooter()
        }
    }

    private func badge(for item: SidebarItem) -> Int {
        switch item {
        case .dashboard: return 0
        case .containers: return model.containers.count
        case .machines: return model.machines.count
        case .images: return model.images.count
        case .volumes: return model.volumes.count
        case .networks: return model.networks.count
        case .build: return 0
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if !model.engineInstalled {
            EmptyStateView(
                symbol: "exclamationmark.triangle",
                title: "Apple Containers not found",
                message: "The `container` command-line tool isn’t installed or isn’t on your PATH. Install it with Homebrew:\n\nbrew install container"
            )
        } else if !model.engineRunning {
            EngineOfflineView()
        } else {
            switch model.selection ?? .dashboard {
            case .dashboard: DashboardView()
            case .containers: ContainersView()
            case .machines: MachinesView()
            case .images: ImagesView()
            case .volumes: VolumesView()
            case .networks: NetworksView()
            case .build: BuildView()
            }
        }
    }
}

// MARK: - Engine footer (status + toggle)

struct EngineFooter: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            Divider()
            HStack(spacing: 8) {
                Circle()
                    .fill(model.engineRunning ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Engine")
                        .font(.caption.weight(.semibold))
                    Text(model.engineRunning ? "Running" : "Stopped")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.engineBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Button(model.engineRunning ? "Stop" : "Start") {
                        Task {
                            if model.engineRunning { await model.stopEngine() }
                            else { await model.startEngine() }
                        }
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }
}

// MARK: - Engine offline splash

struct EngineOfflineView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        EmptyStateView(
            symbol: "bolt.horizontal.circle",
            title: "Container engine is stopped",
            message: "Start the engine to manage and run your containers. This launches the background service that powers Apple Containers.",
            actionTitle: model.engineBusy ? "Starting…" : "Start Engine",
            action: { Task { await model.startEngine() } }
        )
    }
}
