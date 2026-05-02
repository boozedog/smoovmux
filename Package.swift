// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "smoovmux-core",
	platforms: [
		.macOS(.v15),
	],
	products: [
		.library(name: "SessionCore", targets: ["SessionCore"]),
		.library(name: "SmoovLog", targets: ["SmoovLog"]),
	],
	targets: [
		.target(name: "SmoovLog", path: "Sources/SmoovLog"),
		.target(
			name: "SessionCore",
			dependencies: ["SmoovLog"],
			path: "Sources/SessionCore"
		),
		.testTarget(
			name: "SessionCoreTests",
			dependencies: ["SessionCore"],
			path: "Tests/SessionCoreTests"
		),
	]
)
