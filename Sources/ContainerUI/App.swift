import SwiftUI
import AppKit

@main
struct ContainerUIApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 920, minHeight: 600)
                .onAppear { model.start() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // The standard About panel renders "Version {CFBundleShortVersionString}
            // ({CFBundleVersion})". Passing an empty `.version` (CFBundleVersion)
            // suppresses the parenthetical build number, leaving just the version.
            CommandGroup(replacing: .appInfo) {
                Button("About Container Manager") {
                    NSApp.orderFrontStandardAboutPanel(options: [.version: ""])
                }
            }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    Task { await model.refreshAll(showSpinner: true) }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
