import SwiftUI

/// An interactive shell attached to a running container via
/// `container exec -i -t <id> sh`, rendered in a SwiftTerm PTY surface.
///
/// Only meaningful while the container is running — `exec` cannot attach to a
/// stopped container. Each visit (or Reconnect) spawns a fresh shell; bumping
/// `session` recreates the `TerminalSurface`, which restarts the process.
struct ConsoleView: View {
    let containerID: String

    @State private var session = 0
    @State private var exitCode: Int32?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Interactive shell (sh)")
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
                    args: ["exec", "-i", "-t", containerID, "sh"],
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
