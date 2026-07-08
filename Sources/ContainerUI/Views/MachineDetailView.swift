import SwiftUI

struct MachineDetailView: View {
    @EnvironmentObject var model: AppModel
    let machineID: String

    @State private var tab = 0
    @State private var detail: CTMachine?
    @State private var rawJSON = ""

    /// The list entry (kept fresh by auto-refresh) for live status; `detail`
    /// layers on the inspect-only fields (image, home mount, user).
    private var machine: CTMachine? {
        model.machines.first { $0.id == machineID }
    }

    private var busy: Bool { model.busyMachines.contains(machineID) }

    var body: some View {
        Group {
            if let m = machine {
                content(m)
            } else {
                EmptyStateView(symbol: "questionmark.folder", title: "Machine unavailable",
                               message: "This machine no longer exists.")
            }
        }
        .navigationTitle(machineID)
        .task(id: machineID) {
            detail = try? await model.engine.inspectMachine(machineID)
        }
    }

    private func content(_ m: CTMachine) -> some View {
        VStack(spacing: 0) {
            header(m)
            Picker("", selection: $tab) {
                Text("Overview").tag(0)
                Text("Terminal").tag(1)
                Text("Logs").tag(2)
                Text("Inspect").tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            Divider()

            switch tab {
            case 1: MachineConsoleView(machineID: m.id)
            case 2: MachineLogsView(machineID: m.id)
            case 3: inspectTab(m)
            default: overviewTab(m)
            }
        }
        // Status flips (boot/stop) change the inspect output too.
        .onChange(of: m.isRunning) { _, _ in
            Task { detail = try? await model.engine.inspectMachine(machineID) }
        }
    }

    // MARK: Header

    private func header(_ m: CTMachine) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 30))
                .foregroundStyle(m.isRunning ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(m.id).font(.title2.weight(.bold))
                    if m.isDefault { DefaultBadge() }
                }
                HStack(spacing: 8) {
                    StatusPill(running: m.isRunning)
                    if let image = detail?.displayImage {
                        Text(image).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            controls(m)
        }
        .padding(20)
    }

    private func controls(_ m: CTMachine) -> some View {
        HStack(spacing: 10) {
            if busy {
                ProgressView().controlSize(.small)
                Text(m.isRunning ? "Working…" : "Booting…")
                    .font(.callout).foregroundStyle(.secondary)
            } else if m.isRunning {
                Button { tab = 1 } label: { Label("Shell", systemImage: "terminal") }
                Button { model.restartMachine(m) } label: { Label("Restart", systemImage: "arrow.clockwise") }
                Button { model.stopMachine(m) } label: { Label("Stop", systemImage: "stop.fill") }
                    .tint(.orange)
            } else {
                Button { model.startMachine(m) } label: { Label("Boot", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
            }
            Menu {
                if !m.isDefault {
                    Button("Set as Default") { model.setDefaultMachine(m) }
                }
                Button("Delete", role: .destructive) { model.deleteMachine(m) }
            } label: { Image(systemName: "ellipsis.circle") }
            .frame(width: 30)
        }
    }

    // MARK: Overview

    private func overviewTab(_ m: CTMachine) -> some View {
        // Prefer the richer inspect payload where present.
        let d = detail ?? m
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    Text("General").font(.headline)
                    MetaRow("Name", m.id)
                    if let image = d.displayImage { MetaRow("Image", image) }
                    MetaRow("State", m.status.capitalized)
                    MetaRow("Created", Format.relative(m.createdAt))
                    if let arch = d.platform?.architecture {
                        MetaRow("Platform", "\(d.platform?.os ?? "linux")/\(arch)")
                    }
                    if let ip = m.ip, !ip.isEmpty { MetaRow("IP Address", ip, mono: true) }
                    if let user = d.userSetup?.username {
                        MetaRow("User", "\(user) (uid \(d.userSetup?.uid.map(String.init) ?? "—"))")
                    }
                    MetaRow("Disk", Format.bytes(m.diskSize))
                }

                MachineConfigCard(machine: d)
            }
            .padding(20)
        }
    }

    // MARK: Inspect (raw JSON)

    private func inspectTab(_ m: CTMachine) -> some View {
        ScrollView {
            Text(rawJSON.isEmpty ? "Loading…" : rawJSON)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .clipped()
        .task(id: m.id) {
            rawJSON = (try? await model.engine.inspectMachineRaw(m.id)) ?? "Failed to load."
        }
    }
}

// MARK: - Configuration card (cpus / memory / home mount)

/// Editable machine settings applied through `container machine set`. The CLI
/// stores changes immediately but they only take effect on the next boot, so
/// a restart hint appears after applying to a running machine.
private struct MachineConfigCard: View {
    @EnvironmentObject var model: AppModel
    let machine: CTMachine

