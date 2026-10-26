// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ExposureCore", platforms: [.iOS(.v16), .macOS(.v13)], products: [.library(name: "ExposureCore", targets: ["ExposureCore"])], targets: [.target(name: "ExposureCore"), .testTarget(name: "ExposureCoreTests", dependencies: ["ExposureCore"])])
