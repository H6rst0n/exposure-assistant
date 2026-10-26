import Foundation
import Combine
import UIKit
import UserNotifications
import AudioToolbox
import Darwin
import TimerSupport

enum TimerNotificationAccess: Equatable { case notDetermined, allowed, denied }

@MainActor
protocol TimerNotificationScheduling: AnyObject {
    func access() async -> TimerNotificationAccess
    func requestAuthorization() async throws -> Bool
    func schedule(id: String, interval: Double, duration: Double, sound: Bool) async throws
    func pendingIDs() async -> [String]
    func removePending(_ ids: [String])
    func removeDelivered(_ ids: [String])
    func reset()
}

@MainActor
final class SystemTimerNotifications: TimerNotificationScheduling {
    private let center: UNUserNotificationCenter
    init(center: UNUserNotificationCenter) { self.center = center }
    func access() async -> TimerNotificationAccess {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined { return .notDetermined }
        let authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral
        return authorized && settings.alertSetting == .enabled ? .allowed : .denied
    }
    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
    func schedule(id: String, interval: Double, duration: Double, sound: Bool) async throws {
        let content = UNMutableNotificationContent()
        content.title = "曝光時間已到"
        content.body = "\(duration) 秒已結束，請手動關閉相機快門。"
        content.sound = sound ? .default : nil
        // iOS has no per-notification vibration switch. The app preference applies only
        // to foreground feedback; system notification haptics remain user-controlled.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(0.1, interval), repeats: false)
        try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
    func pendingIDs() async -> [String] { await center.pendingNotificationRequests().map(\.identifier) }
    func removePending(_ ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }
    func removeDelivered(_ ids: [String]) { center.removeDeliveredNotifications(withIdentifiers: ids) }
    func reset() { center.removeAllPendingNotificationRequests(); center.removeAllDeliveredNotifications() }
}

/// iOS notifications are best-effort, not an exact-alarm or camera-control API.
/// Sound / Focus / notification settings and background scheduling remain system controlled.
@MainActor
final class TimerController: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var state = ExposureTimerState()
    @Published private(set) var remaining: Double = 0
    @Published private(set) var isStarting = false
    @Published var message: String?
    var isRunning: Bool { state.status == .active }

    private let defaults: UserDefaults
    private let notifications: TimerNotificationScheduling
    private let signal: (Bool, Bool) -> Void
    private var signaledID: String?
    private let key = "exposure.ios.timer.v1"
    nonisolated private static let prefix = "exposure.timer."
    private var ticker: AnyCancellable?
    private var generation = UUID()
    private var foreground = true
    private var appWasActive = true
    private let now: () -> Double
    private let boot: () -> String
    private var notificationID: String { Self.prefix + state.id }

