import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WorkspaceSidebar
import WorkspaceTabs

struct WorkspaceTabSidebar: View {
  @ObservedObject var tabManager: WorkspaceTabManager
  @State private var commandKeyDown = false
  @State private var flagsMonitor: Any?
  @State private var draggedTabId: UUID?
  @State private var dropIndicatorTarget: ScreenDropIndicatorTarget?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Spacer()
        .frame(height: 54)

      HStack {
        Text("SCREENS")
          .font(AppFonts.monospaced(size: 11, weight: .semibold))
          .tracking(0.7)
          .foregroundStyle(.secondary)
        Spacer()
        Button {
          tabManager.showLauncher(action: .newTab)
        } label: {
          Image(systemName: "plus")
            .font(AppFonts.ui(size: 13, weight: .semibold))
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("New Screen")
        .accessibilityLabel("New Screen")
      }
      .padding(.horizontal, 10)
      .padding(.bottom, 8)

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(Array(tabManager.tabs.enumerated()), id: \.element.id) { index, tab in
            WorkspaceTabRow(
              tab: tab,
              shortcutIndex: index + 1,
              showShortcut: commandKeyDown,
              isSelected: tabManager.selectedTabId == tab.id,
              canClose: tabManager.tabs.count > 1,
              indicator: tabManager.terminalStatus(for: tab.id).indicator,
              select: { tabManager.selectTab(tab.id) },
              close: { tabManager.closeTab(tab.id) }
            )
            .padding(.bottom, 4)
            .overlay(alignment: .top) {
              if ScreenDropIndicatorPolicy.indicator(
                isTargeted: dropIndicatorTarget == ScreenDropIndicatorTarget.before(tab.id),
                destinationIsEnd: false
              ) == .before {
                ScreenDropIndicatorLine()
              }
            }
            .overlay {
              WorkspaceTabDragSourceView(
                tabId: tab.id,
                onClick: { tabManager.selectTab(tab.id) },
                onDragBegan: { draggedTabId = tab.id },
                onDragEnded: {
                  draggedTabId = nil
                  dropIndicatorTarget = nil
                },
                onDroppedOutside: { screenPoint in
                  draggedTabId = nil
                  dropIndicatorTarget = nil
                  _ = (NSApp.delegate as? AppDelegate)?.detachScreenToNewWindow(id: tab.id, at: screenPoint)
                }
              )
            }
            .onDrop(
              of: [.plainText, .text],
              delegate: WorkspaceTabDropDelegate(
                destinationTabId: tab.id,
                destinationRowId: tab.id,
                draggedTabId: $draggedTabId,
                dropIndicatorTarget: $dropIndicatorTarget,
                tabManager: tabManager
              )
            )
          }
          Color.clear
            .frame(height: 18)
            .overlay(alignment: .top) {
              if ScreenDropIndicatorPolicy.indicator(
                isTargeted: dropIndicatorTarget == ScreenDropIndicatorTarget.end,
                destinationIsEnd: true
              ) == .end {
                ScreenDropIndicatorLine()
              }
            }
            .onDrop(
              of: [.plainText, .text],
              delegate: WorkspaceTabDropDelegate(
                destinationTabId: nil,
                destinationRowId: nil,
                draggedTabId: $draggedTabId,
                dropIndicatorTarget: $dropIndicatorTarget,
                tabManager: tabManager
              )
            )
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
      }

      Spacer(minLength: 0)

      Button {
        NSApp.sendAction(
          #selector(AppDelegate.showSettingsWindow(_:)),
          to: NSApp.delegate,
          from: nil
        )
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "gearshape")
            .font(AppFonts.ui(size: 12, weight: .medium))
          Text("Settings")
            .font(AppFonts.monospaced(size: 13, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(.primary.opacity(0.9))
      .help("Settings")
      .accessibilityLabel("Settings")
      .padding(.bottom, 10)
    }
    .background(AppChromeColors.sidebarBackground)
    .onDrop(
      of: [.plainText, .text],
      delegate: WorkspaceTabDropDelegate(
        destinationTabId: nil,
        destinationRowId: nil,
        draggedTabId: $draggedTabId,
        dropIndicatorTarget: $dropIndicatorTarget,
        tabManager: tabManager,
        acceptsLocalDrops: false,
        showsIndicator: false
      )
    )
    .onReceive(NotificationCenter.default.publisher(for: .workspaceTabDragEnded)) { _ in
      draggedTabId = nil
      dropIndicatorTarget = nil
    }
    .onAppear {
      flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
        commandKeyDown = event.modifierFlags.contains(.command)
        return event
      }
    }
    .onDisappear {
      if let flagsMonitor {
        NSEvent.removeMonitor(flagsMonitor)
      }
      flagsMonitor = nil
    }
  }
}

