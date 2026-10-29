import Foundation
#if canImport(UIKit)
import UIKit

@MainActor
public enum ShareSheetHelper {
    /// Safely presents a UIActivityViewController on top of whatever modal or sheet is currently active.
    public static func present(activityItems: [Any]) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            ?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first else {
            return
        }

        var topController = window.rootViewController
        while let presented = topController?.presentedViewController {
            topController = presented
        }

        guard let topController else { return }

        let activityVC = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topController.view
            popover.sourceRect = CGRect(x: topController.view.bounds.midX, y: topController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        topController.present(activityVC, animated: true)
    }
}
#endif
