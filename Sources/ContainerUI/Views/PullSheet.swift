import SwiftUI

struct PullSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var reference = ""
    @State private var running = false
    @State private var finished = false
    @State private var failed = false
    @State private var log = ""
    @State private var process: Process?

    private let suggestions = ["alpine:latest", "nginx:latest", "postgres:16",
                               "redis:latest", "python:3.12-slim", "node:22-alpine"]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !running && !finished {
                        field
                        suggestionChips
                    } else {
                        progressLog
                    }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 540, height: 440)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 26)).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading) {
                Text("Pull Image").font(.headline)
                Text("Download an image from a registry").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Image reference").font(.callout.weight(.medium))
            TextField("e.g. nginx:latest", text: $reference)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit(startPull)
            Text("Registry defaults to Docker Hub. Use a full path for others, e.g. ghcr.io/owner/image:tag.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var suggestionChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Popular images").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            FlexWrap(suggestions, id: \.self) { s in
                Button(s) { reference = s }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var progressLog: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if running { ProgressView().controlSize(.small) }
                    Text(running ? "Pulling \(reference)…"
                         : (failed ? "Pull failed" : "Done"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(failed ? .red : .primary)
                }
                Text(log)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("bottom")
            }
            .onChange(of: log) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
        }
    }

    private var footer: some View {
        HStack {
            Button("Close") { cancel(); dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            if finished {
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(running ? "Pulling…" : "Pull") { startPull() }
                    .buttonStyle(.borderedProminent)
                    .disabled(running || reference.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private func startPull() {
        let ref = reference.trimmingCharacters(in: .whitespaces)
        guard !ref.isEmpty, !running else { return }
        running = true; finished = false; failed = false; log = ""
        do {
            let (proc, lines) = try model.engine.stream(["image", "pull", "--", ref])
            process = proc
            Task {
                for await line in lines { log += line }
                proc.waitUntilExit()
                running = false
                finished = true
                failed = proc.terminationStatus != 0
                if !failed {
                    model.showToast(.success, "Pulled \(ref)")
                    await model.refreshAll(showSpinner: false)
                }
            }
        } catch {
            running = false; failed = true
            log = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func cancel() {
        if let p = process, p.isRunning { p.terminate() }
    }
}
