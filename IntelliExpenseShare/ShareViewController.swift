import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    private var hostingController: UIHostingController<ShareExtensionView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        let model = ShareExtensionModel(extensionContext: extensionContext)
        let controller = UIHostingController(rootView: ShareExtensionView(model: model))
        addChild(controller)
        view.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controller.didMove(toParent: self)
        hostingController = controller
    }
}
