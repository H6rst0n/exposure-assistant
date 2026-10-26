import Foundation

public enum Solve: String, Codable, CaseIterable, Identifiable, Sendable {
    case shutter, aperture, iso, nd
    public var id: Self { self }
    public var label: String { switch self { case .shutter: return "快門"; case .aperture: return "光圈"; case .iso: return "ISO"; case .nd: return "ND" } }
}
public enum NdUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case stops, factor, density
    public var id: Self { self }
    public var label: String { switch self { case .stops: return "檔數"; case .factor: return "倍率"; case .density: return "光學密度" } }
}
public struct Exposure: Equatable, Sendable {
    public var aperture: Double
    public var seconds: Double
    public var iso: Double
    public var nd: Double
    public init(aperture: Double, seconds: Double, iso: Double, nd: Double = 0) { self.aperture = aperture; self.seconds = seconds; self.iso = iso; self.nd = nd }
}
public struct Film: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let exponent: Double
    public init(id: String, name: String, exponent: Double) { self.id = id; self.name = name; self.exponent = exponent }
}
public struct Inputs: Codable, Equatable, Sendable {
    public var aperture: String
    public var shutter: String
    public var iso: String
    public var nd: String
    public var unit: NdUnit
    public init(aperture: String = "", shutter: String = "", iso: String = "", nd: String = "0", unit: NdUnit = .stops) { self.aperture = aperture; self.shutter = shutter; self.iso = iso; self.nd = nd; self.unit = unit }
}
public struct FormState: Codable, Equatable, Sendable {
    public var reference: Inputs
    public var target: Inputs
    public var solve: Solve
    public var compensation: String
    public var filmMode: Bool
    public var filmId: String
    public init(reference: Inputs = Inputs(), target: Inputs = Inputs(aperture: "2", shutter: "2", iso: "400"), solve: Solve = .shutter, compensation: String = "0", filmMode: Bool = false, filmId: String = "hp5") { self.reference = reference; self.target = target; self.solve = solve; self.compensation = compensation; self.filmMode = filmMode; self.filmId = filmId }
    public func availableSolvers(astro: Bool) -> [Solve] { astro ? [.shutter, .iso] : (filmMode ? [.shutter, .aperture, .nd] : Solve.allCases) }
}
public struct AppSettings: Codable, Equatable, Sendable {
    public var exposure: FormState = FormState()
    public var astro: FormState = FormState()
    public var red = false
    public var dim = false
    public var brightness: Double = 0.15
    public var hideStars = false
    public var page = 0
    public var sound = true
    public var vibration = true
    public init() {}
}
public struct Calculation: Sendable {
    public let exact: Double
    public let common: Double?
    public let difference: Double?
    public let corrected: Double?
    public let film: Film?
    public let targetSeconds: Double
}
public struct ExposureError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
public func calculate(_ form: FormState, astro: Bool) throws -> Calculation {
    guard form.availableSolvers(astro: astro).contains(form.solve) else { throw ExposureError(astro ? "星空模式僅提供求快門或 ISO" : "底片模式不提供求 ISO") }
    func parse(_ input: Inputs, target: Bool) throws -> Exposure {
        let what: Solve? = target ? form.solve : nil
        let label = target ? "目標" : "參考"
        return try Exposure(aperture: what == .aperture ? 1 : ExposureMath.positive(input.aperture, name: "\(label)光圈"), seconds: what == .shutter ? 1 : ExposureMath.positive(input.shutter, name: "\(label)快門"), iso: what == .iso ? 1 : ExposureMath.positive(input.iso, name: "\(label) ISO"), nd: astro || what == .nd ? 0 : ExposureMath.nd(input.nd, unit: input.unit))
    }
    let reference = try parse(form.reference, target: false)
    let target = try parse(form.target, target: true)
    let exact = try ExposureMath.solve(reference: reference, target: target, what: form.solve, compensation: ExposureMath.compensation(form.compensation))
    let common = ExposureMath.common(exact, what: form.solve)
    let film = form.filmMode && !astro ? Films.find(form.filmId) : nil
    let corrected = try film.flatMap { form.solve == .shutter ? try Films.corrected(exact, film: $0) : nil }
    return Calculation(exact: exact, common: common, difference: common.map { ExposureMath.roundingStops(exact: exact, common: $0, what: form.solve) }, corrected: corrected, film: film, targetSeconds: form.solve == .shutter ? exact : target.seconds)
}
