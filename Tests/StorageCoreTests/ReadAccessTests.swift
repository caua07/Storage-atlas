import Foundation
import XCTest
@testable import StorageCore

final class ReadAccessTests: XCTestCase {
    func testActualReadableDirectoryAndMissingPath() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = ReadAccessCheck.check(paths: [folder.path, folder.appendingPathComponent("missing").path])
        XCTAssertEqual(result.state, .available)
        XCTAssertEqual(result.readableCount, 1)
        XCTAssertEqual(result.deniedCount, 0)
    }

    func testOnlyFreshDenialShowsNotice() {
        let cases: [(ReadAccessCheck.Outcome, ReadAccessState)] = [(.readable, .available), (.denied, .restricted), (.missing, .unknown), (.indeterminate, .unknown)]
        for (outcome, expected) in cases {
            let observation = ReadAccessCheck.check(paths: ["example"], probe: { _ in outcome })
            XCTAssertEqual(observation.state, expected)
            XCTAssertEqual(ReadAccessPreferences.shouldShowNotice(current: observation, dismissed: false), expected == .restricted)
            XCTAssertFalse(ReadAccessPreferences.shouldShowNotice(current: observation, dismissed: true))
        }
        XCTAssertFalse(ReadAccessPreferences.shouldShowNotice(current: nil, dismissed: false))
    }

    func testMissingAndIndeterminateDoNotCertifyAccess() {
        XCTAssertEqual(ReadAccessCheck.check(paths: []).state, .unknown)
        let mixed = ReadAccessCheck.check(paths: ["readable", "other"]) { $0 == "readable" ? .readable : .indeterminate }
        XCTAssertEqual(mixed.state, .unknown)
        let denied = ReadAccessCheck.check(paths: ["readable", "denied", "denied"]) { $0 == "readable" ? .readable : .denied }
        XCTAssertEqual(denied.state, .restricted)
        XCTAssertEqual(denied.deniedCount, 1)
    }

    func testObservationAndDismissalSurviveRelaunchWithoutAuthorizingAnything() throws {
        let suite = "atlas-read-access-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = ReadAccessPreferences(defaults: defaults)
        let date = Date(timeIntervalSince1970: 123456)
        first.save(ReadAccessCheck.check(paths: ["example"], at: date, probe: { _ in .denied }))
        first.dismissNotice()
        let restored = ReadAccessPreferences(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        XCTAssertEqual(restored.lastObservation?.state, .restricted)
        XCTAssertEqual(restored.lastObservation?.checkedAt, date)
        XCTAssertTrue(restored.noticeDismissed)
        XCTAssertFalse(ReadAccessPreferences.shouldShowNotice(current: nil, dismissed: false), "Stored observations never establish this session's access")
        restored.save(ReadAccessCheck.check(paths: ["example"], probe: { _ in .readable }))
        XCTAssertEqual(restored.lastObservation?.state, .available)
        restored.save(ReadAccessCheck.check(paths: ["example"], probe: { _ in .denied }))
        XCTAssertFalse(restored.noticeDismissed, "Newly lost access can be reported")
    }
}
