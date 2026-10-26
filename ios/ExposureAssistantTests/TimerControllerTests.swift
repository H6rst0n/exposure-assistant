import XCTest
import TimerSupport
@testable import ExposureAssistant

@MainActor
final class TimerControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var instant = 100.0
    override func setUp() async throws {
        suite = "TimerControllerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        instant = 100
    }
    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }
    private func controller() -> TimerController {
        TimerController(defaults: defaults, now: { [unowned self] in self.instant }, boot: { "test-boot" })
    }
    func testForegroundStartSnapshotAndCancel() async throws {
        let timer = controller()
        try await timer.start(seconds: 10, background: false, sound: false, vibration: false)
        XCTAssertTrue(timer.isRunning)
        XCTAssertEqual(timer.remaining, 10, accuracy: 0.001)
        XCTAssertFalse(timer.state.background)
        XCTAssertFalse(timer.state.sound)
        XCTAssertFalse(timer.state.vibration)
        timer.cancel()
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.state.status, .idle)
        XCTAssertEqual(timer.remaining, 0)
    }
    func testInvalidDurationAndDuplicateCannotReplace() async throws {
        let timer = controller()
        do { try await timer.start(seconds: 0, background: false, sound: false, vibration: false); XCTFail("Must reject") }
        catch { XCTAssertEqual(error as? ExposureTimerError, .invalidDuration) }
        try await timer.start(seconds: 10, background: false, sound: false, vibration: false)
        let originalID = timer.state.id
        do { try await timer.start(seconds: 20, background: false, sound: false, vibration: false); XCTFail("Must reject") }
        catch { XCTAssertEqual(error as? ExposureTimerError, .alreadyRunning) }
        XCTAssertEqual(timer.state.id, originalID)
        XCTAssertEqual(timer.state.duration, 10)
        timer.cancel()
    }
    func testCompletionOnlyOnceThenNewTimer() async throws {
        let timer = controller()
        try await timer.start(seconds: 2, background: false, sound: false, vibration: false)
        instant = 102
        timer.reconcile()
        XCTAssertEqual(timer.state.status, .completed)
        timer.reconcile()
        XCTAssertEqual(timer.state.status, .completed)
        try await timer.start(seconds: 3, background: false, sound: false, vibration: false)
        XCTAssertEqual(timer.remaining, 3)
        timer.cancel()
    }
    func testForegroundInterruptionDoesNotRestartOnReturn() async throws {
        let timer = controller()
        try await timer.start(seconds: 20, background: false, sound: false, vibration: false)
        timer.sceneChanged(active: false)
        XCTAssertEqual(timer.state.status, .interrupted)
        timer.sceneChanged(active: true)
        XCTAssertEqual(timer.state.status, .interrupted)
        XCTAssertEqual(timer.remaining, 0)
        timer.cancel()
    }
    func testForegroundProcessRelaunchIsInterrupted() async throws {
        let timer = controller()
        try await timer.start(seconds: 20, background: false, sound: false, vibration: false)
        let restored = controller()
        XCTAssertEqual(restored.state.status, .interrupted)
        XCTAssertFalse(restored.isRunning)
        timer.cancel(); restored.cancel()
    }
    func testCancelOldDeadlineCannotCompleteReplacement() async throws {
        let timer = controller()
        try await timer.start(seconds: 2, background: false, sound: false, vibration: false)
        timer.cancel()
        try await timer.start(seconds: 20, background: false, sound: false, vibration: false)
        instant = 103; timer.reconcile()
        XCTAssertEqual(timer.state.status, .active)
        XCTAssertEqual(timer.remaining, 17)
        timer.cancel()
    }
}
