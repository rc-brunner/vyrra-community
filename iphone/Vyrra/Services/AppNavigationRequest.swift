import Foundation

enum AppNavigationRequest {
    static let didRequestNavigation = Notification.Name("VyrraAppNavigationRequestDidChange")

    private static let pendingTabKey = "pendingAppTab"
    private static let pendingActionKey = "pendingAppAction"

    static func request(
        _ tab: AppTab,
        action: AppLaunchAction? = nil,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(tab.storageValue, forKey: pendingTabKey)

        if let action {
            defaults.set(action.rawValue, forKey: pendingActionKey)
        } else {
            defaults.removeObject(forKey: pendingActionKey)
        }

        NotificationCenter.default.post(name: didRequestNavigation, object: nil)
    }

    static func pendingAction(defaults: UserDefaults = .standard) -> AppLaunchAction? {
        guard let rawValue = defaults.string(forKey: pendingActionKey) else { return nil }
        return AppLaunchAction(rawValue: rawValue)
    }

    static func consumePendingTab(defaults: UserDefaults = .standard) -> AppTab? {
        guard let rawValue = defaults.string(forKey: pendingTabKey),
              let tab = AppTab(storageValue: rawValue)
        else { return nil }

        defaults.removeObject(forKey: pendingTabKey)
        return tab
    }

    static func consumePendingAction(defaults: UserDefaults = .standard) -> AppLaunchAction? {
        guard let action = pendingAction(defaults: defaults) else { return nil }
        defaults.removeObject(forKey: pendingActionKey)
        return action
    }
}

enum AppLaunchAction: String {
    case startDictation
    case finishDictation
    case cancelDictation
    case endKeyboardSession
}

extension AppTab {
    var storageValue: String {
        switch self {
        case .speak:
            "speak"
        case .library:
            "library"
        case .personalize:
            "personalize"
        case .settings:
            "settings"
        }
    }

    init?(storageValue: String) {
        switch storageValue {
        case "speak":
            self = .speak
        case "library":
            self = .library
        case "personalize":
            self = .personalize
        case "settings":
            self = .settings
        default:
            return nil
        }
    }
}
