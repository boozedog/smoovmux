import Foundation

public enum ScreenDropIndicator: Equatable, Sendable {
  case before
  case end
}

public enum ScreenDropIndicatorTarget: Equatable, Sendable {
  case before(UUID)
  case end
}

public enum ScreenDropIndicatorPolicy {
  public static func rowTarget(
    draggedId: UUID?,
    rowId: UUID,
    locationY: Double,
    rowHeight: Double,
    orderedIds: [UUID]
  ) -> ScreenDropIndicatorTarget? {
    let destinationId: UUID?
    if locationY < rowHeight / 2 {
      destinationId = rowId
    } else if let rowIndex = orderedIds.firstIndex(of: rowId) {
      destinationId = orderedIds.dropFirst(rowIndex + 1).first
    } else {
      destinationId = nil
    }
    return updatedTarget(draggedId: draggedId, destinationId: destinationId, orderedIds: orderedIds)
  }

  public static func updatedTarget(draggedId: UUID?, destinationId: UUID?, orderedIds: [UUID])
    -> ScreenDropIndicatorTarget?
  {
    guard let draggedId else {
      return destinationId.map(ScreenDropIndicatorTarget.before) ?? .end
    }
    guard let sourceIndex = orderedIds.firstIndex(of: draggedId) else {
      return destinationId.map(ScreenDropIndicatorTarget.before) ?? .end
    }

    if destinationId == draggedId {
      return nil
    }
    if let destinationId, orderedIds.dropFirst(sourceIndex + 1).first == destinationId {
      return nil
    }
    if destinationId == nil && sourceIndex == orderedIds.count - 1 {
      return nil
    }
    return destinationId.map(ScreenDropIndicatorTarget.before) ?? .end
  }

  public static func indicator(isTargeted: Bool, destinationIsEnd: Bool) -> ScreenDropIndicator? {
    guard isTargeted else { return nil }
    return destinationIsEnd ? .end : .before
  }
}
