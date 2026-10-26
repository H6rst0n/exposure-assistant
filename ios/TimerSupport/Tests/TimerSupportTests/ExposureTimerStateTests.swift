import XCTest
@testable import TimerSupport
final class ExposureTimerStateTests: XCTestCase {
    func make(_ duration: Double = 10, background: Bool = true) throws -> ExposureTimerState {
        try .begin(seconds: duration, now: 100, bootID: "boot-a", background: background,
                   sound: true, vibration: true, current: .init(), id: "timer-a")
    }
    func testBoundsAndNonfinite() throws {
        for value in [0.0, -1, 0.099, 604801, .infinity, .nan] { XCTAssertThrowsError(try make(value)) }
        XCTAssertEqual(try make(0.1).duration, 0.1)
        XCTAssertEqual(try make(604800).duration, 604800)
    }
    func testNoReplacement() throws {
        let running = try make()
        XCTAssertThrowsError(try ExposureTimerState.begin(seconds: 2, now: 101, bootID: "boot-a", background: false, sound: false, vibration: false, current: running))
        var preparing = running; preparing.status = .preparing
        XCTAssertThrowsError(try ExposureTimerState.begin(seconds: 2, now: 101, bootID: "boot-a", background: false, sound: false, vibration: false, current: preparing))
    }
    func testMonotonicCountdownAndExactlyOnceFinish() throws {
        var t = try make()
        XCTAssertEqual(t.remaining(at: 104), 6)
        XCTAssertFalse(t.tick(now: 109.99, currentBootID: "boot-a"))
        XCTAssertTrue(t.tick(now: 110, currentBootID: "boot-a"))
        XCTAssertFalse(t.tick(now: 111, currentBootID: "boot-a"))
        XCTAssertEqual(t.status, .completed)
        XCTAssertEqual(t.remaining(at: 111), 0)
    }
    func testBackgroundSleepElapsed() throws {
        var t = try make(60)
        t.restore(now: 400, currentBootID: "boot-a")
        XCTAssertEqual(t.status, .completed)
    }
    func testRebootAndBackwardClockInterrupt() throws {
        var t = try make(); t.restore(now: 5, currentBootID: "boot-b")
        XCTAssertEqual(t.status, .interrupted)
        t = try make(); t.restore(now: 5, currentBootID: "boot-a")
        XCTAssertEqual(t.status, .interrupted)
    }
    func testForegroundOnlyLosesGuaranteeWhenLeavingOrRelaunching() throws {
        var t = try make(background: false); t.leaveForeground()
        XCTAssertEqual(t.status, .interrupted)
        t = try make(background: false); t.restore(now: 102, currentBootID: "boot-a")
        XCTAssertEqual(t.status, .interrupted)
    }
    func testBackgroundContinuesAndRoundTrips() throws {
        var t = try make(); t.leaveForeground(); t.restore(now: 105, currentBootID: "boot-a")
        XCTAssertEqual(t.status, .active)
        let data = try JSONEncoder().encode(t)
        XCTAssertEqual(try JSONDecoder().decode(ExposureTimerState.self, from: data), t)
    }
    func testPreparingOrMissingBootDoesNotRestore() throws {
        var t = try make(); t.status = .preparing; t.restore(now: 105, currentBootID: "boot-a")
        XCTAssertEqual(t.status, .interrupted)
        t = try make(); t.bootID = ""; t.restore(now: 105, currentBootID: "")
        XCTAssertEqual(t.status, .interrupted)
    }
    func testCorruptSnapshotDoesNotComplete() throws {
        var t = try make(); t.deadline = 99; XCTAssertFalse(t.tick(now: 105, currentBootID: "boot-a"))
        XCTAssertEqual(t.status, .interrupted)
    }
}