struct WorkspaceTabRow: View {
  let tab: WorkspaceTabRecord
  let shortcutIndex: Int
  let showShortcut: Bool
  let isSelected: Bool
  let canClose: Bool
  let indicator: TerminalScreenIndicator?
  let select: () -> Void
  let close: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: select) {
      HStack(spacing: 8) {
        Text("\(shortcutIndex)")
          .font(AppFonts.monospaced(size: 12, weight: .medium))
          .foregroundStyle(isSelected ? .primary : .secondary)
          .frame(width: 14, alignment: .leading)

        Text(tab.title)
          .font(AppFonts.monospaced(size: 13, weight: .semibold))
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)

        if showShortcut {
          Text("⌘\(shortcutIndex)")
            .font(AppFonts.monospaced(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
        } else if hovering, canClose {
          Button(action: close) {
            Image(systemName: "xmark")
              .font(AppFonts.ui(size: 11, weight: .semibold))
              .frame(width: 16, height: 16)
          }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
          .help("Close Tab")
          .accessibilityLabel("Close \(tab.title)")
        } else if let indicator {
          TerminalScreenIndicatorView(indicator: indicator)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 7)
      .contentShape(Rectangle())
      .background {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(isSelected ? Color.white.opacity(0.06) : Color.clear)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .stroke(isSelected ? Color(nsColor: .systemBlue).opacity(0.85) : Color.clear, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(tab.title)
    .onHover { hovering in
      self.hovering = hovering
    }
    .contextMenu {
      if canClose {
        Button("Close Tab", action: close)
      }
    }
  }
}

extension Notification.Name {
  fileprivate static let workspaceTabDragEnded = Notification.Name("workspaceTabDragEnded")
  fileprivate static let workspaceTabDragAccepted = Notification.Name("workspaceTabDragAccepted")
}

private struct ScreenDropIndicatorLine: View {
  var body: some View {
    Capsule()
      .fill(Color(nsColor: .systemBlue))
      .frame(height: 2)
      .shadow(color: Color(nsColor: .systemBlue).opacity(0.8), radius: 3)
      .allowsHitTesting(false)
  }
}

private struct WorkspaceTabDragSourceView: NSViewRepresentable {
  let tabId: UUID
  let onClick: () -> Void
  let onDragBegan: () -> Void
  let onDragEnded: () -> Void
  let onDroppedOutside: (NSPoint) -> Void

  func makeNSView(context: Context) -> DragSourceNSView {
    let view = DragSourceNSView()
    view.tabId = tabId
    view.onClick = onClick
    view.onDragBegan = onDragBegan
    view.onDragEnded = onDragEnded
    view.onDroppedOutside = onDroppedOutside
    return view
  }

  func updateNSView(_ nsView: DragSourceNSView, context: Context) {
    nsView.tabId = tabId
    nsView.onClick = onClick
    nsView.onDragBegan = onDragBegan
    nsView.onDragEnded = onDragEnded
    nsView.onDroppedOutside = onDroppedOutside
  }
}

@MainActor
private final class DragSourceNSView: NSView, NSDraggingSource {
  var tabId: UUID?
  var onClick: (() -> Void)?
  var onDragBegan: (() -> Void)?
  var onDragEnded: (() -> Void)?
  var onDroppedOutside: ((NSPoint) -> Void)?
  private var mouseDownEvent: NSEvent?
  private var dragWasAccepted = false
  private var dragAcceptedObserver: NSObjectProtocol?

  override func mouseDown(with event: NSEvent) {
    mouseDownEvent = event
    super.mouseDown(with: event)
  }

  override func mouseUp(with event: NSEvent) {
    if mouseDownEvent != nil {
      onClick?()
    }
    mouseDownEvent = nil
  }

  override func mouseDragged(with event: NSEvent) {
    guard let tabId, let mouseDownEvent else { return }
    dragWasAccepted = false
    dragAcceptedObserver = NotificationCenter.default.addObserver(
      forName: .workspaceTabDragAccepted,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let self,
        let acceptedId = notification.object as? UUID,
        acceptedId == tabId
      else { return }
      self.dragWasAccepted = true
    }
    onDragBegan?()

    let pasteboardItem = NSPasteboardItem()
    pasteboardItem.setString(tabId.uuidString, forType: .string)
    let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
    draggingItem.setDraggingFrame(bounds, contents: draggingImage())
    beginDraggingSession(with: [draggingItem], event: mouseDownEvent, source: self)
    self.mouseDownEvent = nil
  }

  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    .move
  }

  func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    if let dragAcceptedObserver {
      NotificationCenter.default.removeObserver(dragAcceptedObserver)
      self.dragAcceptedObserver = nil
    }
    onDragEnded?()
    NotificationCenter.default.post(name: .workspaceTabDragEnded, object: nil)
    if operation == [] && !dragWasAccepted {
      onDroppedOutside?(screenPoint)
    }
    dragWasAccepted = false
  }

  private func draggingImage() -> NSImage {
    let image = NSImage(size: bounds.size)
    image.lockFocus()
    NSColor.white.withAlphaComponent(0.12).setFill()
    NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
    image.unlockFocus()
    return image
  }
}

private struct WorkspaceTabDropDelegate: DropDelegate {
  private static let rowDropHeight = 36.0

  let destinationTabId: UUID?
  let destinationRowId: UUID?
  @Binding var draggedTabId: UUID?
  @Binding var dropIndicatorTarget: ScreenDropIndicatorTarget?
  let tabManager: WorkspaceTabManager
  var acceptsLocalDrops = true
  var showsIndicator = true

  func dropEntered(info: DropInfo) {
    if showsIndicator {
      updateDropTarget(info: info)
    }
  }

  func dropExited(info: DropInfo) {
    let target = currentTarget(info: info)
    if dropIndicatorTarget == target {
      dropIndicatorTarget = nil
    }
  }

  private func currentDestinationId(info: DropInfo) -> UUID? {
    guard let destinationRowId else { return destinationTabId }
    let target = ScreenDropIndicatorPolicy.rowTarget(
      draggedId: draggedTabId,
      rowId: destinationRowId,
      locationY: info.location.y,
      rowHeight: Self.rowDropHeight,
      orderedIds: tabManager.tabs.map(\.id)
    )
    switch target {
    case .before(let id):
      return id
    case .end, nil:
      return nil
    }
  }

  private func currentTarget(info: DropInfo) -> ScreenDropIndicatorTarget? {
    if let destinationRowId {
      return ScreenDropIndicatorPolicy.rowTarget(
        draggedId: draggedTabId,
        rowId: destinationRowId,
        locationY: info.location.y,
        rowHeight: Self.rowDropHeight,
        orderedIds: tabManager.tabs.map(\.id)
      )
    }
    return ScreenDropIndicatorPolicy.updatedTarget(
      draggedId: draggedTabId,
      destinationId: destinationTabId,
      orderedIds: tabManager.tabs.map(\.id)
    )
  }

  private func updateDropTarget(info: DropInfo) {
    dropIndicatorTarget = currentTarget(info: info)
  }

  private func move(_ id: UUID, destinationId: UUID?) -> Bool {
    if tabManager.containsTab(id) {
      tabManager.moveTab(id, before: destinationId)
      return true
    }

    return (NSApp.delegate as? AppDelegate)?.moveScreen(
      id: id,
      to: tabManager,
      before: destinationId
    ) ?? false
  }

  func performDrop(info: DropInfo) -> Bool {
    if let draggedTabId {
      guard acceptsLocalDrops else { return false }
      self.draggedTabId = nil
      let destinationId = currentDestinationId(info: info)
      dropIndicatorTarget = nil
      NotificationCenter.default.post(name: .workspaceTabDragAccepted, object: draggedTabId)
      return move(draggedTabId, destinationId: destinationId)
    }

    guard let provider = info.itemProviders(for: [.plainText, .text]).first else { return false }
    let typeIdentifier =
      provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
      ? UTType.plainText.identifier
      : UTType.text.identifier
    let destinationId = currentDestinationId(info: info)
    dropIndicatorTarget = nil
    provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
      let rawValue: String?
      if let data = item as? Data {
        rawValue = String(data: data, encoding: .utf8)
      } else if let string = item as? String {
        rawValue = string
      } else if let string = item as? NSString {
        rawValue = string as String
      } else {
        rawValue = nil
      }

      guard let rawValue, let id = UUID(uuidString: rawValue) else { return }
      Task { @MainActor in
        NotificationCenter.default.post(name: .workspaceTabDragAccepted, object: id)
        _ = move(id, destinationId: destinationId)
        dropIndicatorTarget = nil
        Task { @MainActor in
          dropIndicatorTarget = nil
        }
      }
    }
    return true
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    if showsIndicator {
      updateDropTarget(info: info)
    }
    return DropProposal(operation: .move)
  }
}

