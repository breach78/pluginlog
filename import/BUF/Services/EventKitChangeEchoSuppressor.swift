import Foundation

enum EventKitChangeEchoSuppressor {
  static func performAppAuthoredMutation<T>(_ mutation: () throws -> T) rethrows -> T {
    ReminderSourceChangeEchoSuppressor.markAppAuthoredMutation()
    do {
      let result = try mutation()
      ReminderSourceChangeEchoSuppressor.markAppAuthoredMutation()
      return result
    } catch {
      ReminderSourceChangeEchoSuppressor.markAppAuthoredMutation()
      throw error
    }
  }
}
