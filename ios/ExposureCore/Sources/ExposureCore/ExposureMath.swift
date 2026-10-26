import Foundation

public enum Films {
    public static let SOURCE = "https://www.ilfordphoto.com/amfile/file/download/file/1964/product/698/"
    public static let VERSION = "ILFORD / HARMAN · Dec 2023"
    public static let all: [Film] = [
        Film(id: "sfx", name: "SFX 200", exponent: 1.43), Film(id: "panf", name: "Pan F Plus", exponent: 1.33),
        Film(id: "d100", name: "DELTA 100", exponent: 1.26), Film(id: "d400", name: "DELTA 400", exponent: 1.41),
        Film(id: "d3200", name: "DELTA 3200", exponent: 1.33), Film(id: "fp4", name: "FP4 Plus", exponent: 1.26),
        Film(id: "hp5", name: "HP5 Plus", exponent: 1.31), Film(id: "xp2", name: "XP2 Super", exponent: 1.31),
        Film(id: "ortho", name: "ORTHO Plus", exponent: 1.25), Film(id: "k100", name: "Kentmere 100", exponent: 1.26),
        Film(id: "k400", name: "Kentmere 400", exponent: 1.30)
    ]
    public static func find(_ id: String) -> Film? { all.first { $0.id == id } }
    public static func corrected(_ seconds: Double, film: Film) throws -> Double {
        guard seconds.isFinite && seconds > 0 else { throw ExposureError("曝光時間必須大於 0") }
        let result = seconds <= 1 ? seconds : pow(seconds, film.exponent)
        guard result.isFinite else { throw ExposureError("補償時間超出可計算範圍") }
        return result
    }
}
public enum ExposureMath {
    public static func positive(_ text: String, name: String) throws -> Double {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/", omittingEmptySubsequences: false)
        var value: Double?
        if parts.count == 1 { value = Double(parts[0]) }
        if parts.count == 2, let a = Double(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)), let b = Double(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)), a > 0, b > 0 { value = a / b }
        guard let result = value, result.isFinite, result > 0 else { throw ExposureError("\(name) 請輸入大於 0 的數值（快門可用 1/125）") }
        return result
    }
    public static func compensation(_ text: String) throws -> Double {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite, abs(value) <= 100 else { throw ExposureError("曝光補償請輸入 −100 到 +100 檔") }
        return value
    }
    /// A plus sign denotes stacked filters, not arithmetic addition of factors.
    public static func nd(_ text: String, unit: NdUnit) throws -> Double {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ExposureError("請輸入 ND；無濾鏡請填 0 檔或 1 倍") }
        let sum = try text.split(separator: "+", omittingEmptySubsequences: false).reduce(0.0) { total, part in
            guard let v = Double(part.trimmingCharacters(in: .whitespacesAndNewlines)), v.isFinite else { throw ExposureError("ND 請輸入數字，多片以 + 相連") }
            switch unit {
            case .stops: guard v >= 0 else { throw ExposureError("ND 檔數不可小於 0") }; return total + v
            case .factor: guard v >= 1 else { throw ExposureError("ND 倍率至少為 1") }; return total + log2(v)
            case .density: guard v >= 0 else { throw ExposureError("光學密度不可小於 0") }; return total + v / log10(2)
            }
        }
        guard sum.isFinite && sum <= 100 else { throw ExposureError("ND 總量請勿超過 100 檔") }
        return sum
    }
    public static func level(_ e: Exposure) -> Double { log2(e.seconds) + log2(e.iso) - 2 * log2(e.aperture) - e.nd }
    public static func solve(reference: Exposure, target: Exposure, what: Solve, compensation: Double) throws -> Double {
        guard [reference.aperture, reference.seconds, reference.iso, target.aperture, target.seconds, target.iso].allSatisfy({ $0.isFinite && $0 > 0 }) else { throw ExposureError("光圈、快門與 ISO 必須大於 0") }
        guard reference.nd.isFinite, target.nd.isFinite, reference.nd >= 0, target.nd >= 0, compensation.isFinite else { throw ExposureError("ND 與曝光補償必須是有效數值") }
        let desired = level(reference) + compensation
        let logResult: Double
        switch what {
        case .shutter: logResult = desired - log2(target.iso) + 2 * log2(target.aperture) + target.nd
        case .iso: logResult = desired - log2(target.seconds) + 2 * log2(target.aperture) + target.nd
        case .aperture: logResult = (log2(target.seconds) + log2(target.iso) - target.nd - desired) / 2
        case .nd:
            var unfiltered = target; unfiltered.nd = 0
            let result = level(unfiltered) - desired
            guard result.isFinite && abs(result) <= 100 else { throw ExposureError("ND 結果超出 ±100 檔，請縮小參數差距") }
            return result
        }
        let result = pow(2, logResult)
        guard result.isFinite && result > 0 else { throw ExposureError("結果超出可計算範圍，請縮小參數差距") }
        return result
    }
    public static let shutters: [Double] = [8000,6400,5000,4000,3200,2500,2000,1600,1250,1000,800,640,500,400,320,250,200,160,125,100,80,60,50,40,30,25,20,15,13,10,8,6,5,4,3,2].map { 1.0 / Double($0) } + [0.6,0.8,1,1.3,1.6,2,2.5,3.2,4,5,6,8,10,13,15,20,25,30]
    public static let apertures: [Double] = [1,1.2,1.4,1.6,1.8,2,2.2,2.5,2.8,3.2,3.5,4,4.5,5,5.6,6.3,7.1,8,9,10,11,13,14,16,18,20,22,25,29,32,36,40,45,51,57,64]
    public static let isos: [Double] = [25,32,40,50,64,80,100,125,160,200,250,320,400,500,640,800,1000,1250,1600,2000,2500,3200,4000,5000,6400,8000,10000,12800,16000,20000,25600,32000,40000,51200,64000,80000,102400,128000,160000,204800]
    public static func common(_ value: Double, what: Solve) -> Double? {
        guard value.isFinite else { return nil }
        if what == .nd { return value < 0 ? nil : value.rounded(.toNearestOrEven) }
        guard value > 0 else { return nil }
        if what == .shutter && value > 30 { return value <= 604800 ? max(1, value.rounded()) : nil }
        let choices = what == .shutter ? shutters : (what == .iso ? isos : apertures)
        guard value >= choices[0], value <= choices[choices.count - 1] else { return nil }
        return choices.min { abs(log2($0 / value)) < abs(log2($1 / value)) }
    }
    public static func roundingStops(exact: Double, common: Double, what: Solve) -> Double {
        switch what { case .aperture: return -2 * log2(common / exact); case .nd: return exact - common; default: return log2(common / exact) }
    }
}
public func number(_ value: Double) -> String {
    if value == 0 { return "0" }
    if abs(value) >= 1e8 || abs(value) < 0.0001 { return String(format: "%.4g", locale: Locale(identifier: "en_US_POSIX"), value) }
    var result = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
    while result.last == "0" { result.removeLast() }
    if result.last == "." { result.removeLast() }
    return result
}
public func secondsLabel(_ value: Double) -> String { value < 1 && (1 / value).isFinite ? "1/\(number(1 / value)) 秒" : "\(number(value)) 秒" }
public func valueLabel(_ value: Double, solve: Solve) -> String {
    switch solve { case .shutter: return secondsLabel(value); case .aperture: return "f/\(number(value))"; case .iso: return "ISO \(number(value))"; case .nd: return "\(number(value)) 檔" }
}
public func durationLabel(_ seconds: Int64) -> String { let s = max(0, seconds); return String(format: "%02lld:%02lld:%02lld", s / 3600, (s % 3600) / 60, s % 60) }
public let STAR_NOTICE = "固定腳架、未使用追蹤設備時，可用以下方式粗估曝光時間：\n\n曝光秒數 ≈ 500 ÷ 全片幅等效焦距\n\n全片幅使用 50 mm，約為 10 秒。\nAPS-C 裁切倍率 1.5×、使用 50 mm 時，約為 6.7 秒。\n\n這是經驗估算，不是保證不拖線的硬性極限。高像素相機或放大檢視可能需要更短曝光；建議試拍後放大檢查星點。\n\n這項提醒不會更改你的快門設定。"
