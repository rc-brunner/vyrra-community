import UIKit
import UniformTypeIdentifiers

enum ClipboardService {
    static let defaultExpirationInterval: TimeInterval = 60 * 60

    static func copy(_ text: String) {
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: text]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(defaultExpirationInterval)
            ]
        )
    }

    static func clearText() {
        guard UIPasteboard.general.hasStrings else { return }
        UIPasteboard.general.items = []
    }
}
