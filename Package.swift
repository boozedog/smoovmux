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
		.library(name: "SmoovAppCommands", targets: ["SmoovAppCommands"]),
		.library(name: "WorkspaceTabs", targets: ["WorkspaceTabs"]),
	],
	targets: [
		.target(name: "SmoovLog", path: "Sources/SmoovLog"),
		.target(name: "SmoovAppCommands", path: "Sources/SmoovAppCommands"),
		.target(name: "WorkspaceTabs", path: "Sources/WorkspaceTabs"),
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
		.testTarget(
			name: "WorkspaceTabsTests",
			dependencies: ["WorkspaceTabs"],
			path: "Tests/WorkspaceTabsTests"
		),
		.testTarget(
			name: "SmoovAppCommandsTests",
			dependencies: ["SmoovAppCommands"],
			path: "Tests/SmoovAppCommandsTests"
		),
	]
)