    @State private var cpus = ""
    @State private var memory = ""
    @State private var homeMount = "rw"
    @State private var applying = false
    @State private var appliedWhileRunning = false

    private static let homeMountOptions = [
        ("rw", "Read & write"), ("ro", "Read only"), ("none", "Not mounted")
    ]

    private var dirty: Bool {
        cpus != (machine.cpus.map(String.init) ?? "")
            || memory != (machine.memorySetting ?? "")
            || homeMount != (machine.homeMount ?? "rw")
    }

    var body: some View {
        Card {
            HStack {
                Text("Configuration").font(.headline)
                Spacer()
                if applying {
                    ProgressView().controlSize(.small)
                } else if dirty {
                    Button("Apply") { apply() }
                        .controlSize(.small)
                }
            }

            HStack(alignment: .top) {
                Text("CPUs")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)
                TextField("e.g. 4", text: $cpus)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Spacer()
            }
            HStack(alignment: .top) {
                Text("Memory")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)
                TextField("e.g. 8G", text: $memory)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Spacer()
            }
            HStack(alignment: .top) {
                Text("Home folder")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)
                Picker("", selection: $homeMount) {
                    ForEach(Self.homeMountOptions, id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
                Spacer()
            }

            if appliedWhileRunning {
                Label("Saved. Restart the machine to apply the new settings.",
                      systemImage: "arrow.clockwise.circle")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Text("Changes take effect the next time the machine boots.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .onAppear { load() }
        .onChange(of: machine) { _, _ in load() }
    }

    private func load() {
        cpus = machine.cpus.map(String.init) ?? ""
        memory = machine.memorySetting ?? ""
        homeMount = machine.homeMount ?? "rw"
    }

    private func apply() {
        var settings: [String] = []
        let c = cpus.trimmingCharacters(in: .whitespaces)
        let m = memory.trimmingCharacters(in: .whitespaces)
        if !c.isEmpty, c != (machine.cpus.map(String.init) ?? "") { settings.append("cpus=\(c)") }
        if !m.isEmpty, m != (machine.memorySetting ?? "") { settings.append("memory=\(m)") }
        if homeMount != (machine.homeMount ?? "rw") { settings.append("home-mount=\(homeMount)") }
        guard !settings.isEmpty else { return }

        applying = true
        let running = machine.isRunning
        Task {
            defer { applying = false }
            do {
                try await model.engine.configureMachine(machine.id, settings: settings)
                appliedWhileRunning = running
                model.showToast(.success, "Machine settings saved")
                await model.refreshAll(showSpinner: false)
            } catch {
                model.present(error)
            }
        }
    }
}

// MARK: - Terminal (interactive shell)

/// A login shell inside the machine via `container machine run`, rendered in
/// the shared SwiftTerm PTY surface. `machine run` boots the VM if it isn't
/// running, so the terminal works from a cold stop — the shell just takes a
/// few seconds to appear while the machine boots.
private struct MachineConsoleView: View {
    let machineID: String

    @State private var session = 0
    @State private var exitCode: Int32?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Login shell — boots the machine if it's stopped")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let code = exitCode {
                    Text(code == 0 ? "Session ended." : "Session ended (exit \(code)).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button { reconnect() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reconnect a new shell")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()

            if let binary = ContainerEngine.binaryPath {
                TerminalSurface(
                    executable: binary,
                    args: ["machine", "run", "-i", "-t", "-n", machineID],
                    onExit: { exitCode = $0 }
                )
                .id(session)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
            } else {
                EmptyStateView(symbol: "exclamationmark.triangle",
                               title: "container not found",
                               message: "The `container` command-line tool could not be located.")
            }
        }
    }

    private func reconnect() {
        exitCode = nil
        session += 1
    }
}

// MARK: - Logs

/// Machine stdio/boot logs through the PTY surface, mirroring the container
/// `LogsView` — one-shot output, App/Boot toggle, reload re-runs the command.
private struct MachineLogsView: View {
    let machineID: String

    @State private var boot = false
    @State private var reload = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $boot) {
                    Text("App").tag(false)
                    Text("Boot").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Button { reload += 1 } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload logs")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()

            if let binary = ContainerEngine.binaryPath {
                TerminalSurface(executable: binary, args: logArgs)
                    .id("\(boot)-\(reload)")
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor))
            } else {
                EmptyStateView(symbol: "exclamationmark.triangle",
                               title: "container not found",
                               message: "The `container` command-line tool could not be located.")
            }
        }
    }

    private var logArgs: [String] {
        var args = ["machine", "logs", "-n", "1000"]
        if boot { args.append("--boot") }
        args.append(machineID)
        return args
    }
}
