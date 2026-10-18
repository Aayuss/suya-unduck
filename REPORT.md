# suya-unduck 0.3.0 verification report

## Evidence and causes

Both earlier previews failed the user's WhatsApp + YouTube unducking test. Screenshots showed an empty mixer while a video was playing and System Audio Recording permission enabled. Fresh live Core Audio probes during confirmed audible playback reported the browser's helper as running output and correctly grouped it to the browser. The old UI depended on listener-driven cached state, and excluded call apps entirely. Opening it did not force a refresh.

The reference Unduck-Pro engine at commit `5dcdd670c64a6fbbc2e5cb2f57c1611005ebd856` refreshes unducking while enabled, not only after a call-detection gate, and replays media through private aggregates. The earlier call-gated implementation could leave the guard inactive throughout a missed call. This identifies concrete implementation gaps; it does not retrospectively prove which specific gate caused every reported attenuation event.

## Corrections

- One-second discovery fallback, immediate refresh when opening, stable listener registrations and readable grouping of call helpers. User-facing audio sessions stay visible while paused, including call apps.
- Enabled unduck command refresh every 500 ms independent of call detection; include used physical outputs and our aggregates. Playing media uses the existing bit-exact unity path. No boost, private function lookup or unity clipping.
- Call audio defaults remain untouched. Explicit manual volume/mute/routing opts that app into a private pipeline; fail-safe handling returns the original path.
- Restored hardware mic level/mute/input picker, main output picker and per-app output picker. A saved app UID overrides main; missing devices fall back and return when reconnected. Installing does not automatically change system input/output selections.
- Neutral UI and opaque in-panel device picker. Microphone control modifies hardware properties and does not capture microphone audio.
- Asynchronous tap setup/teardown keeps macOS permission waits off the panel thread. Pending results are discarded when settings, devices or lifecycle state supersede them.
- Local-only state snapshots for diagnosing actual installed behavior, with no audio samples. Engineering live-volume verification restores prior settings and captures only the app's panel.

## Verification boundaries

All 82 checks passed both normally and under Thread Sanitizer, including 2,000,000 concurrent atomic operations. The suite covers DSP, atomic concurrency, enabled refresh without listener activity, restoration/error handling, call defaults versus explicit controls, session visibility, output precedence, disconnect fallback and reconnect return. It is run normally and under Thread Sanitizer.

The installed application's actual browser pipeline passed a live check at 80% and 50%: callbacks advanced from 227 to 426, peaks were nonzero, and both samples had zero format errors. The exact prior app setting was restored. macOS initially rejected the old permission identity after the ad-hoc binary changed; the user allowed the final build and transport succeeded. This preview has no stable Apple signing certificate, so another changed binary can require fresh permission. Fixture screenshots do not substitute for this live check. Physical routing to two different outputs, microphone acceptance in System Settings, real-call loudness/clarity and long-duration distortion checks require observation on the actual devices; automated results alone do not establish them.

Machine-specific probes, process IDs, original screenshots and runtime snapshots remain local and excluded from Git. The public report contains only sanitized summaries. Existing app/settings are backed up during installation, and volume/route choices persist by app/device identity.
