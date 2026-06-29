import SwiftUI

private struct PortMapping: Identifiable, Hashable { let id = UUID(); var host = ""; var container = "" }
private struct EnvVar: Identifiable, Hashable { let id = UUID(); var key = ""; var value = "" }
private struct Mount: Identifiable, Hashable { let id = UUID(); var host = ""; var container = "" }

struct RunSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let image: CTImage

    @State private var name = ""
    @State private var ports: [PortMapping] = []
    @State private var envs: [EnvVar] = []
    @State private var mounts: [Mount] = []
    @State private var commandOverride = ""
    @State private var removeOnExit = false
    @State private var showAdvanced = false
    @State private var cpus = ""
    @State private var memory = ""

    @State private var running = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                generalSection
                portsSection
                envSection
                volumesSection
                advancedSection
            }
            .formStyle(.grouped)
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
                    .padding(.horizontal, 20).padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(width: 580, height: 620)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 26)).foregroundStyle(.green)
            VStack(alignment: .leading) {
                Text("Run a Container").font(.headline)
                Text(image.displayName).font(.caption)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    // MARK: Sections

    private var generalSection: some View {
        Section {
            TextField("Container name", text: $name, prompt: Text("Optional — auto-generated"))
            TextField("Command", text: $commandOverride,
                      prompt: Text("Optional — overrides image default"))
                .font(.system(.body, design: .monospaced))
            Toggle("Remove automatically when it stops", isOn: $removeOnExit)
        } header: {
            Text("General")
        }
    }

    private var portsSection: some View {
        Section {
            ForEach($ports) { $p in
                HStack(spacing: 8) {
                    TextField("Host", text: $p.host).frame(width: 90)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    TextField("Container", text: $p.container).frame(width: 90)
                    Spacer()
                    Button { ports.removeAll { $0.id == p.id } } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.borderless)
                }
            }
            Button { ports.append(PortMapping()) } label: {
                Label("Add port mapping", systemImage: "plus")
            }
        } header: {
            Text("Ports")
        } footer: {
            Text("Map a port on your Mac (host) to a port inside the container.")
        }
    }

    private var envSection: some View {
        Section {
            ForEach($envs) { $e in
                HStack(spacing: 8) {
                    TextField("KEY", text: $e.key).font(.system(.body, design: .monospaced))
                    Text("=").foregroundStyle(.secondary)
                    TextField("value", text: $e.value)
                    Button { envs.removeAll { $0.id == e.id } } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.borderless)
                }
            }
            Button { envs.append(EnvVar()) } label: { Label("Add variable", systemImage: "plus") }
        } header: {
            Text("Environment Variables")
        }
    }

    private var volumesSection: some View {
        Section {
            ForEach($mounts) { $m in
                HStack(spacing: 8) {
                    TextField("Host path", text: $m.host)
                    Button { chooseFolder { $m.host.wrappedValue = $0 } } label: {
                        Image(systemName: "folder")
                    }.buttonStyle(.borderless)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    TextField("Container path", text: $m.container)
                    Button { mounts.removeAll { $0.id == m.id } } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.borderless)
                }
            }
            Button { mounts.append(Mount()) } label: { Label("Add volume", systemImage: "plus") }
        } header: {
            Text("Volumes")
        } footer: {
            Text("Share a folder from your Mac with the container.")
        }
    }

    private var advancedSection: some View {
        Section(isExpanded: $showAdvanced) {
            TextField("CPUs", text: $cpus, prompt: Text("default"))
            TextField("Memory", text: $memory, prompt: Text("e.g. 512M, 2G"))
        } header: {
            Text("Advanced")
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Spacer()
            Button {
                runContainer()
            } label: {
                if running { ProgressView().controlSize(.small) }
                else { Label("Run", systemImage: "play.fill") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(running)
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    // MARK: Actions

    private func buildArgs() -> [String] {
        var args = ["run", "--detach"]
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty { args += ["--name", trimmedName] }
        if removeOnExit { args.append("--rm") }
        for p in ports where !p.host.isEmpty && !p.container.isEmpty {
            args += ["--publish", "\(p.host):\(p.container)"]
        }
        for e in envs where !e.key.isEmpty {
            args += ["--env", "\(e.key)=\(e.value)"]
        }
        for m in mounts where !m.host.isEmpty && !m.container.isEmpty {
            args += ["--volume", "\(m.host):\(m.container)"]
        }
        let c = cpus.trimmingCharacters(in: .whitespaces)
        if !c.isEmpty { args += ["--cpus", c] }
        let mem = memory.trimmingCharacters(in: .whitespaces)
        if !mem.isEmpty { args += ["--memory", mem] }

        args.append(model.imageRef(image))

        let cmd = commandOverride.trimmingCharacters(in: .whitespaces)
        if !cmd.isEmpty { args += cmd.split(separator: " ").map(String.init) }
        return args
    }

    private func runContainer() {
        running = true
        errorText = nil
        let args = buildArgs()
        Task {
            do {
                try await model.engine.run(args)
                model.showToast(.success, "Container started")
                model.selection = .containers
                await model.refreshAll(showSpinner: false)
                dismiss()
            } catch {
                running = false
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func chooseFolder(_ completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            completion(url.path)
        }
    }
}
