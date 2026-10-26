// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "TimerSupport", platforms: [.iOS(.v16), .macOS(.v13)], products: [.library(name: "TimerSupport", targets: ["TimerSupport"])], targets: [.target(name: "TimerSupport"), .testTarget(name: "TimerSupportTests", dependencies: ["TimerSupport"])])
