# suya-unduck

A native Apple Silicon macOS menu bar audio mixer. Uses your neon app icon and white transparent menu bar icon. Requires macOS 14.2 or later.

- Independent 0–200% app volume, mute, favorites, and output routing.
- Call and microphone-using apps stay protected from processing.
- System output/input selection with confirmation; hardware microphone volume.
- Custom green panel, light/dark themes, login launch, diagnostics and audio permission guide.
- Public-API call replay and an opt-in experimental device-wide anti-ducking setting.
- Audio stays on your Mac. No virtual drivers, kernel extensions, or network services.

**Preview release:** real-call anti-ducking, Bluetooth transitions, audible failure recovery, and long-call sound quality need manual acceptance. Anti-ducking is off until enabled in Settings. The experimental device setting is undocumented and asks for confirmation. Read [TESTING.md](TESTING.md) and [REPORT.md](REPORT.md). Screen renders in `docs/screenshots/` use sample data.

## Install

Download the DMG from GitHub Releases, open it, and drag **suya-unduck.app** into **Applications**. Open it and allow **Screen & System Audio Recording** in Privacy & Security when requested. The menu bar icon opens the mixer; right-click opens quick actions.

This preview is ad-hoc signed, not notarized. macOS may require Privacy & Security → Open Anyway after the first attempt. A rebuild can require granting audio permission again. Set `SUYA_SIGN_IDENTITY` to an existing trusted code-signing identity for stable local signing; the build never adds a certificate to your keychain.

## Build locally

```sh
./scripts/selftest.sh
./scripts/build_dmg.sh
# Optional: build, copy to /Applications, and launch
./scripts/install.sh
```

Artifacts are in `dist/`. The package has no third-party dependencies. `Package.swift` supports normal SwiftPM builds; the scripts use `swiftc` directly because the currently installed Command Line Tools' SwiftPM crashes with a framework symbol mismatch. The SDK is selected by testing an import of CoreAudio and SwiftUI. Native arm64 builds target macOS 14.2.

## Lab

```sh
./scripts/build_lab.sh
.build/direct-release/suya-unduck-lab help
.build/direct-release/suya-unduck-lab env
.build/direct-release/suya-unduck-lab devices
.build/direct-release/suya-unduck-lab processes
```

Quit SoundSource before lab processing tests. Start with the public `method replay` test in TESTING.md. Device writes require `--i-approve-duck-writes`. Ctrl-C cleans up pipelines and conditionally restores experimental property values. SIGKILL cannot run cleanup; private tap lifetime is delegated to macOS, and experimental device writes may persist until macOS changes them.

Per-app settings live in `~/Library/Application Support/suya-unduck/settings.json`. Diagnostics copy the latest 200 events, layouts, errors, device names and callback counters. Never share diagnostics without reviewing them for app/device identifiers you consider private.