    init(defaults: UserDefaults = .standard,
         center: UNUserNotificationCenter = .current(),
         notifications: TimerNotificationScheduling? = nil,
         signal: @escaping (Bool, Bool) -> Void = { sound, vibration in
             if sound { AudioServicesPlaySystemSound(1005) }
             if vibration { UINotificationFeedbackGenerator().notificationOccurred(.success) }
         },
         now: @escaping () -> Double = { Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000 },
         boot: @escaping () -> String = TimerController.bootIdentifier) {
        self.defaults = defaults; self.notifications = notifications ?? SystemTimerNotifications(center: center)
        self.signal = signal; self.now = now; self.boot = boot
        super.init()
        if notifications == nil { center.delegate = self }
        if ProcessInfo.processInfo.arguments.contains("--uitesting-reset") {
            defaults.removeObject(forKey: key)
            self.notifications.reset()
        }
        if let data = defaults.data(forKey: key), let restored = try? JSONDecoder().decode(ExposureTimerState.self, from: data) {
            state = restored
            state.restore(now: now(), currentBootID: boot())
            if state.status == .interrupted {
                self.notifications.removePending([notificationID])
                message = "先前計時已中斷（重新啟動、排程未完成或僅前景模式），未自動重啟。"
            }
            persist()
        }
        remaining = state.remaining(at: now())
        ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.tick(signal: true)
        }
        updateIdleTimer()
        // No authorization prompt during launch. Validate an existing background schedule only.
        Task { [weak self] in await self?.validatePendingSchedule() }
    }

    nonisolated private static func bootIdentifier() -> String {
        var mib = [CTL_KERN, KERN_BOOTTIME]
        var value = timeval(); var size = MemoryLayout<timeval>.size
        let result = mib.withUnsafeMutableBufferPointer { pointer in
            sysctl(pointer.baseAddress, 2, &value, &size, nil, 0)
        }
        guard result == 0 else { return "" }
        return "\(value.tv_sec):\(value.tv_usec)"
    }

    func start(seconds: Double, background: Bool, sound: Bool, vibration: Bool) async throws {
        guard !isStarting && !isRunning else { throw ExposureTimerError.alreadyRunning }
        // Validate before displaying a notification permission prompt.
        _ = try ExposureTimerState.begin(seconds: seconds, now: now(), bootID: boot(), background: background,
                                         sound: sound, vibration: vibration, current: state)
        isStarting = true
        let token = UUID(); generation = token
        let identifier = UUID().uuidString
        let requestID = Self.prefix + identifier
        defer { if generation == token { isStarting = false } }
        do {
            if background {
                var access = await notifications.access()
                guard generation == token && !Task.isCancelled else { throw CancellationError() }
                if access == .notDetermined {
                    let allowed = try await notifications.requestAuthorization()
                    guard generation == token && !Task.isCancelled else { throw CancellationError() }
                    guard allowed else { throw ExposureTimerError.notificationsUnavailable }
                    access = await notifications.access()
                }
                guard generation == token && !Task.isCancelled else { throw CancellationError() }
                guard access == .allowed else { throw ExposureTimerError.notificationsUnavailable }
            }
            guard generation == token && !Task.isCancelled else { throw CancellationError() }
            guard UIApplication.shared.applicationState != .background else { throw CancellationError() }
            // A permission dialog can temporarily inactivate the scene; starting only requires the
            // app not to have entered background. A background transition cancels preparation.
            var candidate = try ExposureTimerState.begin(seconds: seconds, now: now(), bootID: boot(),
                background: background, sound: sound, vibration: vibration, current: state, id: identifier)
            notifications.removePending([notificationID])
            notifications.removeDelivered([notificationID])
            signaledID = nil
            if background {
                candidate.status = .preparing; state = candidate; persist()
                do {
                    try await notifications.schedule(id: requestID, interval: candidate.deadline - now(),
                                                     duration: seconds, sound: sound)
                }
                catch { throw ExposureTimerError.schedulingFailed }
                guard generation == token && !Task.isCancelled else {
                    notifications.removePending([requestID])
                    notifications.removeDelivered([requestID])
                    throw CancellationError()
                }
            }
            candidate.status = .active; state = candidate; message = nil; persist()
            remaining = state.remaining(at: now()); updateIdleTimer()
            tick(signal: true)
        } catch {
            // Cancel can race both permission and add(). Never clear a newer timer.
            notifications.removePending([requestID])
            if generation == token {
                state = ExposureTimerState(); remaining = 0; persist(); updateIdleTimer()
            }
            throw error
        }
    }

    func cancel() {
        let old = notificationID
        generation = UUID(); isStarting = false
        state = ExposureTimerState(); remaining = 0; message = nil
        persist(); updateIdleTimer()
        notifications.removePending([old])
        notifications.removeDelivered([old])
    }

    /// Parent should pass scenePhase == .active. Inactive is treated conservatively for
    /// foreground-only timers, except while the system authorization prompt is starting.
    func sceneChanged(active: Bool) {
        foreground = active
        if !active && appWasActive && isRunning && !state.background {
            state.leaveForeground(); message = "前景計時已中斷：切換 App 或鎖屏後不保證提醒，請重新確認曝光。"
            remaining = 0; persist()
        }
        appWasActive = active
        updateIdleTimer()
        if active { reconcile() }
    }

    /// Wire only to scenePhase == .background, not .inactive (permission dialogs).
    func sceneBackgrounded() {
        if isStarting {
            cancel()
            message = "啟動計時期間離開 App，已取消啟動；返回後請重新確認。"
        }
        sceneChanged(active: false)
    }

    func reconcile() {
        tick(signal: false)
        Task { [weak self] in await self?.validatePendingSchedule() }
    }

    func tick(signal: Bool) {
        guard isRunning else { return }
        let oldStatus = state.status
        let finished = state.tick(now: now(), currentBootID: boot())
        remaining = state.remaining(at: now())
        if state.status != oldStatus {
            persist(); updateIdleTimer()
            if state.status == .interrupted {
                notifications.removePending([notificationID])
                message = "計時時鐘已重設或資料無法確認，計時中斷，請手動確認相機。"
            } else if finished {
                message = "曝光時間已到，請手動關閉相機快門。"
                // Keep the OS reminder unless the foreground actually owns delivery. A tick
                // during suspension/reconciliation must not cancel the only remaining alert.
                if foreground && signal { signalCompletion() }
            }
        }
    }

    private func validatePendingSchedule() async {
        guard isRunning && state.background else { return }
        let expected = state.id
        let requests = await notifications.pendingIDs()
        guard isRunning && state.id == expected else { return }
        tick(signal: false)
        guard isRunning else { return }
        let access = await notifications.access()
        guard isRunning && state.id == expected else { return }
        // Near expiry, delivery may already have removed the pending request.
        if remaining > 1 && (!requests.contains(notificationID) || access != .allowed) {
            state.status = .interrupted; remaining = 0
            notifications.removePending([notificationID])
            message = "背景提醒排程或通知權限已失效，計時已中斷；請確認曝光後重新開始。"
            persist(); updateIdleTimer()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: key) }
    }
    private func updateIdleTimer() { UIApplication.shared.isIdleTimerDisabled = foreground && isRunning }

    private func signalCompletion() {
        guard state.status == .completed, signaledID != state.id else { return }
        signaledID = state.id
        notifications.removePending([notificationID])
        signal(state.sound, state.vibration)
    }

    /// Called only for delivery while the app is foregrounded. A completed snapshot may
    /// have been reconciled without a signal, so don't silently suppress that OS delivery.
    func notificationArrivedInForeground(id: String) {
        guard id == notificationID else { return }
        tick(signal: true)
        if state.status == .completed { signalCompletion() }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if notification.request.identifier.hasPrefix(Self.prefix) {
            completionHandler([])
            let id = notification.request.identifier
            Task { @MainActor [weak self] in self?.notificationArrivedInForeground(id: id) }
        } else { completionHandler([.banner, .sound]) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
        Task { @MainActor [weak self] in self?.reconcile() }
    }
}
