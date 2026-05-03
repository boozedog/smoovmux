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
		.library(name: "WorkspacePanes", targets: ["WorkspacePanes"]),
		.library(name: "WorkspaceState", targets: ["WorkspaceState"]),
		.library(name: "WorkspaceSidebar", targets: ["WorkspaceSidebar"]),
		.library(name: "PaneLauncher", targets: ["PaneLauncher"]),
	],
	targets: [
		.target(name: "SmoovLog", path: "Sources/SmoovLog"),
		.target(name: "SmoovAppCommands", path: "Sources/SmoovAppCommands"),
		.target(name: "WorkspaceTabs", path: "Sources/WorkspaceTabs"),
		.target(name: "WorkspacePanes", path: "Sources/WorkspacePanes"),
		.target(name: "WorkspaceSidebar", path: "Sources/WorkspaceSidebar"),
		.target(
			name: "WorkspaceState",
			dependencies: ["WorkspaceTabs", "WorkspacePanes", "WorkspaceSidebar"],
			path: "Sources/WorkspaceState"
		),
		.target(name: "PaneLauncher", path: "Sources/PaneLauncher"),
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
		.testTarget(
			name: "WorkspacePanesTests",
			dependencies: ["WorkspacePanes"],
			path: "Tests/WorkspacePanesTests"
		),
		.testTarget(
			name: "SmoovLogTests",
			dependencies: ["SmoovLog"],
			path: "Tests/SmoovLogTests"
		),
		.testTarget(
			name: "WorkspaceStateTests",
			dependencies: ["WorkspaceState", "WorkspaceSidebar"],
			path: "Tests/WorkspaceStateTests"
		),
		.testTarget(
			name: "WorkspaceSidebarTests",
			dependencies: ["WorkspaceSidebar"],
			path: "Tests/WorkspaceSidebarTests"
		),
		.testTarget(
			name: "PaneLauncherTests",
			dependencies: ["PaneLauncher"],
			path: "Tests/PaneLauncherTests"
		),
	]
)
