// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "smoovmux-core",
	platforms: [
		.macOS(.v15),
	],
	products: [
		.library(name: "TmuxCC", targets: ["TmuxCC"]),
		.library(name: "SessionCore", targets: ["SessionCore"]),
		.library(name: "SmoovLog", targets: ["SmoovLog"]),
	],
	targets: [
		.target(name: "SmoovLog", path: "Sources/SmoovLog"),
		.target(name: "SessionCore", dependencies: ["SmoovLog"], path: "Sources/SessionCore"),
		.target(name: "TmuxCC", path: "Sources/TmuxCC"),
		.testTarget(name: "TmuxCCTests", dependencies: ["TmuxCC"], path: "Tests/TmuxCCTests"),
	]
)
