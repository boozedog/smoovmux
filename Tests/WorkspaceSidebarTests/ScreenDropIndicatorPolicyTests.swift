import Foundation
import Testing

@testable import WorkspaceSidebar

@Suite("Screen drop indicator policy")
struct ScreenDropIndicatorPolicyTests {
  @Test("destination row shows before indicator")
  func destinationRowShowsBeforeIndicator() {
    #expect(ScreenDropIndicatorPolicy.indicator(isTargeted: true, destinationIsEnd: false) == .before)
  }

  @Test("end target shows end indicator")
  func endTargetShowsEndIndicator() {
    #expect(ScreenDropIndicatorPolicy.indicator(isTargeted: true, destinationIsEnd: true) == .end)
  }

  @Test("drop target updates only when drop changes order")
  func dropTargetUpdatesOnlyWhenDropChangesOrder() {
    let first = UUID()
    let second = UUID()
    let third = UUID()
    let order = [first, second, third]

    #expect(
      ScreenDropIndicatorPolicy.updatedTarget(draggedId: third, destinationId: first, orderedIds: order)
        == .before(first))
    #expect(ScreenDropIndicatorPolicy.updatedTarget(draggedId: first, destinationId: first, orderedIds: order) == nil)
    #expect(ScreenDropIndicatorPolicy.updatedTarget(draggedId: first, destinationId: second, orderedIds: order) == nil)
    #expect(ScreenDropIndicatorPolicy.updatedTarget(draggedId: first, destinationId: nil, orderedIds: order) == .end)
    #expect(ScreenDropIndicatorPolicy.updatedTarget(draggedId: third, destinationId: nil, orderedIds: order) == nil)
    #expect(
      ScreenDropIndicatorPolicy.updatedTarget(draggedId: first, destinationId: third, orderedIds: order)
        == .before(third))
  }

  @Test("row half chooses before or after row")
  func rowHalfChoosesBeforeOrAfterRow() {
    let first = UUID()
    let second = UUID()
    let third = UUID()
    let order = [first, second, third]

    #expect(
      ScreenDropIndicatorPolicy.rowTarget(
        draggedId: first,
        rowId: second,
        locationY: 8,
        rowHeight: 32,
        orderedIds: order
      ) == nil)
    #expect(
      ScreenDropIndicatorPolicy.rowTarget(
        draggedId: first,
        rowId: second,
        locationY: 24,
        rowHeight: 32,
        orderedIds: order
      ) == .before(third))
    #expect(
      ScreenDropIndicatorPolicy.rowTarget(
        draggedId: first,
        rowId: third,
        locationY: 24,
        rowHeight: 32,
        orderedIds: order
      ) == .end)
  }

  @Test("external drop target always updates")
  func externalDropTargetAlwaysUpdates() {
    let destination = UUID()
    let existing = UUID()

    #expect(
      ScreenDropIndicatorPolicy.updatedTarget(draggedId: UUID(), destinationId: destination, orderedIds: [existing])
        == .before(destination))
  }

  @Test("untargeted drop location shows no indicator")
  func untargetedDropLocationShowsNoIndicator() {
    #expect(ScreenDropIndicatorPolicy.indicator(isTargeted: false, destinationIsEnd: false) == nil)
  }
}
