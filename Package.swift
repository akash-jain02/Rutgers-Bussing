// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "DepartureCore", platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v13)], products: [.library(name: "DepartureCore", targets: ["DepartureCore"])], targets: [.target(name: "DepartureCore"), .testTarget(name: "DepartureCoreTests", dependencies: ["DepartureCore"])])
