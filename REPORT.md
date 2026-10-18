# suya-unduck 0.4.0 verification report

## Confirmed behavior from 0.3.0

The user confirmed YouTube stays at normal loudness during a WhatsApp call. The installed browser path also passed a metadata-only transport check at 80% and 50%, with advancing callbacks, nonzero signal and zero format errors. This release retains the enabled 500 ms device guard and unity media processing that passed that call check.

## Screenshot sound investigation

The user reported that CleanShot and native screenshots are silent during a WhatsApp call, but CleanShot sounds normally off-call. A 40 ms activity observer saw very short output events from `systemsoundserverd` for the screenshots. Both main and system-effects outputs were the same device. No application mute/route preference accounted for the missing sound.

The old engine excluded the background system-effects source from automatic replay. Its brief events can also end before one-second app discovery. The new engine groups that source as System sounds and keeps its unity replay path ready while unducking is enabled, even while idle. It uses the actual system-effects output, including when that differs from main. Idle sources no longer trigger the active-source stall watchdog; format errors still fail safe. Disabling unducking removes the idle replay; call and microphone protections remain in place. This addresses the observed coverage gap; audible acceptance must still be checked in a real call.

## UI

- Supplied transparent waveform artwork replaces only the menu-bar icon. The application icon remains unchanged.
- Centered SF Symbol chevrons replace baseline-aligned arrow text.
- Compact shared app rows combine app name/output and slider/mute. Hardware and apps share one scroll view. The main panel is 380 × 560 points, constrained to the available screen height.
- Main output level/mute, system-effects output, microphone level/mute/input and per-app output choices remain directly available.
- Panel fade/resize, navigation, picker/dialog/toast transitions, switch motion, hover/press feedback and slider interaction use short animations. Reduce Motion removes motion effects. Sliders follow dragging directly, without lagging value animations.

## Verification boundaries

All 89 checks passed normally and under Thread Sanitizer, including 2,000,000 concurrent atomic operations. Automated policy/DSP/concurrency checks include idle effects prearming, unity gain, effects-device selection, disabling and protected-call bypass. Fixture renders cover light/dark mixer, output picker, settings, permission, reset and empty states. Actual screenshot sound, live call clarity, physical multi-device routing and motion feel require observation on the Mac. Metadata-only live checks do not establish audible loudness or absence of ticks.

Machine-specific activity logs, live screenshots and diagnostic snapshots stay in ignored local evidence. Public screenshots contain fixtures only. The installer preserves previous app/settings backups. Ad-hoc signing can require renewed macOS audio permission for a changed binary.
