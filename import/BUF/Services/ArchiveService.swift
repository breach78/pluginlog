import Foundation

enum ArchiveReason: String {
  case remoteDeletion
  case userAction
}

@MainActor
protocol ArchiveService: AnyObject {}

@MainActor
final class DefaultArchiveService: ArchiveService {}
