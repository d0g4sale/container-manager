import SwiftUI

struct BuildView: View {
    @EnvironmentObject var model: AppModel

    @State private var contextPath = ""
    @State private var dockerfile = ""
    @State private var tag = ""
    @State private var noCache = false
    @State private var log = ""
    @State private var building = false
    @State private var finished = false
    @State private var failed = false
    @State private var process: Process?

    private var detectedFiles: [String] {
        guard !contextPath.isEmpty else { return [] }
        let fm = FileManager.default
        return ["Dockerfile", "Containerfile"].filter {
            fm.fileExists(atPath: contextPath + "/" + $0)
        }
    }

    private var canBuild: Bool {
        !contextPath.isEmpty && !tag.trimmingCharacters(in: .whitespaces).isEmpty && !building
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack {
                        TextField("Build context folder", text: $contextPath,
                                  prompt: Text("Choose a folder containing your Dockerfile"))
                        Button("Choose…") { chooseFolder() }
                    }
                    if !contextPath.isEmpty {
                        if detectedFiles.isEmpty {
                            Label("No Dockerfile or Containerfile found in this folder.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.orange)
                        } else {
                            Label("Found: \(detectedFiles.joined(separator: ", "))",
                                  systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(.green)
                        }
                    }
                } header: {
                    Text("Source")
                }

                Section {
                    TextField("Image tag", text: $tag, prompt: Text("e.g. myapp:latest"))
                        .font(.system(.body, design: .monospaced))
                    TextField("Dockerfile path", text: $dockerfile,
                              prompt: Text("Optional — defaults to ./Dockerfile"))
                        .font(.system(.body, design: .monospaced))
                    Toggle("Build without cache", isOn: $noCache)
                } header: {
                    Text("Output")
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 320)

            Divider()
            buildLog
            Divider()
            footer
        }
        .navigationTitle("Build")
    }

    private var buildLog: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if log.isEmpty {
                    Text("Build output will appear here.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(40)
                } else {
                    Text(log)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .id("bottom")
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipped()
            .onChange(of: log) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottomLeading) } }
        }
    }

    private var footer: some View {
        HStack {
            if building { ProgressView().controlSize(.small); Text("Building…").foregroundStyle(.secondary) }
            else if finished { Label(failed ? "Build failed" : "Build succeeded",
                                     systemImage: failed ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(failed ? .red : .green) }
            Spacer()
            if building {
                Button("Cancel") { cancel() }
            }
            Button { build() } label: { Label("Build", systemImage: "hammer.fill") }
                .buttonStyle(.borderedProminent)
                .disabled(!canBuild)
        }
        .padding(20)
    }

    private func build() {
        guard canBuild else { return }
        building = true; finished = false; failed = false; log = ""
        var args = ["build", "--tag", tag.trimmingCharacters(in: .whitespaces)]
        if noCache { args.append("--no-cache") }
        let df = dockerfile.trimmingCharacters(in: .whitespaces)
        if !df.isEmpty { args += ["--file", df] }
        args += ["--progress", "plain", contextPath]

        do {
            let (proc, lines) = try model.engine.stream(args)
            process = proc
            Task {
                for await line in lines { log += line }
                proc.waitUntilExit()
                building = false
                finished = true
                failed = proc.terminationStatus != 0
                if !failed {
                    model.showToast(.success, "Built \(tag)")
                    await model.refreshAll(showSpinner: false)
                } else {
                    model.showToast(.error, "Build failed")
                }
            }
        } catch {
            building = false; failed = true; finished = true
            log = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func cancel() {
        if let p = process, p.isRunning { p.terminate() }
        building = false
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            contextPath = url.path
            if tag.isEmpty { tag = url.lastPathComponent.lowercased() + ":latest" }
        }
    }
}
