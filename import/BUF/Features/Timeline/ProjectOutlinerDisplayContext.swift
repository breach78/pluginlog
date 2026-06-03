import Foundation

struct ProjectOutlinerVisibleBlock: Identifiable {
  let id: UUID
  let block: ProjectOutlineBlock
  let displayDepth: Int
  let hasVisibleChildren: Bool
}

struct ProjectOutlinerDisplayContext {
  let blocks: [ProjectOutlinerVisibleBlock]
  let visibleIDs: [UUID]
  let visibleDepthsByID: [UUID: Int]
  let selectedIDs: Set<UUID>

  init(
    document: ProjectOutlineDocument,
    focusRootID: UUID?,
    hiddenTaskIDs: Set<UUID>,
    selection: ProjectOutlineBlockSelection?
  ) {
    let visibleIndices = ProjectOutlineVisibilityPolicy.visibleIndices(
      in: document,
      focusRootID: focusRootID,
      hiddenTaskIDs: hiddenTaskIDs
    )
    let rootDepth = focusRootID
      .flatMap { id in document.blocks.first(where: { $0.id == id })?.depth }
      ?? 0
    var visibleBlocks: [ProjectOutlinerVisibleBlock] = []
    visibleBlocks.reserveCapacity(visibleIndices.count)

    for position in visibleIndices.indices {
      let index = visibleIndices[position]
      let block = document.blocks[index]
      let hasVisibleChildren = ProjectOutlineVisibilityPolicy.hasVisibleChildren(
        blockID: block.id,
        in: document,
        hiddenTaskIDs: hiddenTaskIDs
      )
      let displayDepth = focusRootID == nil ? block.depth : max(0, block.depth - rootDepth)
      visibleBlocks.append(
        ProjectOutlinerVisibleBlock(
          id: block.id,
          block: block,
          displayDepth: displayDepth,
          hasVisibleChildren: hasVisibleChildren
        )
      )
    }

    let visibleIDs = visibleBlocks.map(\.id)
    let visibleDepthsByID = Dictionary(
      uniqueKeysWithValues: visibleBlocks.map { ($0.id, $0.block.depth) }
    )
    self.blocks = visibleBlocks
    self.visibleIDs = visibleIDs
    self.visibleDepthsByID = visibleDepthsByID
    self.selectedIDs = selection.map {
      Set($0.selectedIDs(in: visibleIDs, depths: visibleDepthsByID))
    } ?? []
  }
}
