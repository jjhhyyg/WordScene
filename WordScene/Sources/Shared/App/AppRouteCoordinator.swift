import Foundation

@MainActor
final class AppRouteCoordinator: ObservableObject {
    @Published private(set) var pendingShareHandoffID: UUID?

    func open(url: URL) {
        guard url.scheme == ShareExtensionConfiguration.urlScheme,
              url.host == ShareExtensionConfiguration.handoffHost,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let idValue = components.queryItems?.first(where: { $0.name == "id" })?.value,
              let id = UUID(uuidString: idValue) else {
            return
        }

        pendingShareHandoffID = id
    }

    func consumePendingShareHandoffID() -> UUID? {
        let id = pendingShareHandoffID
        pendingShareHandoffID = nil
        return id
    }
}
