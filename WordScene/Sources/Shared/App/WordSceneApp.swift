import SwiftUI

@main
struct WordSceneApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        #if os(macOS)
        .defaultSize(width: 1360, height: 820)
        .windowResizability(.contentMinSize)
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .frame(width: 720, height: 560)
        }
        #endif
    }
}
