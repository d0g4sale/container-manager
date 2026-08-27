import SwiftUI

/// Container logs rendered through a SwiftTerm PTY surface so ANSI colour
/// codes, wrapping and scrollback all behave like a real terminal.
///
/// `container logs` is a one-shot command: it prints the requested tail and
/// exits, leaving static output in the surface. Switching App/Boot or hitting
/// Reload changes the view's identity, recreating the surface and re-running
/// the command.
struct LogsView: View {
    let containerID: String

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
        var args = ["logs", "-n", "1000"]
        if boot { args.append("--boot") }
        args += ["--", containerID]
        return args
    }
}
