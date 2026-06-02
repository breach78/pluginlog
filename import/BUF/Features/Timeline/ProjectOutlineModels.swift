import Foundation

struct ProjectOutlineDocument: Equatable {
  var blocks: [ProjectOutlineBlock]

  init(blocks: [ProjectOutlineBlock] = []) {
    self.blocks = blocks
  }
}

struct ProjectOutlineBlock: Identifiable, Equatable {
  let id: UUID
  var depth: Int
  var text: String
  var taskBinding: ProjectOutlineTaskBinding?
  var childrenCollapsed: Bool
  var colorToken: ProjectOutlineBlockColor?

  init(
    id: UUID = UUID(),
    depth: Int,
    text: String,
    taskBinding: ProjectOutlineTaskBinding? = nil,
    childrenCollapsed: Bool = false,
    colorToken: ProjectOutlineBlockColor? = nil
  ) {
    self.id = id
    self.depth = max(0, depth)
    self.text = text
    self.taskBinding = taskBinding
    self.childrenCollapsed = childrenCollapsed
    self.colorToken = colorToken
  }

  var isTaskBlock: Bool {
    taskBinding != nil
  }
}

enum ProjectOutlineBlockColor: String, CaseIterable, Equatable {
  case mist
  case sage
  case moss
  case sand
  case clay
  case rose
  case dusk
  case slate
}

struct ProjectOutlineTaskBinding: Equatable {
  var taskID: UUID?
  var taskExternalIdentifier: String?
  var preservedAttributes: [String: String]

  init(
    taskID: UUID?,
    taskExternalIdentifier: String?,
    preservedAttributes: [String: String] = [:]
  ) {
    self.taskID = taskID
    self.taskExternalIdentifier = taskExternalIdentifier
    self.preservedAttributes = preservedAttributes
  }
}

struct ProjectOutlineInsertionResult: Equatable {
  let insertedBlockID: UUID?
  let focusedBlockID: UUID
}

struct ProjectOutlineBackspaceResult: Equatable {
  let focusedBlockID: UUID?
  let focusOffset: Int?
}

enum ProjectOutlineDropPlacement: Equatable {
  case before
  case after
  case child
}

struct ProjectOutlineDropIndicator: Equatable {
  let targetID: UUID
  let placement: ProjectOutlineDropPlacement
}
