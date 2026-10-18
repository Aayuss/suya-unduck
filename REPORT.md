# suya-unduck implementation and verification report

Date: 2026-10-18 (Asia/Kathmandu). Status: **preview; real-call and reliability acceptance pending**.

## Local verification summary

Machine-specific inventories, device identifiers, original screenshots and full build logs are retained locally in `dist/local-evidence/` and excluded from Git. This public report contains only implementation and validation summaries.

- Apple Silicon release build compiled with Swift language mode 5 and a compatible macOS SDK chosen by an import/typecheck probe.
- The installed SwiftPM could not launch because of a bundled framework symbol mismatch. The working scripts compile the independent modules directly with `swiftc` and `clang`.
- A passive unmuted-tap setup probe found the supported Float32 packed/interleaved stereo layout on the built-in output: 48 kHz, format flags 9, 8 bytes/frame, one input and one output stream/buffer. No IO was started; this does not verify capture or audible playback.
- Final normal suite: **52 checks passed**, including DSP, routing/silence/call policy, settings and 2,000,000 concurrent atomic operations.
- Final Thread Sanitizer suite: **52 checks passed** with Swift and C instrumentation; no reported race. This is deterministic self-test coverage, not a complete engine execution audit.
- Published screen renders use deterministic sample data, with no local app activity or device identifiers. They verify visual layout, not real audio processing.

## Expected by design

One private process tap and aggregate per app group. The selected physical output supplies the aggregate clock. Tap drift compensation is on. Core Audio's `.mutedWhenTapped` behavior supplies the normal audio path when IO stops. Unsupported/ambiguous layouts are refused before playback. Every callback checks buffer counts, tap offset, channel shape, data presence and bounded byte sizes. First-three-callback shapes are recorded in C atomics and available in diagnostics.

The callback captures only immutable render layout and preallocated pointers; it invokes AudioRender and C atomics without logging, queues, locks, property calls or class access. Finite samples pass bit-exactly at unity; attenuation has no limiter. Only gains above unity use soft limiting. NaN/Infinity input is silenced. Independent counters and one-way failure flags are lock-free. Callback state is freed only after stopping/destroying IO. Runtime teardown error handling deliberately retains callback storage if HAL cannot confirm destruction, avoiding a use-after-free.

App configuration, device/process reconciliation and lifecycle run on the main serial queue. Settings writes are atomic and debounced. Corrupt files are preserved with a timestamped extension. System/process/device property listeners trigger updates. The watchdog runs only with running pipeline IO; meters refresh only while the panel is visible. Silence policies use one-shot deadlines. Idle without processing uses no repeating timers.

Known call applications and apps using input are protected. Parent PID traversal and bundle rules group helpers. Routes persist by UID, fall back when missing, and return when the device reconnects. System defaults change only after an explicit selection and confirmation. Hardware input volume/mute changes do not capture microphone audio; physical input streams in an output aggregate must be successfully disabled or creation fails.

Public replay, experimental DuckGuard and digital compensation all start off. DuckGuard requires explicit in-app confirmation or the lab approval flag; validates the 16-byte property; uses listeners and event-triggered, rate-limited writes; stops after errors/conflicts; and restores only while the current value equals its last write. There is no periodic DuckGuard fallback without evidence. No private functions, virtual drivers or daemon restarts are used.

## Rule review

