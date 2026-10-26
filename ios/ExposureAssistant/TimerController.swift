import Foundation
import Combine
import UIKit
import UserNotifications
import AudioToolbox
import Darwin
import TimerSupport

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
    private let center: UNUserNotificationCenter
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
         now: @escaping () -> Double = { Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000 },
         boot: @escaping () -> String = TimerController.bootIdentifier) {
        self.defaults = defaults; self.center = center; self.now = now; self.boot = boot
        super.init()
        center.delegate = self
        if ProcessInfo.processInfo.arguments.contains("--uitesting-reset") {
            defaults.removeObject(forKey: key)
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
        }
        if let data = defaults.data(forKey: key), let restored = try? JSONDecoder().decode(ExposureTimerState.self, from: data) {
            state = restored
            state.restore(now: now(), currentBootID: boot())
            if state.status == .interrupted {
                center.removePendingNotificationRequests(withIdentifiers: [notificationID])
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
                var settings = await center.notificationSettings()
                guard generation == token else { throw CancellationError() }
                if settings.authorizationStatus == .notDetermined {
                    let allowed = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                    guard generation == token else { throw CancellationError() }
                    guard allowed else { throw ExposureTimerError.notificationsUnavailable }
                    settings = await center.notificationSettings()
                }
                guard generation == token else { throw CancellationError() }
                guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral else {
                    throw ExposureTimerError.notificationsUnavailable
                }
                guard settings.alertSetting == .enabled else { throw ExposureTimerError.notificationsUnavailable }
            }
            guard generation == token else { throw CancellationError() }
            guard UIApplication.shared.applicationState != .background else { throw CancellationError() }
            // A permission dialog can temporarily inactivate the scene; starting only requires the
            // app not to have entered background. A background transition cancels preparation.
            var candidate = try ExposureTimerState.begin(seconds: seconds, now: now(), bootID: boot(),
                background: background, sound: sound, vibration: vibration, current: state, id: identifier)
            center.removeDeliveredNotifications(withIdentifiers: [notificationID])
            if background {
                candidate.status = .preparing; state = candidate; persist()
                let content = UNMutableNotificationContent()
                content.title = "曝光時間已到"
                content.body = "\(seconds) 秒已結束，請手動關閉相機快門。"
                content.sound = sound ? .default : nil
                // iOS offers no independent notification vibration switch; preference applies
                // only to the app's foreground signal, never a promise about system haptics.
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(0.1, candidate.deadline - now()), repeats: false)
                do { try await center.add(UNNotificationRequest(identifier: requestID, content: content, trigger: trigger)) }
                catch { throw ExposureTimerError.schedulingFailed }
                guard generation == token else {
                    center.removePendingNotificationRequests(withIdentifiers: [requestID])
                    center.removeDeliveredNotifications(withIdentifiers: [requestID])
                    throw CancellationError()
                }
            }
            candidate.status = .active; state = candidate; message = nil; persist()
            remaining = state.remaining(at: now()); updateIdleTimer()
            tick(signal: true)
        } catch {
            // Cancel can race both permission and add(). Never clear a newer timer.
            center.removePendingNotificationRequests(withIdentifiers: [requestID])
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
        center.removePendingNotificationRequests(withIdentifiers: [old])
        center.removeDeliveredNotifications(withIdentifiers: [old])
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

    private func tick(signal: Bool) {
        guard isRunning else { return }
        let oldStatus = state.status
        let finished = state.tick(now: now(), currentBootID: boot())
        remaining = state.remaining(at: now())
        if state.status != oldStatus {
            persist(); updateIdleTimer()
            if state.status == .interrupted {
                center.removePendingNotificationRequests(withIdentifiers: [notificationID])
                message = "計時時鐘已重設或資料無法確認，計時中斷，請手動確認相機。"
            } else if finished {
                center.removePendingNotificationRequests(withIdentifiers: [notificationID])
                message = "曝光時間已到，請手動關閉相機快門。"
                if foreground && signal {
                    if state.sound { AudioServicesPlaySystemSound(1005) }
                    if state.vibration { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                }
            }
        }
    }

    private func validatePendingSchedule() async {
        guard isRunning && state.background else { return }
        let expected = state.id
        let requests = await center.pendingNotificationRequests()
        guard isRunning && state.id == expected else { return }
        tick(signal: false)
        guard isRunning else { return }
        let settings = await center.notificationSettings()
        guard isRunning && state.id == expected else { return }
        // Near expiry, delivery may already have removed the pending request.
        if remaining > 1 && (!requests.contains(where: { $0.identifier == notificationID }) || settings.authorizationStatus == .denied || settings.alertSetting != .enabled) {
            state.status = .interrupted; remaining = 0
            center.removePendingNotificationRequests(withIdentifiers: [notificationID])
            message = "背景提醒排程或通知權限已失效，計時已中斷；請確認曝光後重新開始。"
            persist(); updateIdleTimer()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: key) }
    }
    private func updateIdleTimer() { UIApplication.shared.isIdleTimerDisabled = foreground && isRunning }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if notification.request.identifier.hasPrefix(Self.prefix) {
            // The foreground timer owns the signal to prevent double sound/haptics.
            completionHandler([])
            Task { @MainActor [weak self] in self?.tick(signal: true) }
        } else { completionHandler([.banner, .sound]) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
        Task { @MainActor [weak self] in self?.reconcile() }
    }
}
