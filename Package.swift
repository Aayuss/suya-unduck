// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "suya-unduck", platforms: [.macOS(.v14)], products: [
.executable(name: "suya-unduck", targets: ["SuyaUnduck"]),
.executable(name: "suya-unduck-lab", targets: ["SuyaUnduckLab"]),
.executable(name: "suya-unduck-selftest", targets: ["SuyaUnduckSelfTest"])], targets: [
.target(name: "CAtomics"), .target(name: "MixerCore", dependencies: ["CAtomics"]),
.target(name: "MixerEngine", dependencies: ["MixerCore", "CAtomics"], linkerSettings: [.linkedFramework("CoreAudio"), .linkedFramework("AudioToolbox"), .linkedFramework("AppKit")]),
.executableTarget(name: "SuyaUnduck", dependencies: ["MixerEngine", "MixerCore", "CAtomics"], linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ServiceManagement")]),
.executableTarget(name: "SuyaUnduckLab", dependencies: ["MixerEngine", "MixerCore", "CAtomics"]),
.executableTarget(name: "SuyaUnduckSelfTest", dependencies: ["MixerCore", "MixerEngine", "CAtomics"])], swiftLanguageVersions: [.v5])
