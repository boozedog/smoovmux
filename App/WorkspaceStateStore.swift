import AppKit
import Foundation
import SmoovLog
import WorkspaceState

@MainActor
final class WorkspaceStateStore {
  private let url: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private let debouncer: WorkspaceStateSaveDebouncer

  init(fileManager: FileManager = .default, bundleIdentifier: String? = Bundle.main.bundleIdentifier) {
    let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let appDirectory = supportDirectory.appendingPathComponent(bundleIdentifier ?? "smoovmux", isDirectory: true)
    self.url = appDirectory.appendingPathComponent("workspace-state.json")
    let stateURL = self.url
    self.debouncer = WorkspaceStateSaveDebouncer(delay: .milliseconds(300)) { state in
      await Self.write(state, to: stateURL)
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    self.encoder = encoder
    self.decoder = JSONDecoder()

    do {
      try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
    } catch {
      SmoovLog.error("workspace state directory creation failed: \(error)")
    }
  }

  func load() -> WorkspaceState? {
    do {
      let data = try Data(contentsOf: url)
      return try decoder.decode(WorkspaceState.self, from: data)
    } catch CocoaError.fileReadNoSuchFile {
      return nil
    } catch {
      SmoovLog.error("workspace state load failed: \(error)")
      return nil
    }
  }

  func save(_ state: WorkspaceState) {
    Task {
      await debouncer.schedule(state)
    }
  }

  func saveImmediately(_ state: WorkspaceState) {
    do {
      let data = try encoder.encode(state)
      try data.write(to: url, options: [.atomic])
    } catch {
      SmoovLog.error("workspace state save failed: \(error)")
    }
  }

  private static func write(_ state: WorkspaceState, to url: URL) async {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(state)
      try data.write(to: url, options: [.atomic])
    } catch {
      SmoovLog.error("workspace state save failed: \(error)")
    }
  }
}

extension WorkspaceWindowFrame {
  init(_ rect: NSRect) {
    self.init(
      x: Double(rect.origin.x),
      y: Double(rect.origin.y),
      width: Double(rect.size.width),
      height: Double(rect.size.height)
    )
  }

  var rect: NSRect {
    NSRect(x: x, y: y, width: width, height: height)
  }
}
