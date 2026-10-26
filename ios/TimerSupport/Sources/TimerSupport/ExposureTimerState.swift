import Foundation

public enum ExposureTimerStatus: String, Codable { case idle, preparing, active, completed, interrupted }
public enum ExposureTimerError: LocalizedError, Equatable {
    case invalidDuration, alreadyRunning, notificationsUnavailable, schedulingFailed
    public var errorDescription: String? {
        switch self {
        case .invalidDuration: return "計時支援 0.1 秒至 7 天。"
        case .alreadyRunning: return "已有曝光正在計時，請先取消。"
        case .notificationsUnavailable: return "背景通知未獲允許。請到系統設定開啟通知，或明確選擇前景計時。"
        case .schedulingFailed: return "無法排程背景通知，計時未啟動。可重試或改選前景計時。"
        }
    }
}

/// Uses a continuous monotonic clock which includes device sleep, not the wall clock.
/// bootID must identify the current boot; an unavailable boot ID cannot restore a timer.
public struct ExposureTimerState: Codable, Equatable {
    public var id: String
    public var status: ExposureTimerStatus
    public var duration: Double
    public var started: Double
    public var deadline: Double
    public var bootID: String
    public var background: Bool
    public var sound: Bool
    public var vibration: Bool

    public init(id: String = "", status: ExposureTimerStatus = .idle, duration: Double = 0,
                started: Double = 0, deadline: Double = 0, bootID: String = "",
                background: Bool = false, sound: Bool = true, vibration: Bool = true) {
        self.id = id; self.status = status; self.duration = duration; self.started = started
        self.deadline = deadline; self.bootID = bootID; self.background = background
        self.sound = sound; self.vibration = vibration
    }
    public static func begin(seconds: Double, now: Double, bootID: String, background: Bool,
                             sound: Bool, vibration: Bool, current: ExposureTimerState,
                             id: String = UUID().uuidString) throws -> ExposureTimerState {
        guard seconds.isFinite, (0.1...604800).contains(seconds), now.isFinite, now >= 0,
              (now + seconds).isFinite else { throw ExposureTimerError.invalidDuration }
        guard current.status != .active && current.status != .preparing else { throw ExposureTimerError.alreadyRunning }
        return ExposureTimerState(id: id, status: .active, duration: seconds, started: now,
                                  deadline: now + seconds, bootID: bootID, background: background,
                                  sound: sound, vibration: vibration)
    }
    public func remaining(at now: Double) -> Double {
        guard status == .active, now.isFinite else { return 0 }
        return max(0, min(duration, deadline - now))
    }
    public var isValidActiveSnapshot: Bool {
        !id.isEmpty && duration.isFinite && (0.1...604800).contains(duration)
            && started.isFinite && started >= 0 && deadline.isFinite && deadline > started
            && abs((deadline - started) - duration) < 0.001
    }
    /// Returns whether a live transition completed, so a caller can signal at most once.
    @discardableResult public mutating func tick(now: Double, currentBootID: String) -> Bool {
        guard status == .active else { return false }
        guard isValidActiveSnapshot, now.isFinite, now >= started,
              bootID == currentBootID else { status = .interrupted; return false }
        guard now >= deadline else { return false }
        status = .completed
        return true
    }
    public mutating func restore(now: Double, currentBootID: String) {
        guard status == .active || status == .preparing else { return }
        guard status == .active, background, !bootID.isEmpty, !currentBootID.isEmpty else {
            status = .interrupted; return
        }
        _ = tick(now: now, currentBootID: currentBootID)
    }
    public mutating func leaveForeground() {
        if status == .active && !background { status = .interrupted }
    }
}
