# suya-unduck

A compact native Apple Silicon macOS menu bar audio mixer with neutral surfaces, subtle green accents and Reduce Motion-aware transitions. Hardware and apps share one scroll area.

- **App volume:** music, browsers and call apps get independent volume and mute controls. Apps with an audio session stay visible while paused.
- **Main output:** choose the Mac's default audio output and adjust its hardware volume/mute when supported.
- **System sounds:** select the device for alerts and screenshot effects. The effects replay path stays ready for short sounds while unducking is enabled.
- **Per-app output:** choose a specific device for an app, or **Use main output**. A specific choice overrides the main output. A disconnected device temporarily falls back to main and returns when reconnected.
- **Microphone:** choose the input device, adjust its hardware level and mute it when supported.
- **Keep volume during calls:** enabled unducking uses per-app unity replay for playing media and repeated unity commands on the used physical and aggregate outputs. It does not depend on detecting a call first.

Call apps stay on their original audio path at default settings. Manually changing a call app's volume/mute/output opts that app into processing; failures return it to its original path. No audio is recorded to disk or uploaded, and no virtual audio driver is installed.

## Install

Get the DMG from [Releases](https://github.com/Aayuss/suya-unduck/releases). Drag **suya-unduck.app** into Applications. Requires Apple Silicon and macOS 14.2+.

Enable **suya-unduck** under **Privacy & Security → Screen & System Audio Recording** for app volume/routing. The microphone slider changes hardware settings without recording microphone audio. Devices with no adjustable level are labeled accordingly.

The app is ad-hoc signed, not notarized. macOS may require **Open Anyway** or renewed System Audio Recording approval after rebuilding. `SUYA_SIGN_IDENTITY` can select an existing trusted signing identity.

## Unducking implementation

The implementation was compared against [Unduck-Pro](https://github.com/MrRockySL/Unduck-Pro), commit `5dcdd670c64a6fbbc2e5cb2f57c1611005ebd856`. Like its engine, the enabled guard repeatedly writes the undocumented device command every 500 ms, including our aggregate devices, independently of call detection. Media replay is unity-transparent; no digital compensation boost is used. The original C-atomic realtime render path is retained, with no private function lookup or hard clipping at unity.

A one-second discovery fallback supplements Core Audio listeners, and opening the panel immediately refreshes the list. This deliberately trades a small amount of periodic work for reliable discovery after two failed previews. The unduck timer stops when disabled, on sleep or quit, and after device errors. Its original property is restored only while the current value still matches its last write.

The user confirmed normal YouTube loudness during WhatsApp calls with 0.3.0. Earlier previews failed that test. The 0.4.0 effects change addresses separately reported silent screenshots. Read [REPORT.md](REPORT.md) and [TESTING.md](TESTING.md) for the distinction between automated checks, live transport verification and audible call acceptance.

## Build / install from source

```sh
./scripts/selftest.sh
./scripts/build_dmg.sh
./scripts/install.sh
```

The installer gracefully quits the old app, backs up its app/settings, verifies the mounted DMG's app and installs it in Applications. Scripts select a compatible SDK and use `swiftc`/`clang`; a SwiftPM manifest is included. No third-party packages are required. Public screenshots contain sample data only. Support information and live diagnostic snapshots stay local and may contain app/device identifiers.
