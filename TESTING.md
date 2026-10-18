# suya-unduck 0.4.0 verification

## Automated

`./scripts/selftest.sh` checks unity-transparent DSP, ramps, mute, non-finite input, format faults, bounded output, C atomics with 2,000,000 concurrent operations, settings migration, call detection, session visibility, explicit call controls and routing precedence. It runs with Swift and C Thread Sanitizer too.

Guard tests inject a fake device that emits no listener event and continues reporting unity. Repeated enabled commands must continue; disabling stops them, conditionally restores owned values, preserves external changes, and stops retries after errors. Unduck replay must operate without a detected call. Default call audio must bypass processing until the user explicitly changes it.

## Actual audio-path verification

The optional engineering launch flags `--verify-volume <bundle-id> --verify-report <private-path>` use the actual application's capture identity and pipeline. They briefly apply 80% and 50%, record callback count/peak/format-error metadata, restore the exact prior setting and capture only the app's own panel to a private folder. They do not record audio samples. This is an explicit engineering check; normal launches do not change app levels automatically.

A successful live test requires a playing source, advancing callbacks, a nonzero signal peak and zero format errors. It establishes transport/processing, not audible unducking during a WhatsApp call.

The optional `--verify-effects <private-path>` observes system-effects callback count, maximum peak, format errors and activity-event count for sixty seconds after the pipeline becomes ready. It stores no samples. Take screenshots during this window and separately confirm whether you hear them.

## Manual acceptance

1. Play YouTube. Its browser must appear within about one second and immediately when opening the panel. Pause and resume; the row should remain. Call apps such as WhatsApp must also appear.
2. Adjust the browser to 30%, return to 100%, mute and unmute. Check for crackle or missing sound. Test a call app's manual controls too; defaults leave its original path untouched.
3. Select a main output. Choose a different output on one app. That app must use its specific choice; other apps must use main. Return its choice to **Use main output**. Disconnect/reconnect an override device and check fallback/return.
4. Move the microphone slider and compare System Settings both ways. Test input picker and hardware mute. A fixed-level mic must say it has no adjustable level. No microphone recording is used.
5. Keep volume enabled, start WhatsApp + YouTube. Compare media loudness to its pre-call baseline; listen for ticks/distortion and verify both callers remain clear. Repeat with FaceTime and browser calls. Enabled guard operation must not depend on the call-status heuristic.
6. Test a two-hour call, device changes, sleep/wake and quit/force quit. Measure audible recovery separately; callback counters do not establish an audible ≤300 ms recovery bound.
7. Inspect dark/light themes, device-picker dismissal, opaque reset dialog, keyboard focus, sliders, VoiceOver, screen edges and fullscreen Spaces. Public renders use fixtures; physical interaction remains a separate acceptance check.

If something fails, **Copy support info**. Local runtime metadata under the app's Logs directory also records discovered app activity, selected routes and pipeline/guard state. Review app/device identifiers before sharing publicly.

8. During a WhatsApp call, take CleanShot and native screenshots. Both must sound normally while YouTube stays at normal volume. Repeat off-call and with system effects routed to a different device. A prearmed pipeline with nonzero peak proves transport, not listening acceptance.
9. Scroll from the hardware controls through all app rows in one viewport. Inspect centered chevrons and the supplied waveform menu icon. Check hover, presses, switches, slider drag/focus, navigation, picker/dialog dismissal and panel open/close with Reduce Motion both enabled and disabled.
