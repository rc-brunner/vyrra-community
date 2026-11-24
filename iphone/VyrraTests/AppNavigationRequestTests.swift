import XCTest
@testable import Vyrra

final class AppNavigationRequestTests: XCTestCase {
    func testRequestStoresAndConsumesTabAndLaunchAction() throws {
        let suiteName = "AppNavigationRequestTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        AppNavigationRequest.request(.speak, action: .startDictation, defaults: defaults)

        XCTAssertEqual(AppNavigationRequest.pendingAction(defaults: defaults), .startDictation)
        XCTAssertEqual(AppNavigationRequest.consumePendingTab(defaults: defaults), .speak)
        XCTAssertEqual(AppNavigationRequest.consumePendingAction(defaults: defaults), .startDictation)
        XCTAssertNil(AppNavigationRequest.consumePendingTab(defaults: defaults))
        XCTAssertNil(AppNavigationRequest.consumePendingAction(defaults: defaults))
    }

    func testRequestWithoutActionClearsExistingAction() throws {
        let suiteName = "AppNavigationRequestTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        AppNavigationRequest.request(.speak, action: .startDictation, defaults: defaults)
        AppNavigationRequest.request(.library, defaults: defaults)

        XCTAssertEqual(AppNavigationRequest.consumePendingTab(defaults: defaults), .library)
        XCTAssertNil(AppNavigationRequest.consumePendingAction(defaults: defaults))
    }
}
