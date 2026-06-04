import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    private let viewModel = ShareTranslationViewModel()

    override func viewDidLoad() {
        super.viewDidLoad()

        let viewModel = self.viewModel
        let shareView = ShareTranslationView(
            viewModel: viewModel,
            onCopy: { [weak viewModel] text in
                UIPasteboard.general.string = text
                viewModel?.markCopied()
            },
            onOpen: { [weak self] url in
                guard let extensionContext = self?.extensionContext else {
                    return
                }

                extensionContext.open(url, completionHandler: nil)
                extensionContext.completeRequest(returningItems: nil)
            }
        )
        let hostingController = UIHostingController(rootView: shareView)
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)

        viewModel.load(providers: inputItemProviders())
    }

    private func inputItemProviders() -> [NSItemProvider] {
        extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []
    }
}
