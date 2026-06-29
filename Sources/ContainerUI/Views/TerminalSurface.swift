import SwiftUI
import AppKit
import SwiftTerm

/// SwiftUI host for a SwiftTerm `LocalProcessTerminalView` that runs a single
/// `container` subcommand inside a pseudo-terminal.
///
/// Both the interactive Console (`exec -i -t … sh`) and the Logs view
/// (`logs …`) drive this one component, so both get ANSI-colour rendering,
/// scrollback and correct PTY newline handling for free. The view is recreated
/// — and the child process restarted — whenever `args` changes, which the
/// callers exploit by toggling a session counter to reconnect/reload.
struct TerminalSurface: NSViewRepresentable {
    /// Absolute path to the executable to spawn (the resolved `container` binary).
    let executable: String
    /// Arguments passed to the executable.
    let args: [String]
    /// Invoked on the main thread when the child process exits.
    var onExit: ((Int32?) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(onExit: onExit) }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let term = LocalProcessTerminalView(frame: .zero)
        term.processDelegate = context.coordinator
        term.configureNativeColors()
        term.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        term.startProcess(executable: executable, args: args)
        return term
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        context.coordinator.onExit = onExit
    }

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: Coordinator) {
        nsView.terminate()
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var onExit: ((Int32?) -> Void)?
        init(onExit: ((Int32?) -> Void)?) { self.onExit = onExit }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {
            let cb = onExit
            DispatchQueue.main.async { cb?(exitCode) }
        }
    }
}
