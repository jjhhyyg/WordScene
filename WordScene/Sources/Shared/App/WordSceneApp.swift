import SwiftUI

@main
struct WordSceneApp: App {
    private let dataController = AppDataController.live

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appDataController, dataController)
        }
        #if os(macOS)
        .defaultSize(width: 1360, height: 820)
        .windowResizability(.contentMinSize)
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .frame(width: 720, height: 560)
                .environment(\.appDataController, dataController)
        }
        #endif
    }
}
