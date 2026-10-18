# suya-unduck testing

## Automated

Run `./scripts/selftest.sh`. It checks unity sample equality, mute, ramps, output shapes, tap offsets, non-finite input, limiter behavior, buffer mismatch/fault flags, settings defaults/migration, grouping, call protection, lock-free atomics and 2,000,000 concurrent atomic operations. The suite is also built and run with Thread Sanitizer for Swift and C. These tests do not establish real-time execution behavior or audible call safety.

## Phase 0: anti-ducking evidence

Quit SoundSource using its own Quit action. Leave its driver installed. Build the lab with `./scripts/build_lab.sh`. Use `.build/direct-release/suya-unduck-lab` before each command below. Do not test two audio mixers simultaneously.

1. Save `env`, `devices`, and `processes` output. Optional `probe-layout` inspects an unmuted tap/aggregate without starting IO; it only proves setup layout compatibility.
2. Start a WhatsApp call and YouTube playback in Chrome, with no processing running. Notice the baseline ducking.
3. Run `watch-duck --minutes 2`. This is read-only. Compare LISTENER events with SNAPSHOT values.
4. Run `method replay --bundle com.google.Chrome --minutes 2`. Allow System Audio Recording for the host running the lab when asked. Does YouTube stay at normal volume? Is there crackle? Can both people still hear one another?
5. Only if replay fails and you accept an undocumented device-wide setting, run `method duck-device --minutes 2 --i-approve-duck-writes`. Check for ticks, notification volume changes, call or mic problems.
6. Only if needed, try `method replay+duck --bundle com.google.Chrome --minutes 2 --i-approve-duck-writes`.
7. Run `layout --bundle com.google.Chrome` with speakers, then with AirPods connected. It logs the validated aggregate layout and callback/error counts. Unsupported layouts are refused.
8. Run `resume-test --bundle com.google.Chrome --gain 0.2 --strategy keep-running --minutes 3`. Pause for 15 seconds and resume three times. Listen for full-volume bursts. `stop-io` also supports resume. `destroy` currently removes the pipeline and requires rerunning the command to restore processing; automatic recreation in this lab strategy remains outstanding.
9. Run `fault-inject --bundle com.google.Chrome`. This prints **control teardown latency**, not physical audible recovery. Repeat 20 times and record an external audio measurement to establish worst audible recovery (target ≤300 ms).
10. Paste the outputs and listening observations back for method selection. Do not infer effectiveness from the duck value or callback count alone.

The app uses only event-driven DuckGuard writes. If the property listener does not report changes on your device, do not rely on that method. No unverified polling workaround is enabled.

## App acceptance

- T1: Chrome volume 30% → quieter without crackle; 100% → normal.
- T2: Mute/unmute Chrome.
- T3: Spotify → speakers and Chrome → AirPods simultaneously. Disconnect/reconnect AirPods and check fallback/return.
- T4: WhatsApp call + YouTube with replay enabled, no digital boost. Verify normal media level without ticks. If necessary, separately test the explicitly approved experimental method.
- T5: Change media volume/device during the call. Both people must remain audible.
- T6: At least two hours of calling plus media with no distortion.
- T7: AirPods media at 50% with no call: high quality, no microphone indicator caused by suya-unduck.
- T8: Microphone slider follows System Settings in both directions. Fixed-volume microphones show unavailable.
- T9: Idle ten minutes with no processing: measure CPU, RAM, wakeups in Activity Monitor. Targets <0.1% CPU, <1 wakeup/s, <50 MB RAM. Measure one playing pipeline (<1%), one silent custom pipeline (<0.5%), and open panel (<3%).
- T10: Sleep/wake three times; settings and audio recover.
- T11: Quit while Chrome is at 30%; Chrome returns to normal. Repeat with force quit, recording recovery externally.
- T12: Enable launch at login, reboot, verify startup and saved levels.
- T13: Inspect both themes; keyboard Tab/Shift-Tab, arrow-adjustable sliders, dropdown selection, Escape, VoiceOver names and values. Check two displays, fullscreen Spaces, menu bar auto-hide, left/right/Ctrl-click, outside clicks, text field focus and display removal.

## Reliability

Run `soak --bundle com.google.Chrome --minutes 120 --gain 1` during a real call, ideally with AirPods. Save callback/error/peak logs. A clean log does not replace listening.

Connect/disconnect AirPods ten times, explicitly change default output ten times, sleep/wake three times, pause/resume 30 times with 5–60 second gaps. Play Chrome, Spotify and Music on two devices for one hour. Force quit while processing and verify original audio recovery.

Bluetooth headset microphones force macOS's lower-quality call profile; this app cannot prevent that while another app uses the headset mic.

If anything is off, open **Diagnostics → Copy diagnostics** and paste the report, along with what you heard. All real-device acceptance items remain pending until recorded in REPORT.md.
