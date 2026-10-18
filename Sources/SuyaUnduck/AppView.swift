import SwiftUI
import AppKit
import ServiceManagement
import MixerCore
import MixerEngine
import CAtomics

@available(macOS 14.2, *) final class Model: ObservableObject {
    let engine = Engine()
    @Published var revision = 0
    @Published var screen = "Mixer"
    @Published var toast: String?
    @Published var confirmation: (String, () -> Void)?
    @Published var protectedID = ""
    @Published var meterTick = 0
    private var meterTimer: Timer?
    private var micWork: DispatchWorkItem?
    private var lastMicWrite = Date.distantPast
    var screenshotMode = false
    init(preview: Bool = false) { engine.changed = { [weak self] in self?.revision += 1 }; screenshotMode = preview; if preview { engine.loadPreview() } else { engine.start() } }
    func notify(_ message: String) { toast = message; DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.toast = nil } }
    func global<T>(_ path: WritableKeyPath<MixerCore.Settings, T>) -> Binding<T> {
        Binding(get: { self.engine.settings[keyPath: path] }, set: { self.engine.settings[keyPath: path] = $0; self.engine.persist(); self.engine.reconcile() })
    }
    func setting<T>(_ key: String, _ path: WritableKeyPath<AppSetting, T>) -> Binding<T> {
        Binding(get: { (self.engine.settings.apps[key] ?? AppSetting())[keyPath: path] }, set: { value in self.engine.update(key) { $0[keyPath: path] = value } })
    }
    func microphone(_ value: Float) {
        micWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            do { try Hardware.setInputVolume(value); self?.lastMicWrite = Date(); self?.revision += 1 }
            catch { self?.notify("Cannot adjust this microphone") }
        }
        micWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, 0.05 - Date().timeIntervalSince(lastMicWrite)), execute: work)
    }
    func meters(_ visible: Bool) {
        meterTimer?.invalidate(); meterTimer = nil
        if visible { meterTimer = Timer.scheduledTimer(withTimeInterval: 1/15, repeats: true) { [weak self] _ in self?.meterTick += 1 } }
    }
    func quit() { engine.quit(); NSApp.terminate(nil) }
}
@available(macOS 14.2, *) struct AppView: View {
    @ObservedObject var model: Model
    @Environment(\.colorScheme) var scheme
    private var resolvedScheme: ColorScheme { model.engine.settings.theme == "Dark" ? .dark : model.engine.settings.theme == "Light" ? .light : scheme }
    private var accent: Color { Color.accent(for: resolvedScheme) }
    private var muted: Color { Color(hex: resolvedScheme == .dark ? 0x8DA196 : 0x5A6B61) }
    var body: some View {
        let _ = model.revision
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        switch model.screen {
                        case "Settings": settings
                        case "Diagnostics": diagnostics
                        case "Permission": permission
                        case "Quick": quick
                        default: mixer
                        }
                    }.padding(.bottom, 4)
                }
                HStack { Action(title: "Diagnostics") { model.screen = "Diagnostics" }; Spacer(); Action(title: "Quit") { model.quit() } }
            }.padding(20)
            if let toast = model.toast { VStack { Spacer(); Text(toast).padding(12).background(.regularMaterial, in: Capsule()).padding(20) }.allowsHitTesting(false) }
            if let confirm = model.confirmation {
                Color.black.opacity(0.45).clipShape(RoundedRectangle(cornerRadius: 16))
                Card {
                    Text("Confirm change").font(.headline)
                    Text(confirm.0)
                    HStack { Action(title: "Cancel") { model.confirmation = nil }; Spacer(); Action(title: "Confirm") { let action = confirm.1; model.confirmation = nil; action() } }
                }.padding(24)
            }
        }.frame(width: 380, height: model.screen == "Quick" ? 300 : 580)
            .foregroundStyle(resolvedScheme == .dark ? Color(hex: 0xE9F3ED) : Color(hex: 0x0E1A13))
            .background(resolvedScheme == .dark ? Color(hex: 0x0D1310) : Color(hex: 0xF5F9F6), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.20)))
            .font(.system(size: 13, design: .rounded))
            .environment(\.colorScheme, resolvedScheme)
            .preferredColorScheme(model.engine.settings.theme == "Dark" ? .dark : model.engine.settings.theme == "Light" ? .light : nil)
    }
    var header: some View {
        HStack(spacing: 8) {
            if model.screen != "Mixer" { Action(title: "‹") { model.screen = "Mixer" }.accessibilityLabel("Back to mixer") }
            Circle().fill(accent).frame(width: 7, height: 7)
            Text(model.screen == "Mixer" || model.screen == "Quick" ? "suya-unduck" : model.screen).font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer()
            if model.engine.callActive { Text("Call active").font(.system(size: 10)).foregroundStyle(accent) }
            if model.screen == "Mixer" { Action(title: "Settings") { model.screen = "Settings" } }
        }
    }
    func label(_ text: String) -> some View { Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(muted) }
    var mixer: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("Output")
            devicePicker(input: false)
            label("Apps")
            if visibleApps.isEmpty {
                Card { Text("∿  ∿  ∿").font(.system(size: 35)).foregroundStyle(accent); Text("Play something — apps appear here."); Text("Audio stays on your Mac.").foregroundStyle(muted) }
            }
            ForEach(visibleApps) { app in appRow(app) }
            label("Microphone")
            Card {
                devicePicker(input: true)
                if let volume = model.screenshotMode ? Float(0.65) : Hardware.inputVolume() {
                    HStack { Text("Input volume"); Spacer(); Text("\(Int(volume * 100))%").monospacedDigit() }
                    GreenSlider(label: "Microphone volume", value: Binding(get: { Hardware.inputVolume() ?? 0 }, set: { model.microphone($0) }), maximum: 1)
                } else { Text("This mic has no adjustable volume").foregroundStyle(muted) }
                if let muted = model.screenshotMode ? false : Hardware.inputMuted() {
                    Action(title: muted ? "Unmute microphone" : "Mute microphone") { do { try Hardware.setInputMuted(!muted); model.revision += 1 } catch { model.notify("Microphone mute unavailable") } }
                }
            }
            if !model.engine.errors.isEmpty { Action(title: "Audio access and troubleshooting") { model.screen = "Permission" } }
        }
    }
    var visibleApps: [AudioApp] {
        model.engine.apps.filter { $0.playing || $0.recording || model.engine.settings.apps[$0.id] != nil || Protection.known.contains($0.id) }.sorted {
            let a = model.engine.settings.apps[$0.id]?.favorite ?? false, b = model.engine.settings.apps[$1.id]?.favorite ?? false
            if a != b { return a }; if $0.playing != $1.playing { return $0.playing }; return $0.name < $1.name
        }
    }
    func appRow(_ app: AudioApp) -> some View {
        let protected = app.protected || model.engine.settings.extraProtected.contains(app.id)
        let setting = model.engine.settings.apps[app.id] ?? AppSetting()
        return Card {
            HStack {
                if let icon = NSRunningApplication.runningApplications(withBundleIdentifier: app.id).first?.icon { Image(nsImage: icon).resizable().frame(width: 24, height: 24) }
                Text(app.name).fontWeight(.medium).lineLimit(1)
                Spacer()
                if protected { Text("Protected").font(.system(size: 10)).foregroundStyle(muted) }
                else {
                    Text("\(Int(setting.volume * 100))%").monospacedDigit().onTapGesture(count: 2) { model.engine.update(app.id) { $0.volume = 1 } }
                    Action(title: setting.muted ? "Unmute" : "Mute") { model.engine.update(app.id) { $0.muted.toggle() } }
                }
            }
            if !protected {
                GreenSlider(label: "\(app.name) volume", value: model.setting(app.id, \.volume))
                HStack {
                    GreenDropdown(label: "Route", values: [("", "System default")] + model.engine.devices.filter(\.output).map { ($0.uid, $0.name) }, selected: Binding(get: { setting.output ?? "" }, set: { v in model.engine.update(app.id) { $0.output = v.isEmpty ? nil : v } }))
                    Spacer(); Action(title: setting.favorite ? "★" : "☆") { model.engine.update(app.id) { $0.favorite.toggle() } }.accessibilityLabel("Favorite \(app.name)")
                }
                let _ = model.meterTick
                GeometryReader { geo in
                    Capsule().fill(accent.opacity(0.7)).frame(width: geo.size.width * CGFloat(min(1, model.engine.pipelines[app.id].map { am_load_peak($0.shared) } ?? 0)), height: 2)
                }.frame(height: 2)
                if let error = model.engine.errors[app.id] { Text("Playing normally · \(error)").font(.system(size: 10)).foregroundStyle(Color(hex: 0xFF6B6B)).textSelection(.enabled) }
            }
        }
    }
    func devicePicker(input: Bool) -> some View {
        let id = model.screenshotMode ? (input ? UInt32(3) : UInt32(1)) : Hardware.defaultDevice(input: input)
        return GreenDropdown(label: input ? "Input" : "Output", values: model.engine.devices.filter { input ? $0.input : $0.output }.map { (String($0.id), $0.name) }, selected: Binding(get: { String(id) }, set: { new in
            guard let id = UInt32(new) else { return }
            model.confirmation = ("Change the system \(input ? "input" : "output") device?", { do { try Hardware.setDefault(id, input: input); model.engine.refresh() } catch { model.notify("Device change failed: \(error)") } })
        }))
    }
    var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            label("General")
            Card {
                GreenToggle(title: "Launch at login", value: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { enabled in do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; model.revision += 1 } catch { model.notify("Login setting: \(error.localizedDescription)") } }))
                GreenDropdown(label: "Theme", values: ["System", "Dark", "Light"].map { ($0, $0) }, selected: model.global(\.theme))
            }
            label("Anti-ducking")
            Card {
                GreenToggle(title: "Replay media during calls", value: model.global(\.replay))
                Text("Public API replay is experimental until tested during your real call. No digital boost is applied.").font(.system(size: 11)).foregroundStyle(muted)
                GreenToggle(title: "Experimental device anti-ducking", value: Binding(get: { model.engine.settings.duckApproved }, set: { enabled in
                    if !enabled { model.engine.settings.duckApproved = false; model.engine.persist(); model.engine.reconcile() }
                    else { model.confirmation = ("Enable an undocumented audio setting that affects every app on the output device during calls? It may stop working after macOS updates. Verify call audio and notifications before relying on it.", { model.engine.settings.duckApproved = true; model.engine.persist(); model.engine.reconcile() }) }
                }))
            }
            Card {
                GreenToggle(title: "Experimental digital compensation", value: model.global(\.compensationEnabled))
                if model.engine.settings.compensationEnabled {
                    Text("Boost: \(String(format: "%.2f", model.engine.settings.compensation))×").foregroundStyle(Color(hex: 0xF5C451))
                    GreenSlider(label: "Experimental compensation boost", value: Binding(get: { model.engine.settings.compensation - 1 }, set: { model.engine.settings.compensation = $0 + 1; model.engine.persist(); model.engine.reconcile() }))
                }
                Text("Off by default. Boosts processed media digitally during calls and changes its dynamics. Requires replay or a custom volume/route.").font(.system(size: 11)).foregroundStyle(muted)
            }
            label("Calls")
            Card {
                GreenDropdown(label: "Call mode", values: ["Auto", "Always", "Never"].map { ($0, $0) }, selected: model.global(\.callMode))
                GreenToggle(title: "Browser calls count", value: model.global(\.browserCalls))
                Text("Call apps and apps using the mic are always protected.").font(.system(size: 11)).foregroundStyle(muted)
            }
            label("Protected apps")
            Card {
                Text(Protection.known.sorted().joined(separator: "\n")).font(.system(size: 10)).foregroundStyle(muted)
                ForEach(model.engine.settings.extraProtected, id: \.self) { id in HStack { Text(id); Spacer(); Action(title: "Remove") { model.engine.settings.extraProtected.removeAll { $0 == id }; model.engine.persist(); model.engine.reconcile() } } }
                TextField("Bundle ID", text: $model.protectedID).textFieldStyle(.plain).padding(8).background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8)).accessibilityLabel("Protected application bundle identifier")
                Action(title: "Add protection") {
                    let id = model.protectedID.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !id.isEmpty && !model.engine.settings.extraProtected.contains(id) { model.engine.settings.extraProtected.append(id); model.engine.persist(); model.engine.reconcile(); model.protectedID = "" }
                }
            }
            label("Advanced")
            Card {
                GreenDropdown(label: "Silent apps", values: [("keep-running", "Keep volume locked"), ("stop-io", "Stop audio IO when silent"), ("destroy", "Remove pipeline when silent")], selected: model.global(\.resumePolicy))
                Text("Keep volume locked uses some CPU while an app is open. Battery-saving modes may play at full volume briefly when media resumes.").font(.system(size: 11)).foregroundStyle(muted)
                HStack { Text("Stop after \(Int(model.engine.settings.idleStopSeconds))s"); Spacer(); Action(title: "−") { model.engine.settings.idleStopSeconds = max(5, model.engine.settings.idleStopSeconds - 5); model.engine.persist(); model.engine.reconcile() }; Action(title: "+") { model.engine.settings.idleStopSeconds = min(600, model.engine.settings.idleStopSeconds + 5); model.engine.settings.destroyIdleSeconds = max(model.engine.settings.destroyIdleSeconds, model.engine.settings.idleStopSeconds); model.engine.persist(); model.engine.reconcile() } }
                HStack { Text("Remove after \(Int(model.engine.settings.destroyIdleSeconds))s"); Spacer(); Action(title: "−") { model.engine.settings.destroyIdleSeconds = max(model.engine.settings.idleStopSeconds, model.engine.settings.destroyIdleSeconds - 30); model.engine.persist(); model.engine.reconcile() }; Action(title: "+") { model.engine.settings.destroyIdleSeconds = min(3600, model.engine.settings.destroyIdleSeconds + 30); model.engine.persist(); model.engine.reconcile() } }
            }
            Action(title: "Reset all volumes") { model.confirmation = ("Reset every app to 100% and remove saved routes?", { model.engine.settings.apps = [:]; model.engine.persist(); model.engine.reconcile() }) }
            Text("suya-unduck · 0.1.0\nPrivate audio processing. No drivers. No uploads.").font(.system(size: 11)).foregroundStyle(muted)
        }
    }
    var diagnostics: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Anti-ducking and long-call audio quality need real-call verification.").foregroundStyle(Color(hex: 0xF5C451))
            Action(title: "Copy diagnostics") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.engine.diagnostics(), forType: .string); model.notify("Copied") }
            Action(title: "Open log folder") { NSWorkspace.shared.open(EventLog.folder) }
            Action(title: "Audio permissions") { model.screen = "Permission" }
            Text(model.screenshotMode ? "suya-unduck\nUI preview — sample data\nNo audio processing or measurements\nCall: inactive\nReplay: off\nPipelines: 0\nNo errors" : model.engine.diagnostics()).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
        }
    }
    var permission: some View {
        Card {
            Text("Let suya-unduck adjust app audio").font(.headline)
            Text("1. Open Privacy & Security.\n\n2. Enable suya-unduck in Screen & System Audio Recording.\n\n3. Quit and reopen suya-unduck, then play audio and adjust an app’s volume.")
            Action(title: "Open System Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!) }
            Text("Microphone audio is never captured. Protected call apps keep their normal audio path.").foregroundStyle(muted)
        }
    }
    var quick: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Action(title: "Mute media") { for app in model.engine.apps where !app.protected { model.engine.update(app.id) { $0.muted = true } } }; Action(title: "Unmute") { for key in Array(model.engine.settings.apps.keys) { model.engine.update(key) { $0.muted = false } } } }
            GreenDropdown(label: "Call mode", values: ["Auto", "Always", "Never"].map { ($0, $0) }, selected: model.global(\.callMode))
            Action(title: "Settings") { model.screen = "Settings" }
        }
    }
}
