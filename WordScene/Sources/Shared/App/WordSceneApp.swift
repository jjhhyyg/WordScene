import SwiftUI

@main
struct WordSceneApp: App {
    @AppStorage(AppTheme.storageKey) private var selectedThemeRawValue = AppTheme.auto.rawValue
    @StateObject private var routeCoordinator = AppRouteCoordinator()
    private let dataController = AppDataController.live

    private var selectedTheme: AppTheme {
        AppTheme.fromStorageValue(selectedThemeRawValue)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appDataController, dataController)
                .environmentObject(routeCoordinator)
                .wordSceneTheme(selectedTheme)
                .onOpenURL { url in
                    routeCoordinator.open(url: url)
                }
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
                .environmentObject(routeCoordinator)
                .wordSceneTheme(selectedTheme)
        }
        #endif
    }
}
