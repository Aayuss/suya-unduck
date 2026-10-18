# suya-unduck

A small native macOS menu bar app for two things:

- **App volume:** adjust or mute individual music and video apps.
- **Keep volume during calls:** prevent macOS from lowering your media during FaceTime, WhatsApp and other calls.

The panel uses neutral light/dark surfaces with small green accents. There are no microphone, routing, protection-list, boost or audio-method settings. It follows your Mac's appearance. Call audio stays on its original path; internal audio processes are hidden.

## Install

Open the DMG from [Releases](https://github.com/Aayuss/suya-unduck/releases), then drag **suya-unduck.app** into Applications. This build requires Apple Silicon and macOS 14.2 or newer.

For app volume controls, enable **suya-unduck** in **System Settings → Privacy & Security → Screen & System Audio Recording**. Play audio in an app and it will appear in the mixer. Click its percentage to reset to 100%.

**Keep volume during calls** is one switch. Existing approval from the earlier preview is preserved. Its device command uses an undocumented Core Audio property, refreshed every 500 ms only during detected calls. It applies to the output device without digitally boosting your media. It may need changes after macOS updates. Real-call listening tests remain necessary; see [TESTING.md](TESTING.md).

The earlier preview failed a user-reported WhatsApp + YouTube test. Version 0.2.0 addresses call detection that depended only on microphone ownership and a listener-only guard that could miss renewed attenuation. These are implementation corrections, not a claim that a new real-call test has already passed.

Audio stays on your Mac. No driver installs, uploads or microphone recording. The app is ad-hoc signed and not notarized, so macOS may require **Privacy & Security → Open Anyway** after an update. System audio permission may need enabling again after a rebuild.

## Build

```sh
./scripts/selftest.sh
./scripts/build_dmg.sh
./scripts/install.sh
```

The scripts select a compatible SDK and build with `swiftc`/`clang`; `Package.swift` is also included. No third-party packages are required. `SUYA_SIGN_IDENTITY` can select an existing code-signing identity. No certificate is added automatically.

Settings migration backs up the earlier file before simplifying it, keeps app volumes/mutes and the anti-ducking opt-in, and removes old routing/boost behavior. Settings and support logs stay in the user's Library. Public screenshots use sample data.
