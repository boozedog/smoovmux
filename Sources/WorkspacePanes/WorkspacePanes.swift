import Foundation

public enum WorkspacePaneSplitDirection: String, Equatable, Sendable {
  case right
  case down
}

public struct WorkspacePaneLeaf: Equatable, Identifiable, Sendable {
  public let id: UUID

  public init(id: UUID = UUID()) {
    self.id = id
  }
}

public struct WorkspacePaneSplit: Equatable, Identifiable, Sendable {
  public let id: UUID
  public var direction: WorkspacePaneSplitDirection
  public var first: WorkspacePaneNode
  public var second: WorkspacePaneNode

  public init(
    id: UUID = UUID(),
    direction: WorkspacePaneSplitDirection,
    first: WorkspacePaneNode,
    second: WorkspacePaneNode
  ) {
    self.id = id
    self.direction = direction
    self.first = first
    self.second = second
  }
}

public indirect enum WorkspacePaneNode: Equatable, Sendable {
  case leaf(WorkspacePaneLeaf)
  case split(WorkspacePaneSplit)

  public var id: UUID {
    switch self {
    case .leaf(let leaf):
      return leaf.id
    case .split(let split):
      return split.id
    }
  }
}

public struct WorkspacePaneTree: Equatable, Sendable {
  public private(set) var root: WorkspacePaneNode
  public private(set) var selectedPaneId: UUID

  public init(root: WorkspacePaneNode? = nil, selectedPaneId: UUID? = nil) {
    let root = root ?? .leaf(WorkspacePaneLeaf())
    self.root = root
    self.selectedPaneId = selectedPaneId.flatMap { root.containsLeaf(id: $0) ? $0 : nil } ?? root.firstLeafId
  }

  public var leaves: [WorkspacePaneLeaf] {
    root.leaves
  }

  @discardableResult
  public mutating func selectPane(_ id: UUID) -> Bool {
    guard root.containsLeaf(id: id) else { return false }
    selectedPaneId = id
    return true
  }

  @discardableResult
  public mutating func splitSelectedPane(
    direction: WorkspacePaneSplitDirection,
    newPaneId: UUID = UUID(),
    splitId: UUID = UUID()
  ) -> UUID? {
    splitPane(selectedPaneId, direction: direction, newPaneId: newPaneId, splitId: splitId)
  }

  @discardableResult
  public mutating func splitPane(
    _ paneId: UUID,
    direction: WorkspacePaneSplitDirection,
    newPaneId: UUID = UUID(),
    splitId: UUID = UUID()
  ) -> UUID? {
    guard
      let next = root.replacingLeaf(
        id: paneId,
        with: { leaf in
          .split(
            WorkspacePaneSplit(
              id: splitId,
              direction: direction,
              first: .leaf(leaf),
              second: .leaf(WorkspacePaneLeaf(id: newPaneId))
            )
          )
        })
    else {
      return nil
    }

    root = next
    selectedPaneId = newPaneId
    return newPaneId
  }

  @discardableResult
  public mutating func closeSelectedPane() -> Bool {
    closePane(selectedPaneId)
  }

  @discardableResult
  public mutating func closePane(_ paneId: UUID) -> Bool {
    guard case .split = root, let result = root.removingLeaf(id: paneId) else { return false }
    root = result.root
    selectedPaneId = result.promoted.firstLeafId
    return true
  }
}

extension WorkspacePaneNode {
  fileprivate var firstLeafId: UUID {
    switch self {
    case .leaf(let leaf):
      return leaf.id
    case .split(let split):
      return split.first.firstLeafId
    }
  }

  fileprivate var leaves: [WorkspacePaneLeaf] {
    switch self {
    case .leaf(let leaf):
      return [leaf]
    case .split(let split):
      return split.first.leaves + split.second.leaves
    }
  }

  fileprivate func containsLeaf(id: UUID) -> Bool {
    switch self {
    case .leaf(let leaf):
      return leaf.id == id
    case .split(let split):
      return split.first.containsLeaf(id: id) || split.second.containsLeaf(id: id)
    }
  }

  fileprivate func replacingLeaf(
    id: UUID,
    with replace: (WorkspacePaneLeaf) -> WorkspacePaneNode
  ) -> WorkspacePaneNode? {
    switch self {
    case .leaf(let leaf):
      return leaf.id == id ? replace(leaf) : nil
    case .split(var split):
      if let first = split.first.replacingLeaf(id: id, with: replace) {
        split.first = first
        return .split(split)
      }
      if let second = split.second.replacingLeaf(id: id, with: replace) {
        split.second = second
        return .split(split)
      }
      return nil
    }
  }

  fileprivate func removingLeaf(id: UUID) -> (root: WorkspacePaneNode, promoted: WorkspacePaneNode)? {
    switch self {
    case .leaf:
      return nil
    case .split(var split):
      if case .leaf(let leaf) = split.first, leaf.id == id {
        return (split.second, split.second)
      }
      if case .leaf(let leaf) = split.second, leaf.id == id {
        return (split.first, split.first)
      }
      if let removal = split.first.removingLeaf(id: id) {
        split.first = removal.root
        return (.split(split), removal.promoted)
      }
      if let removal = split.second.removingLeaf(id: id) {
        split.second = removal.root
        return (.split(split), removal.promoted)
      }
      return nil
    }
  }
}
