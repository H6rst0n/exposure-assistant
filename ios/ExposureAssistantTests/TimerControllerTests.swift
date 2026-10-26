import XCTest
import TimerSupport
@testable import ExposureAssistant

@MainActor
final class TimerControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var instant = 100.0
    private var notifications: FakeTimerNotifications!
    private var signalCount = 0
    override func setUp() async throws {
        suite = "TimerControllerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        instant = 100
        notifications = FakeTimerNotifications()
        signalCount = 0
    }
    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }
    private func controller() -> TimerController {
        TimerController(defaults: defaults, notifications: notifications, signal: { [weak self] _, _ in self?.signalCount += 1 }, now: { [unowned self] in self.instant }, boot: { "test-boot" })
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
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<2000 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Timed out waiting for async checkpoint")
    }
    func testDeniedNotificationDoesNotSilentlyStartForeground() async throws {
        notifications.authorization = .denied
        let timer = controller()
        do { try await timer.start(seconds: 20, background: true, sound: false, vibration: false); XCTFail("Must reject") }
        catch { XCTAssertEqual(error as? ExposureTimerError, .notificationsUnavailable) }
        XCTAssertEqual(timer.state.status, .idle)
        XCTAssertFalse(timer.isStarting)
        XCTAssertTrue(notifications.pending.isEmpty)
    }
    func testCancelWhilePermissionPendingDoesNotStart() async throws {
        notifications.authorization = .notDetermined
        notifications.holdAuthorization = true
        let timer = controller()
        let task = Task { try await timer.start(seconds: 20, background: true, sound: false, vibration: false) }
        await waitUntil { self.notifications.authorizationContinuation != nil }
        timer.cancel()
        notifications.finishAuthorization(true)
        do { try await task.value; XCTFail("Must cancel") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(timer.state.status, .idle)
        XCTAssertTrue(notifications.pending.isEmpty)
    }
    func testCancelledStartTaskDoesNotContinueAfterPermission() async throws {
        notifications.authorization = .notDetermined
        notifications.holdAuthorization = true
        let timer = controller()
        let task = Task { try await timer.start(seconds: 20, background: true, sound: false, vibration: false) }
        await waitUntil { self.notifications.authorizationContinuation != nil }
        task.cancel()
        notifications.finishAuthorization(true)
        do { try await task.value; XCTFail("Must cancel") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(timer.state.status, .idle)
        XCTAssertFalse(timer.isStarting)
        XCTAssertTrue(notifications.pending.isEmpty)
    }
    func testBackgroundDuringPermissionPreparationCancels() async throws {
        notifications.authorization = .notDetermined
        notifications.holdAuthorization = true
        let timer = controller()
        let task = Task { try await timer.start(seconds: 20, background: true, sound: false, vibration: false) }
        await waitUntil { self.notifications.authorizationContinuation != nil }
        timer.sceneBackgrounded()
        notifications.finishAuthorization(true)
        do { try await task.value; XCTFail("Must cancel") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(timer.state.status, .idle)
        XCTAssertFalse(timer.isStarting)
    }
    func testCancelDuringScheduleCannotResurrectOrEraseNewTimer() async throws {
        notifications.holdSchedule = true
        let timer = controller()
        let task = Task { try await timer.start(seconds: 20, background: true, sound: false, vibration: false) }
        await waitUntil { self.notifications.scheduleContinuation != nil }
        XCTAssertEqual(timer.state.status, .preparing)
        timer.cancel()
        try await timer.start(seconds: 40, background: false, sound: false, vibration: false)
        let newID = timer.state.id
        notifications.finishSchedule()
        do { try await task.value; XCTFail("Must cancel") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(timer.state.id, newID)
        XCTAssertEqual(timer.state.duration, 40)
        XCTAssertTrue(timer.isRunning)
        XCTAssertTrue(notifications.pending.isEmpty)
        timer.cancel()
    }
    func testScheduleFailureRollsBackWithoutFallback() async throws {
        notifications.failSchedule = true
        let timer = controller()
        do { try await timer.start(seconds: 20, background: true, sound: false, vibration: false); XCTFail("Must fail") }
        catch { XCTAssertEqual(error as? ExposureTimerError, .schedulingFailed) }
        XCTAssertEqual(timer.state.status, .idle)
        XCTAssertTrue(notifications.pending.isEmpty)
    }
    func testBackgroundTickPreservesOnlyOSReminder() async throws {
        let timer = controller()
        try await timer.start(seconds: 2, background: true, sound: false, vibration: false)
        let request = "exposure.timer." + timer.state.id
        timer.sceneChanged(active: false)
        instant = 103; timer.tick(signal: true)
        XCTAssertEqual(timer.state.status, .completed)
        XCTAssertTrue(notifications.pending.contains(request))
        XCTAssertEqual(signalCount, 0)
        timer.cancel()
    }
    func testSilentReconcilePreservesReminderAndForegroundDeliverySignalsOnce() async throws {
        let timer = controller()
        try await timer.start(seconds: 2, background: true, sound: false, vibration: false)
        let request = "exposure.timer." + timer.state.id
        instant = 103; timer.reconcile()
        XCTAssertEqual(timer.state.status, .completed)
        XCTAssertTrue(notifications.pending.contains(request))
        XCTAssertEqual(signalCount, 0)
        timer.notificationArrivedInForeground(id: request)
        timer.notificationArrivedInForeground(id: request)
        XCTAssertEqual(signalCount, 1)
        XCTAssertFalse(notifications.pending.contains(request))
        timer.cancel()
    }
    func testForegroundCompletionOwnsAlertAndSuppressesDuplicate() async throws {
        let timer = controller()
        try await timer.start(seconds: 2, background: true, sound: false, vibration: false)
        let request = "exposure.timer." + timer.state.id
        instant = 103; timer.tick(signal: true)
        XCTAssertEqual(timer.state.status, .completed)
        XCTAssertEqual(signalCount, 1)
        XCTAssertFalse(notifications.pending.contains(request))
        timer.notificationArrivedInForeground(id: request)
        XCTAssertEqual(signalCount, 1)
        timer.cancel()
    }

}


@MainActor
private final class FakeTimerNotifications: TimerNotificationScheduling {
    var authorization = TimerNotificationAccess.allowed
    var holdAuthorization = false
    var holdSchedule = false
    var failSchedule = false
    var pending = Set<String>()
    var authorizationContinuation: CheckedContinuation<Bool, Never>?
    var scheduleContinuation: CheckedContinuation<Void, Never>?
    func access() async -> TimerNotificationAccess { authorization }
    func requestAuthorization() async throws -> Bool {
        if holdAuthorization {
            return await withCheckedContinuation { authorizationContinuation = $0 }
        }
        return authorization == .allowed
    }
    func finishAuthorization(_ allowed: Bool) {
        authorization = allowed ? .allowed : .denied
        let continuation = authorizationContinuation; authorizationContinuation = nil
        continuation?.resume(returning: allowed)
    }
    func schedule(id: String, interval: Double, duration: Double, sound: Bool) async throws {
        if failSchedule { throw ExposureTimerError.schedulingFailed }
        if holdSchedule { await withCheckedContinuation { scheduleContinuation = $0 } }
        pending.insert(id)
    }
    func finishSchedule() {
        let continuation = scheduleContinuation; scheduleContinuation = nil
        continuation?.resume()
    }
    func pendingIDs() async -> [String] { Array(pending) }
    func removePending(_ ids: [String]) { for id in ids { pending.remove(id) } }
    func removeDelivered(_ ids: [String]) {}
    func reset() { pending.removeAll() }
}
