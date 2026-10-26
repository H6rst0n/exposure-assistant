import XCTest
@testable import ExposureCore

final class ExposureCoreTests: XCTestCase {
    let reference = Exposure(aperture: 2, seconds: 2, iso: 6400)
    func testSpecifiedExposureAndND() throws {
        XCTAssertEqual(try ExposureMath.solve(reference: reference, target: Exposure(aperture: 2, seconds: 1, iso: 400), what: .shutter, compensation: 0), 32, accuracy: 1e-10)
        XCTAssertEqual(try ExposureMath.solve(reference: reference, target: Exposure(aperture: 2, seconds: 1, iso: 400, nd: 3), what: .shutter, compensation: 0), 256, accuracy: 1e-10)
    }
    func testCompensationAndReferenceFilter() throws {
        let target = Exposure(aperture: 2, seconds: 1, iso: 400)
        XCTAssertEqual(try ExposureMath.solve(reference: reference, target: target, what: .shutter, compensation: 1), 64, accuracy: 1e-10)
        XCTAssertEqual(try ExposureMath.solve(reference: reference, target: target, what: .shutter, compensation: -1), 16, accuracy: 1e-10)
        var filtered = reference; filtered.nd = 2
        XCTAssertEqual(try ExposureMath.solve(reference: filtered, target: target, what: .shutter, compensation: 0), 8, accuracy: 1e-10)
    }
    func testAllSolversRandomRoundTrips() throws {
        var seed: UInt64 = 371
        func random(_ low: Double, _ high: Double) -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return low + Double(seed >> 11) / Double(UInt64(1) << 53) * (high - low)
        }
        for _ in 0..<1000 {
            let r = Exposure(aperture: pow(2, random(0, 5)), seconds: pow(2, random(-10, 10)), iso: pow(2, random(5, 15)), nd: random(0, 10))
            let t = Exposure(aperture: pow(2, random(0, 5)), seconds: pow(2, random(-10, 10)), iso: pow(2, random(5, 15)), nd: random(0, 10))
            let c = random(-3, 3)
            for what in Solve.allCases {
                let result = try ExposureMath.solve(reference: r, target: t, what: what, compensation: c)
                var solved = t
                switch what { case .shutter: solved.seconds = result; case .aperture: solved.aperture = result; case .iso: solved.iso = result; case .nd: solved.nd = result }
                XCTAssertEqual(ExposureMath.level(solved), ExposureMath.level(r) + c, accuracy: 1e-10)
            }
        }
    }
    func testNegativeNDGuidance() throws {
        let nd = try ExposureMath.solve(reference: reference, target: Exposure(aperture: 2, seconds: 16, iso: 400), what: .nd, compensation: 0)
        XCTAssertEqual(nd, -1, accuracy: 1e-10)
        XCTAssertNil(ExposureMath.common(nd, what: .nd))
    }
    func testNDStackUnits() throws {
        XCTAssertEqual(try ExposureMath.nd("3 + 6", unit: .stops), 9, accuracy: 1e-10)
        XCTAssertEqual(try ExposureMath.nd("8 + 64", unit: .factor), 9, accuracy: 1e-10)
        XCTAssertEqual(try ExposureMath.nd("0.9 + 1.8", unit: .density), 2.7 / log10(2), accuracy: 1e-10)
        XCTAssertEqual(try ExposureMath.nd("1000", unit: .factor), log2(1000), accuracy: 1e-10)
        XCTAssertEqual(try ExposureMath.nd("1", unit: .factor), 0)
    }
    func testRejectsInvalidND() {
        for value in ["", "NaN", "Infinity", "3+", "+3", "-1", "101", "3+-2", "3++2"] { XCTAssertThrowsError(try ExposureMath.nd(value, unit: .stops), value) }
        XCTAssertThrowsError(try ExposureMath.nd("0", unit: .factor))
        XCTAssertThrowsError(try ExposureMath.nd("-0.1", unit: .density))
    }
    func testFractionInput() throws {
        XCTAssertEqual(try ExposureMath.positive("1/125", name: "快門"), 0.008, accuracy: 1e-12)
        XCTAssertEqual(try ExposureMath.positive(" 1 / 2 ", name: "快門"), 0.5, accuracy: 1e-12)
    }
    func testInvalidInput() {
        for text in ["", "0", "-1", "NaN", "Infinity", "1/0", "-1/-2", "1/2/3", "1e309", "/2", "1/", "1e-999"] { XCTAssertThrowsError(try ExposureMath.positive(text, name: "數值"), text) }
        for text in ["NaN", "101", "-101", "", "inf"] { XCTAssertThrowsError(try ExposureMath.compensation(text)) }
    }
    func testSolverRejectsOverflowAndInvalidParameters() {
        XCTAssertThrowsError(try ExposureMath.solve(reference: Exposure(aperture: 0, seconds: 1, iso: 100), target: reference, what: .shutter, compensation: 0))
        XCTAssertThrowsError(try ExposureMath.solve(reference: reference, target: reference, what: .shutter, compensation: .infinity))
        XCTAssertThrowsError(try ExposureMath.solve(reference: reference, target: reference, what: .shutter, compensation: 2000))
        XCTAssertThrowsError(try ExposureMath.solve(reference: reference, target: reference, what: .nd, compensation: 2000))
    }
    func testRoundingSignAndRange() throws {
        XCTAssertEqual(ExposureMath.roundingStops(exact: 1, common: 2, what: .shutter), 1)
        XCTAssertEqual(ExposureMath.roundingStops(exact: 100, common: 200, what: .iso), 1)
        XCTAssertEqual(ExposureMath.roundingStops(exact: 2, common: 4, what: .aperture), -2)
        XCTAssertEqual(ExposureMath.roundingStops(exact: 3, common: 4, what: .nd), -1)
        XCTAssertEqual(try XCTUnwrap(ExposureMath.common(1 / 127, what: .shutter)), 1 / 125, accuracy: 1e-10)
        XCTAssertEqual(ExposureMath.common(31.5, what: .shutter), 32)
        XCTAssertEqual(ExposureMath.common(2.5, what: .nd), 2) // Kotlin round uses ties to even.
        XCTAssertNil(ExposureMath.common(604801, what: .shutter))
        XCTAssertNil(ExposureMath.common(1, what: .iso))
        XCTAssertNil(ExposureMath.common(.nan, what: .nd))
    }
    func testFilmKnownExampleBoundaryAndOverflow() throws {
        let hp5 = try XCTUnwrap(Films.find("hp5"))
        XCTAssertEqual(try Films.corrected(10, film: hp5), 20.417379, accuracy: 1e-5)
        XCTAssertEqual(try Films.corrected(1, film: hp5), 1)
        XCTAssertEqual(try Films.corrected(0.5, film: hp5), 0.5)
        XCTAssertGreaterThan(try Films.corrected(1.001, film: hp5), 1.001)
        XCTAssertThrowsError(try Films.corrected(.greatestFiniteMagnitude, film: hp5))
        XCTAssertThrowsError(try Films.corrected(0, film: hp5))
    }
    func testManufacturerCoefficients() {
        XCTAssertEqual(Films.all.map(\.exponent), [1.43,1.33,1.26,1.41,1.33,1.26,1.31,1.31,1.25,1.26,1.30])
        XCTAssertNil(Films.find("unknown"))
    }
    func testFilmAfterNDExactlyOnce() throws {
        let form = FormState(reference: Inputs(aperture: "2", shutter: "10", iso: "400"), target: Inputs(aperture: "2", shutter: "", iso: "400", nd: "3"), filmMode: true)
        let c = try calculate(form, astro: false)
        XCTAssertEqual(c.exact, 80, accuracy: 1e-8)
        XCTAssertEqual(try XCTUnwrap(c.corrected), pow(80, 1.31), accuracy: 1e-8)
    }
    func testFilmUsesUnroundedTime() throws {
        let form = FormState(reference: Inputs(aperture: "2", shutter: "31.4", iso: "400"), target: Inputs(aperture: "2", iso: "400"), filmMode: true)
        let c = try calculate(form, astro: false)
        XCTAssertEqual(c.common, 31)
        XCTAssertEqual(try XCTUnwrap(c.corrected), pow(31.4, 1.31), accuracy: 1e-8)
    }
    func testUnknownFilmAndInverseNoCorrection() throws {
        var form = FormState(reference: Inputs(aperture: "2", shutter: "10", iso: "400"), target: Inputs(aperture: "2", shutter: "10", iso: "400"), filmMode: true, filmId: "unknown")
        XCTAssertNil(try calculate(form, astro: false).corrected)
        form.filmId = "hp5"; form.solve = .aperture
        XCTAssertNil(try calculate(form, astro: false).corrected)
        form.solve = .shutter
        XCTAssertNil(try calculate(form, astro: true).corrected)
    }
    func testModeRestrictions() {
        var form = FormState(); form.filmMode = true; form.solve = .iso
        XCTAssertThrowsError(try calculate(form, astro: false))
        form.solve = .nd
        XCTAssertThrowsError(try calculate(form, astro: true))
        XCTAssertEqual(form.availableSolvers(astro: false), [.shutter, .aperture, .nd])
        XCTAssertEqual(form.availableSolvers(astro: true), [.shutter, .iso])
    }
    func testMissingReferenceAndSolvedFieldIgnored() throws {
        XCTAssertThrowsError(try calculate(FormState(), astro: false))
        let form = FormState(reference: Inputs(aperture: "2", shutter: "2", iso: "6400"), target: Inputs(aperture: "2", shutter: "invalid", iso: "400"))
        XCTAssertEqual(try calculate(form, astro: false).exact, 32, accuracy: 1e-10)
    }
    func testAstroIgnoresHiddenND() throws {
        let form = FormState(reference: Inputs(aperture: "2", shutter: "2", iso: "6400", nd: "bad"), target: Inputs(aperture: "2", iso: "400", nd: "bad"), filmMode: true)
        XCTAssertEqual(try calculate(form, astro: true).exact, 32, accuracy: 1e-10)
        XCTAssertTrue(STAR_NOTICE.contains("500 ÷ 全片幅等效焦距"))
        XCTAssertTrue(STAR_NOTICE.contains("6.7 秒"))
    }
    func testActualApertureNotRoundedToSquareRoot() throws {
        let value = try ExposureMath.solve(reference: Exposure(aperture: 2, seconds: 1, iso: 100), target: Exposure(aperture: 2.8, seconds: 1, iso: 100), what: .shutter, compensation: 0)
        XCTAssertEqual(value, 1.96, accuracy: 1e-12)
    }
    func testFormatting() {
        XCTAssertEqual(durationLabel(3661), "01:01:01")
        XCTAssertEqual(durationLabel(-1), "00:00:00")
        XCTAssertEqual(secondsLabel(1 / 125), "1/125 秒")
        XCTAssertEqual(secondsLabel(32), "32 秒")
        XCTAssertEqual(number(2.8), "2.8")
    }
    func testCodableRoundTripAndIndependentForms() throws {
        var settings = AppSettings()
        settings.exposure.reference.aperture = "2.8"
        settings.astro.reference.aperture = "1.4"
        settings.red = true; settings.page = 1
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)), settings)
        XCTAssertNotEqual(settings.exposure, settings.astro)
    }
}
