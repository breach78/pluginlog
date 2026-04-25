import Foundation

extension AppState {
  @discardableResult
  func installObsidianHelperPluginForCurrentVault() -> ObsidianHelperPluginInstallResult? {
    guard let obsidianVaultRootURL else {
      obsidianHelperPluginInstallStatus = "Obsidian vault가 설정되지 않았습니다."
      return nil
    }

    do {
      let result = try ObsidianHelperPluginInstaller.installBundled(
        toVaultRootURL: obsidianVaultRootURL
      )
      obsidianHelperPluginInstallStatus =
        "Helper 설치됨: \(result.targetURL.path)"
      return result
    } catch {
      obsidianHelperPluginInstallStatus =
        "Helper 설치 실패: \(error.localizedDescription)"
      return nil
    }
  }
}