struct TerminalScreenIndicatorView: View {
  let indicator: TerminalScreenIndicator

  var body: some View {
    indicatorContent
      .help(indicator.accessibilityLabel)
      .accessibilityLabel(indicator.accessibilityLabel)
  }

  @ViewBuilder
  private var indicatorContent: some View {
    switch indicator {
    case .bell(let count):
      HStack(spacing: 3) {
        Image(systemName: "bell.fill")
        if count > 1 {
          Text("\(count)")
            .font(AppFonts.monospaced(size: 10, weight: .semibold))
        }
      }
      .font(AppFonts.ui(size: 12, weight: .semibold))
      .foregroundStyle(Color(nsColor: .systemYellow))
    case .progress(let percent):
      Text("\(percent)%")
        .font(AppFonts.monospaced(size: 10, weight: .semibold))
        .foregroundStyle(Color(nsColor: .systemYellow))
    case .commandFinished(let exitCode):
      Image(systemName: exitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
        .foregroundStyle(exitCode == 0 ? .secondary : Color(nsColor: .systemRed))
    case .childExited:
      Image(systemName: "stop.circle.fill")
        .foregroundStyle(Color(nsColor: .systemOrange))
    case .rendererUnhealthy:
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(Color(nsColor: .systemRed))
    }
  }
}
