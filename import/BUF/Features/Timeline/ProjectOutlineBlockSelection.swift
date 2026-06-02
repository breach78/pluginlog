import Foundation

struct ProjectOutlineBlockSelection {
  let anchorID: UUID
  let headID: UUID

  func selectedIDs(in visibleIDs: [UUID], depths: [UUID: Int]) -> [UUID] {
    guard let anchorIndex = visibleIDs.firstIndex(of: anchorID),
      let headIndex = visibleIDs.firstIndex(of: headID)
    else {
      return []
    }
    let bounds = min(anchorIndex, headIndex)...max(anchorIndex, headIndex)
    let baseIDs = Array(visibleIDs[bounds])
    let expanded = Set(baseIDs.flatMap { subtreeVisibleIDs(for: $0, in: visibleIDs, depths: depths) })
    return visibleIDs.filter { expanded.contains($0) }
  }

  func adjacentID(afterSelectionBy offset: Int, in visibleIDs: [UUID], depths: [UUID: Int]) -> UUID? {
    let ids = selectedIDs(in: visibleIDs, depths: depths)
    guard let first = ids.first,
      let last = ids.last,
      let firstIndex = visibleIDs.firstIndex(of: first),
      let lastIndex = visibleIDs.firstIndex(of: last)
    else {
      return nil
    }
    let targetIndex = offset < 0 ? firstIndex - 1 : lastIndex + 1
    guard visibleIDs.indices.contains(targetIndex) else {
      return offset < 0 ? first : last
    }
    return visibleIDs[targetIndex]
  }

  private func subtreeVisibleIDs(
    for blockID: UUID,
    in visibleIDs: [UUID],
    depths: [UUID: Int]
  ) -> [UUID] {
    guard let rootIndex = visibleIDs.firstIndex(of: blockID),
      let rootDepth = depths[blockID]
    else {
      return []
    }
    var result = [blockID]
    var index = rootIndex + 1
    while visibleIDs.indices.contains(index) {
      let id = visibleIDs[index]
      guard let depth = depths[id], depth > rootDepth else { break }
      result.append(id)
      index += 1
    }
    return result
  }
}
