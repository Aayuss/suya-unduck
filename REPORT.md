# suya-unduck 0.4.1 verification report

## Todoist completion sound at 100%

The user reported completion sounds only above 100%, including off-call. Live 0.4.0 metadata showed Todoist idle with a running pipeline at a boosted volume; logs also showed repeated Todoist pipeline starts/stops. At unity, the old policy kept only the system-effects source ready while idle. A regular app's short sound had to activate discovery/setup, and the pipeline was removed again when the sound ended. Boosting counted as a custom setting and retained the pipeline across silence.

While unducking is enabled, eligible user-facing apps with an existing Core Audio session now keep their path ready at unity as well. This extends the readiness policy already used for system effects; it does not add gain. The change covers short app sounds generally, rather than hardcoding Todoist. Call/microphone and background-process protections still apply, and disabling unducking removes default-volume idle app paths. No new settings are exposed. Keeping more eligible paths ready deliberately uses some background resources to prevent transient sounds being caught during setup/teardown.

All 93 checks passed normally and under Thread Sanitizer, including 2,000,000 concurrent atomic operations. Regression tests cover ready paths at 99%, 100% and 101% without a call, disabling, protected-call bypass, idle health, gain/DSP and concurrency. After installing 0.4.1 and setting Todoist to exactly 100%, the user confirmed that its completion sound plays. The installed runtime also showed Todoist at volume 1 with an idle, ready pipeline and no error. This is listening acceptance for the reported Todoist case, not a new call-time acceptance test.

## Preserved verified behavior

The user confirmed normal YouTube loudness in a WhatsApp call with 0.3.0, and both CleanShot and native screenshot sounds in a WhatsApp call with 0.4.0. The 0.4.0 effects check recorded advancing callbacks, nonzero peak and zero format errors. This patch preserves the enabled device guard, system-effects routing, supplied icon and compact UI. These earlier acceptance results are historical, not a new physical test of 0.4.1.

Private runtime snapshots, live screenshots and device/process identifiers stay in ignored local evidence. Public screenshots remain fixtures. The installer backs up the previous app/settings; ad-hoc signing may require fresh macOS audio permission for the changed binary.