| Rule | Implementation / evidence |
| --- | --- |
| 1 Call protection | Known IDs plus their sub-identifiers and all input-active groups bypass processing. No override to weaken this protection is exposed in this preview. |
| 2 Real-time callback | Value/pointer-only block; render + C atomics. Source review done; live profiling remains pending. |
| 3 Shared state | C11 atomics for render/control communication. Control state confined to main queue; file logger state confined to its own serial queue. Concurrent atomics tested with TSan. |
| 4 Unity transparency | Random Float32 unity bit-pattern comparison passed; limiting only above unity. |
| 5 No default boost | Compensation starts disabled and is labeled experimental. |
| 6 Clocked aggregate | Physical output is main and clock device; tap drift compensation enabled; no ring-buffer bridge. |
| 7 Reader safety | `.mutedWhenTapped`; no permanently muted taps. |
| 8 Fail-safe | Format failure triggers teardown by a 250 ms watchdog. Circuit breaker disables after three recent errors, retries by deadline. Audible ≤300 ms recovery is NOT YET VERIFIED. |
| 9 Private devices | Both tap and aggregate are private. Crash cleanup behavior needs physical acceptance. |
| 10 Device defaults | Changed only through explicit device selection and confirmation. No automatic rate/hog changes. |
| 11 Private API boundary | Experimental selector isolated in DuckGuard.swift; off by default; no private symbol loading. |
| 12 Idle behavior | Event listeners; watchdog only while running; panel-only meters; one-shot idle/cooldown deadlines. |
| 13 No drivers | No HAL installation, kernel extension or coreaudiod restart code. |
| 14 Custom UI | Status item + borderless NSPanel + custom SwiftUI controls. No native menus/alerts/sliders. Keyboard/VoiceOver acceptance still pending. |
| 15 Attribution | THIRD_PARTY_NOTICES.md records the supplied spec and architectural references. No GPL code copied. |
| 16 RT verification | Lock-free check + bounded loops + callback source review + TSan tests. Ten-minute live callback profiling remains pending. |
| 17 Evidence honesty | Measured results separated from expected behavior; preview is not declared complete against critical acceptance. |

## Critical acceptance still required

| Check | Status |
| --- | --- |
| Phase 0 real-call method comparison | NOT YET VERIFIED. No method selected as proven. |
| T4 Media remains at full volume during WhatsApp call | NOT YET VERIFIED |
| T5 Call and microphone remain clear | NOT YET VERIFIED |
| T6 Two-hour distortion-free call | NOT YET VERIFIED |
| Audible fault recovery ≤300 ms, worst of 20 runs | NOT YET VERIFIED. Lab currently measures teardown only, not physical audible recovery. |
| Silence/resume bursts on speakers/AirPods | NOT YET VERIFIED |
| Device churn, multi-device routing, sleep/wake, force quit | NOT YET VERIFIED |
| Idle ten-minute CPU/wakeups/RAM targets | NOT YET VERIFIED |
| Playing/silent pipeline and open-panel CPU targets | NOT YET VERIFIED |
| Two-display, fullscreen, auto-hide, keyboard and VoiceOver interaction | NOT YET VERIFIED |

## Preview differences from the supplied spec

The user's direct request to build/package/push was followed; the supplied document's phase-stop text was treated as project guidance, not a new user instruction to stop all work. Live evidence gates remain explicit and experimental defaults remain off.

The preview implements the app, lab, tests, build scripts, icons and CI without waiting on a real call. It does not infer anti-ducking success from the undocumented property existing. The lab's fault test reports control teardown only; its destroy-on-silence strategy requires restarting the command instead of automatically recreating a destroyed pipeline. Per-device/macOS verification records, automated audible fault measurement, detailed per-pipeline overload counters, tooltip delay/scroll-wheel slider adjustments and full accessibility/UI acceptance remain outstanding. No signing certificate was added to the keychain; builds use ad-hoc signatures unless an existing identity is supplied. App Store distribution and notarization are outside this preview.

## Build and static verification

- Local arm64 application and CLI compile with zero errors/warnings using `./scripts/selftest.sh` (followed by UI theme/contrast corrections, a passive layout diagnostic command, and a release rebuild).
- `codesign --verify --deep --strict` passed on the packaged app. Signature is ad-hoc with hardened runtime; it is not Developer ID signed or notarized.
- A compressed DMG was generated locally and `hdiutil verify` passed. The release includes a SHA256 checksum file.
- All five screens were rendered to PNG in both themes with deterministic sample data and visually inspected. The initial light-mode render exposed an appearance propagation issue, which was corrected before publication. Native menu/keyboard/VoiceOver interaction is still pending.
- Plists passed `plutil -lint`; shell scripts passed syntax validation; source name scan found no old app name; `git diff --check` passed.
- Forbidden visible UI scan returned no matches:

```sh
rg -n 'NSMenu|NSPopover|NSAlert|MenuBarExtra|\b(Slider|Toggle|Picker|Menu|Stepper|Form|List)\s*\(|\.(alert|sheet|popover|contextMenu|help)\s*\(|systemName:' Sources/SuyaUnduck
# no output, exit 1
```

GitHub build status is reported separately after the actual remote run; local results are not a claim of green CI.
