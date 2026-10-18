# suya-unduck 0.2.0 verification

## Automated checks

`./scripts/selftest.sh` covers DSP, lock-free atomics with 2,000,000 concurrent operations, policy and settings migration, readable app filtering, call detection, and the anti-duck refresh lifecycle. It runs normally and with Thread Sanitizer for Swift and C.

The guard regression uses a fake device that reports unity and emits no listener events. It must still receive repeated commands while active; stop must cancel refreshes, conditionally restore only its own value, preserve external changes, and disable itself after a write failure. These tests do not prove audible unducking on a real call.

## User acceptance

1. Play YouTube in your browser. Its app should appear with a volume slider and Mute button. Set 30%, 100%, mute and unmute. No crackle should occur.
2. Enable **Keep volume during calls**, start a WhatsApp call, and play YouTube. The panel should say **Call detected**. Media should stay at its normal pre-call loudness. Both callers must remain clear. Repeat with FaceTime and a browser call.
3. End the call. The guard must stop refreshing and leave other app/system audio behavior normal. Repeat over a long call and with your usual headphones.
4. Open Settings. It should contain login launch, a short explanation, Audio access and Reset volumes. No raw bundle identifiers, protection lists or technical method choices should appear.
5. Open Reset volumes, then cancel. The modal must have an opaque surface and block controls behind it. Check dark/light appearance, small screen positioning, right-click Settings, Esc, outside click, keyboard sliders and focus indication confined to the slider thumb.
6. Quit while an app is attenuated. It should return to its normal audio path. Check sleep/wake, reconnecting output devices and a two-hour call for distortion.

**Known evidence:** the 0.1.0 preview failed the user's WhatsApp + YouTube test with replay and device methods enabled. A successful 0.2.0 real-call listening result has not yet been recorded. Do not treat automated tests or a successful property write as proof of audible recovery.

If something is wrong, click **Copy support info** and share that report. It includes detected call state and guard status. Review it for app/device identifiers before sharing publicly.

The advanced lab CLI remains available for engineering diagnostics; it is not part of the normal app UI. Run `./scripts/build_lab.sh` and `.build/direct-release/suya-unduck-lab help`. Quit other audio mixers before processing tests. Fault injection currently measures control teardown rather than physical audible recovery.
