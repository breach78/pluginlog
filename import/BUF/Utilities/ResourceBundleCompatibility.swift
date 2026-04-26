#if XCODE_PROJECT_BUILD
import Foundation

extension Bundle {
  static var module: Bundle { .main }
}
#endif
