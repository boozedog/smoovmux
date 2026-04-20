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
		.library(name: "PaneRelay", targets: ["PaneRelay"]),
		.executable(name: "smoovmux-relay", targets: ["smoovmux-relay"]),
	],
	targets: [
		.target(name: "SmoovLog", path: "Sources/SmoovLog"),
		.target(
			name: "SessionCore",
			dependencies: ["SmoovLog", "TmuxCC"],
			path: "Sources/SessionCore"
		),
		.target(name: "TmuxCC", path: "Sources/TmuxCC"),
		.target(
			name: "PaneRelay",
			dependencies: ["SmoovLog"],
			path: "Sources/PaneRelay"
		),
		.executableTarget(
			name: "smoovmux-relay",
			path: "Sources/smoovmux-relay"
		),
		.testTarget(name: "TmuxCCTests", dependencies: ["TmuxCC"], path: "Tests/TmuxCCTests"),
		.testTarget(
			name: "SessionCoreTests",
			dependencies: ["SessionCore", "TmuxCC"],
			path: "Tests/SessionCoreTests",
			resources: [.copy("Fixtures")]
		),
		.testTarget(
			name: "PaneRelayTests",
			dependencies: ["PaneRelay"],
			path: "Tests/PaneRelayTests"
		),
	]
)
