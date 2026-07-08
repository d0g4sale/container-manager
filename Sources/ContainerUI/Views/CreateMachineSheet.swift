import SwiftUI

/// A guided form for `container machine create` — image, name and resources
/// up front, the pull/boot progress streamed live once it starts.
struct CreateMachineSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var image = ""
    @State private var name = ""
    @State private var cpus = ""
    @State private var memory = ""
    @State private var homeMount = "rw"
    @State private var setDefault = false
    @State private var bootNow = true

    @State private var running = false
    @State private var finished = false
    @State private var failed = false
    @State private var log = ""
    @State private var process: Process?

    /// Machines boot the image's `/sbin/init`, so only init-capable images
    /// work: busybox-based ones (alpine) or systemd `-init` variants. Plain
    /// base images (ubuntu, debian, fedora) have no init and die on boot;
    /// amd64-only images (archlinux) fail earlier on Apple Silicon. Every
    /// suggestion here is multi-arch (arm64) and verified to boot.
    private let suggestions = ["alpine:3.22", "almalinux/9-init",
                               "rockylinux/rockylinux:9-ubi-init", "redhat/ubi9-init"]

    private var trimmedImage: String { image.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if running || finished {
                progressLog
            } else {
                form
            }
            Divider()
            footer
        }
        .frame(width: 580, height: 560)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 26)).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading) {
                Text("Create a Machine").font(.headline)
                Text("A lightweight Linux virtual machine built from a container image")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    // MARK: Form

    private var form: some View {
        Form {
            Section {
                TextField("Image", text: $image, prompt: Text("e.g. ubuntu:24.04"))
                    .font(.system(.body, design: .monospaced))
                TextField("Name", text: $name, prompt: Text("Optional — e.g. dev-box"))
                    .font(.system(.body, design: .monospaced))
                suggestionChips
            } header: {
                Text("Image")
            } footer: {
                Text("The machine boots the image's init system (/sbin/init), so pick an init-capable image: alpine, or a systemd “-init” variant. Plain ubuntu/debian/fedora base images won't boot. Registry defaults to Docker Hub.")
            }

            Section {
                TextField("CPUs", text: $cpus, prompt: Text("Optional — e.g. 4"))
                TextField("Memory", text: $memory, prompt: Text("Optional — e.g. 8G (default: half of system memory)"))
                Picker("Home folder", selection: $homeMount) {
                    Text("Read & write").tag("rw")
                    Text("Read only").tag("ro")
                    Text("Not mounted").tag("none")
                }
            } header: {
                Text("Resources")
            } footer: {
                Text("Your macOS home folder is shared into the machine, so your files are right there in the shell.")
            }

            Section {
                Toggle("Boot after creating", isOn: $bootNow)
                Toggle("Set as default machine", isOn: $setDefault)
            } footer: {
                Text("The default machine is the one commands target when no name is given.")
            }
        }
        .formStyle(.grouped)
    }

    private var suggestionChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Popular images").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            FlexWrap(suggestions, id: \.self) { s in
                Button(s) { image = s }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Progress

    private var progressLog: some View {
        ScrollView {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if running { ProgressView().controlSize(.small) }
                        Text(running ? "Creating machine from \(trimmedImage)…"
                             : (failed ? "Create failed" : "Machine ready"))
                            .font(.callout.weight(.medium))
                            .foregroundStyle(failed ? .red : .primary)
                    }
                    if failed, let hint = failureHint {
                        Label(hint, systemImage: "lightbulb")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                    Text(log)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("bottom")
                }
                .padding(20)
                .onChange(of: log) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
        }
    }

    /// A plain-English explanation for the known ways `machine create` fails,
    /// matched against the raw CLI output above.
    private var failureHint: String? {
        if log.localizedCaseInsensitiveContains("unsupported platform") {
            return "This image doesn't provide a linux/arm64 build, which Apple Silicon machines need. Pick a multi-platform image — e.g. alpine:3.22 or almalinux/9-init."
        }
        if log.localizedCaseInsensitiveContains("is not running")
            || log.localizedCaseInsensitiveContains("must be running") {
            return "The image booted but exited immediately — it has no init system (/sbin/init), which machines need. Plain base images like ubuntu or debian won't boot; use alpine:3.22 or a systemd “-init” image such as almalinux/9-init. A stopped machine record may have been left behind — delete it from the Machines list."
        }
        return nil
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Close") { cancel(); dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            if finished && !failed {
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else if finished && failed {
                Button("Back") { finished = false; failed = false }
                Button("Retry") { startCreate() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(running ? "Creating…" : "Create") { startCreate() }
                    .buttonStyle(.borderedProminent)
                    .disabled(running || trimmedImage.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    // MARK: Create

    private func startCreate() {
        guard !trimmedImage.isEmpty, !running else { return }
        running = true; finished = false; failed = false; log = ""

        var args = ["machine", "create", "--progress", "plain"]
        let name = self.name.trimmingCharacters(in: .whitespaces)
        let cpus = self.cpus.trimmingCharacters(in: .whitespaces)
        let memory = self.memory.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { args += ["--name", name] }
        if !cpus.isEmpty { args += ["--cpus", cpus] }
        if !memory.isEmpty { args += ["--memory", memory] }
        if homeMount != "rw" { args += ["--home-mount", homeMount] }
        if setDefault { args.append("--set-default") }
        if !bootNow { args.append("--no-boot") }
        args.append(trimmedImage)

        do {
            let (proc, lines) = try model.engine.stream(args)
            process = proc
            Task {
                for await line in lines { log += line }
                proc.waitUntilExit()
                running = false
                finished = true
                failed = proc.terminationStatus != 0
                if !failed {
                    model.showToast(.success, "Machine \(name.isEmpty ? "created" : "\(name) created")")
                    await model.refreshAll(showSpinner: false)
                }
            }
        } catch {
            running = false; finished = true; failed = true
            log = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func cancel() {
        if let p = process, p.isRunning { p.terminate() }
    }
}
