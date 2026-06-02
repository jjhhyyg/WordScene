import SwiftUI

@main
struct WordSceneApp: App {
    @AppStorage(AppTheme.storageKey) private var selectedThemeRawValue = AppTheme.auto.rawValue
    private let dataController = AppDataController.live

    private var selectedTheme: AppTheme {
        AppTheme.fromStorageValue(selectedThemeRawValue)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appDataController, dataController)
                .wordSceneTheme(selectedTheme)
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
                .wordSceneTheme(selectedTheme)
        }
        #endif
    }
}
