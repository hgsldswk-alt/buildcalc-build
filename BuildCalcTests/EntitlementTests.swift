import XCTest

final class EntitlementTests: XCTestCase {
    func testFirstLaunchAndExactBoundary() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var value = Entitlement(firstOpen: start.addingTimeInterval(-60 * 86_400), proStartedAt: start)
        XCTAssertTrue(value.hasPro(at: start, free: false))
        XCTAssertTrue(value.hasPro(at: value.trialEnd.addingTimeInterval(-1), free: false))
        XCTAssertFalse(value.hasPro(at: value.trialEnd, free: false))
        value.observe(value.trialEnd)
        XCTAssertFalse(value.hasPro(at: value.trialEnd.addingTimeInterval(-1), free: false))
        XCTAssertFalse(value.hasPro(at: start, free: false))
        XCTAssertTrue(value.hasPro(at: value.trialEnd, free: true))
        value.purchasedPro = true
        XCTAssertTrue(value.hasPro(at: value.trialEnd, free: false))
    }

    func testReceiptAndReinstallNeverExtendTrial() throws {
        let opened = Date(timeIntervalSince1970: 1_800_000_000)
        let original = opened.addingTimeInterval(-31 * 86_400)
        var value = Entitlement(firstOpen: opened, trialClaimedAt: original)
        XCTAssertFalse(value.hasPro(at: opened, free: false))
        value.trialClaimedAt = opened.addingTimeInterval(8 * 86_400)
        XCTAssertEqual(value.trialStart, opened)
        let stored = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(Entitlement.self, from: stored), value)
    }
}
