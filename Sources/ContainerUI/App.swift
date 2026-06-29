import SwiftUI

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
