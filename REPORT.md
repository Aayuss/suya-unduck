# suya-unduck 0.2.0 report

## Changes prompted by user evidence

The user reported that YouTube still became quieter during a WhatsApp call with both preview anti-ducking methods enabled and digital compensation disabled. This is a failed real-call acceptance test for 0.1.0.

Two implementation gaps could explain it:

- Call detection required input activity on the grouped calling app. Active output from known call apps now also counts, allowing for helper-owned microphone paths. Browser microphone use and user apps using input/output are included; background speech services do not trigger the guard.
- The guard relied on property listeners and skipped a command when the readable value was already unity. It now refreshes the device command every 500 ms during a detected call, even without listener events or a readable change. Refreshes stop on call end, error, conflict, sleep or quit. No idle timer is introduced.

These changes do not establish the exact cause of the earlier incident, nor prove that the new version has passed a real call.

## Interface

Neutral charcoal/white surfaces, ordinary text and buttons, muted green switch/slider accents. Normal UI contains app volume controls and one call-volume switch. Settings contain login launch, help and reset. Removed microphone controls, routing pickers, protection lists, boost, call-mode and timer settings. Background/system audio processes and untouched call rows are hidden.

The confirmation surface is fully opaque with a dimmed, noninteractive background; the oversized slider focus border is replaced by a thumb outline. Percent labels reset volume to 100%. The panel follows system appearance and uses appropriate dimensions for each page. Public renders use deterministic sample data only.

## Migration and installation

The earlier settings file is backed up locally before migration. Volumes, mute states and existing device-property consent are retained. Legacy replay, digital compensation and routes are disabled/cleared. No system default output/input device or sample rate is changed by this update. The installed app is replaced only after a graceful quit and backed up before replacement.

## Verification scope

DSP, atomic concurrency and policy tests remain in the suite. New regressions cover call detection without same-app microphone ownership, background speech exclusion, visible app filtering, settings migration, scheduled unity refresh without events/readable deltas, no writes after stop, conditional restoration, failure disabling and refusal without approval. Guard tests inject fake property access; they never capture microphone/audio or write real device properties.

Real-call media loudness, call clarity, AirPods transitions, two-hour distortion checks, audible failure recovery and full physical keyboard/VoiceOver acceptance remain pending until actually observed. Private taps use `.mutedWhenTapped`; realtime DSP and gain limiting rules are unchanged. No virtual drivers, private function calls, software boost or audio uploads are added.

Machine-specific state and original diagnostics remain local and excluded from Git. Local/CI test counts and actual installation outcome are reported after execution.
