import Foundation

extension Foundation.Bundle {
    static let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("pluginlog-harness_BrainUnfogHarness.bundle").path
        let buildPath = "/Users/three/app_build/logseq plugin/.build/arm64-apple-macosx/debug/pluginlog-harness_BrainUnfogHarness.bundle"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}