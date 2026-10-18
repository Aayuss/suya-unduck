import SwiftUI
import AppKit
import ServiceManagement
import MixerCore
import MixerEngine

struct DeviceChoice {
    let title: String
    let values: [(String, String)]
    let selected: String
    let apply: (String) -> Void
}
@available(macOS 14.2, *) final class Model: ObservableObject {
    let engine: Engine
    @Published var revision = 0
    @Published var screen = "Mixer"
    @Published var toast: String?
    @Published var confirmation: (String, () -> Void)?
    @Published var deviceChoice: DeviceChoice?
    var screenshotMode = false
    private var micWork: DispatchWorkItem?
    private var lastMicWrite = Date.distantPast
    init(preview: Bool = false) {
        engine = Engine(preview: preview)
        engine.changed = { [weak self] in self?.revision += 1 }
        screenshotMode = preview
        if preview { engine.loadPreview() } else { engine.start() }
    }
    func setting<T>(_ key: String, _ path: WritableKeyPath<AppSetting, T>) -> Binding<T> {
        Binding(get: { (self.engine.settings.apps[key] ?? AppSetting())[keyPath: path] }, set: { value in self.engine.update(key) { $0[keyPath: path] = value } })
    }
    func notify(_ message: String) { toast = message; DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.toast = nil } }
    func meters(_ visible: Bool) { if visible && !screenshotMode { engine.refresh() } }
    func microphone(_ value: Float) {
        micWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            do { try Hardware.setInputVolume(value); self?.lastMicWrite = Date(); self?.revision += 1 }
            catch { self?.notify("This microphone cannot adjust its level") }
        }
        micWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, 0.05 - Date().timeIntervalSince(lastMicWrite)), execute: work)
    }
    func pickMain(input: Bool) {
        let choices = engine.devices.filter { input ? $0.input : $0.output }
        let current = screenshotMode ? (input ? UInt32(3) : UInt32(1)) : Hardware.defaultDevice(input: input)
        deviceChoice = DeviceChoice(title: input ? "Microphone" : "Main output", values: choices.map { (String($0.id), $0.name) }, selected: String(current), apply: { [weak self] selected in
            guard let id = UInt32(selected), let self else { return }
            if !self.screenshotMode { do { try Hardware.setDefault(id, input: input); self.engine.refresh() } catch { self.notify("Couldn’t change the device") } }
        })
    }
    func pickApp(_ app: AudioApp) {
        deviceChoice = DeviceChoice(title: "Output for \(app.name)", values: [("", "Use main output")] + engine.devices.filter(\.output).map { ($0.uid, $0.name) }, selected: engine.settings.apps[app.id]?.output ?? "", apply: { [weak self] value in self?.engine.update(app.id) { $0.output = value.isEmpty ? nil : value } })
    }
    func quit() { engine.quit(); NSApp.terminate(nil) }
    var volumeLock: Binding<Bool> {
        Binding(get: { self.engine.settings.duckApproved }, set: { self.engine.settings.duckApproved = $0; self.engine.persist(); self.engine.reconcile() })
    }
}
@available(macOS 14.2, *) struct AppView: View {
    @ObservedObject var model: Model
    @Environment(\.colorScheme) private var systemScheme
    private var scheme: ColorScheme { model.engine.settings.theme == "Dark" ? .dark : model.engine.settings.theme == "Light" ? .light : systemScheme }
    private var muted: Color { Color.muted(for: scheme) }
    var body: some View {
        let _ = model.revision
        ZStack {
            VStack(alignment: .leading, spacing: 18) {
                header
                if model.screen == "Settings" { preferences }
                else if model.screen == "Permission" { permission }
                else {
                    callControl
                    hardwareControls
                    HStack { Text("APP VOLUME").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(muted); Spacer(); Text("0–200%").font(.system(size: 10)).foregroundStyle(muted) }
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            if visibleApps.isEmpty {
                                VStack(spacing: 10) {
                                    Text("Play something").font(.system(size: 16, weight: .medium))
                                    Text("Open an app that uses audio.\nIts volume and output controls appear here.").multilineTextAlignment(.center).foregroundStyle(muted).lineSpacing(4)
                                }.frame(maxWidth: .infinity).padding(.vertical, 40)
                            }
                            ForEach(visibleApps) { app in appRow(app) }
                        }.padding(.bottom, 4)
                    }.frame(maxHeight: .infinity)
                }
                footer
            }.padding(20).allowsHitTesting(model.confirmation == nil && model.deviceChoice == nil).accessibilityHidden(model.confirmation != nil || model.deviceChoice != nil)
            if let toast = model.toast {
                VStack { Spacer(); Text(toast).padding(12).background(Color.surface(for: scheme), in: Capsule()).shadow(radius: 8).padding(18) }.allowsHitTesting(false)
            }
            if let choice = model.deviceChoice {
                Color.black.opacity(0.35).clipShape(RoundedRectangle(cornerRadius: 16)).contentShape(Rectangle()).onTapGesture { model.deviceChoice = nil }
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(choice.title).fontWeight(.semibold); Spacer(); Action(title: "Close") { model.deviceChoice = nil } }
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(choice.values, id: \.0) { value in
                                Button { model.deviceChoice = nil; choice.apply(value.0) } label: {
                                    HStack { Text(value.1).lineLimit(2); Spacer(); if value.0 == choice.selected { Text("✓").foregroundStyle(Color.accent(for: scheme)) } }
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                        .background(Color.primary.opacity(value.0 == choice.selected ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 7))
                                }.buttonStyle(.plain).accessibilityLabel(value.1)
                            }
                        }
                    }.frame(height: min(CGFloat(choice.values.count) * 46, 260))
                }.padding(16).frame(width: 310).background(Color.surface(for: scheme), in: RoundedRectangle(cornerRadius: 14)).shadow(color: .black.opacity(0.3), radius: 20, y: 6).accessibilityAddTraits(.isModal)
            }
            if let confirm = model.confirmation {
                Color.black.opacity(0.48).clipShape(RoundedRectangle(cornerRadius: 16)).contentShape(Rectangle()).onTapGesture { model.confirmation = nil }
                VStack(alignment: .leading, spacing: 16) {
                    Text("Reset app volumes?").font(.system(size: 16, weight: .semibold))
                    Text(confirm.0).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                    HStack { Action(title: "Cancel") { model.confirmation = nil }; Spacer(); Action(title: "Reset") { model.confirmation = nil; confirm.1() } }
                }.padding(20).frame(width: 300).background(Color.surface(for: scheme), in: RoundedRectangle(cornerRadius: 14)).shadow(color: .black.opacity(0.3), radius: 20, y: 6)
                    .accessibilityAddTraits(.isModal)
            }
        }.frame(width: 360, height: model.screen == "Settings" ? 330 : model.screen == "Permission" ? 390 : 640)
            .foregroundStyle(scheme == .dark ? Color(hex: 0xEFEFF1) : Color(hex: 0x202126))
            .background(Color.panel(for: scheme), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.10)))
            .font(.system(size: 13))
            .environment(\.colorScheme, scheme)
            .preferredColorScheme(model.engine.settings.theme == "System" ? nil : scheme)
    }
    var header: some View {
        HStack {
            if model.screen == "Mixer" { Text("suya-unduck").font(.system(size: 16, weight: .semibold)); Spacer(); Action(title: "Settings") { model.screen = "Settings" } }
            else { Action(title: "‹ Back") { model.screen = "Mixer" }; Spacer(); Text(model.screen).fontWeight(.semibold) }
        }
    }
    var callControl: some View {
        Card {
            AccentSwitch(title: "Keep volume during calls", value: model.volumeLock)
            HStack(spacing: 7) {
                Circle().fill(model.engine.settings.duckApproved ? Color.accent(for: scheme) : muted.opacity(0.4)).frame(width: 5, height: 5)
                Text(model.engine.settings.duckApproved ? (model.screenshotMode || model.engine.unduckStatus == "active" ? "On · keeps media at normal volume" : "This output needs checking · copy support info") : "Off · macOS can lower media during calls")
                    .font(.system(size: 11)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    func routeButton(title: String, name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) { Text(title).foregroundStyle(muted); Spacer(minLength: 8); Text(name).lineLimit(1); Text("⌄").foregroundStyle(muted) }.font(.system(size: 12)).contentShape(Rectangle()).padding(.vertical, 3)
        }.buttonStyle(.plain).accessibilityLabel("\(title): \(name)")
    }
    var hardwareControls: some View {
        let outputID = model.screenshotMode ? UInt32(1) : Hardware.defaultDevice()
        let inputID = model.screenshotMode ? UInt32(3) : Hardware.defaultDevice(input: true)
        return Card {
            routeButton(title: "Main output", name: model.engine.devices.first { $0.id == outputID }?.name ?? "Unavailable") { model.pickMain(input: false) }
            Text("Per-app output choices take priority.").font(.system(size: 10)).foregroundStyle(muted)
            Divider().opacity(0.35)
            routeButton(title: "Microphone", name: model.engine.devices.first { $0.id == inputID }?.name ?? "Unavailable") { model.pickMain(input: true) }
            if let level = model.screenshotMode ? Float(0.65) : Hardware.inputVolume() {
                HStack {
                    Text("Input level").font(.system(size: 11)).foregroundStyle(muted)
                    Spacer()
                    Text("\(Int(level * 100))%").font(.system(size: 11)).monospacedDigit().foregroundStyle(muted)
                    if let micMuted = model.screenshotMode ? false : Hardware.inputMuted() {
                        Action(title: micMuted ? "Unmute mic" : "Mute mic") { do { try Hardware.setInputMuted(!micMuted); model.revision += 1 } catch { model.notify("Mic mute unavailable") } }.font(.system(size: 10))
                    }
                }
                VolumeControl(label: "Microphone input level", value: Binding(get: { model.screenshotMode ? 0.65 : Hardware.inputVolume() ?? 0 }, set: { model.microphone($0) }), maximum: 1)
            } else { Text("This microphone has a fixed input level.").font(.system(size: 11)).foregroundStyle(muted) }
        }
    }
    var visibleApps: [AudioApp] {
        model.engine.apps.filter { app in
            let userApp = model.screenshotMode || Hardware.isUserFacing(app)
            return AppPresentation.showInMixer(isUserApp: userApp, playing: app.playing, hasSavedVolume: model.engine.settings.apps[app.id] != nil, hasAudioSession: model.screenshotMode || !app.processes.isEmpty)
        }.sorted { if $0.playing != $1.playing { return $0.playing }; return $0.name < $1.name }
    }
    func appRow(_ app: AudioApp) -> some View {
        let setting = model.engine.settings.apps[app.id] ?? AppSetting()
        return Card {
            HStack(spacing: 10) {
                if let icon = NSRunningApplication.runningApplications(withBundleIdentifier: app.id).first?.icon { Image(nsImage: icon).resizable().frame(width: 22, height: 22) }
                Text(app.name).fontWeight(.medium).lineLimit(1)
                Spacer(minLength: 5)
                Button { model.engine.update(app.id) { $0.volume = 1 } } label: { Text("\(Int(setting.volume * 100))%").monospacedDigit().foregroundStyle(muted) }.buttonStyle(.plain).accessibilityLabel("Reset \(app.name) volume to 100 percent")
                Action(title: setting.muted ? "Unmute" : "Mute") { model.engine.update(app.id) { $0.muted.toggle() } }
            }
            VolumeControl(label: "\(app.name) volume", value: model.setting(app.id, \.volume))
            routeButton(title: "Output", name: setting.output.map { uid in model.engine.devices.first { $0.uid == uid }?.name ?? "Unavailable · main output" } ?? "Use main output") { model.pickApp(app) }
            if model.engine.errors[app.id] != nil {
                Button { model.screen = "Permission" } label: { Text("Volume control unavailable · check audio access").font(.system(size: 11)).foregroundStyle(muted) }.buttonStyle(.plain)
            }
        }
    }
    var preferences: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                AccentSwitch(title: "Open at login", value: Binding(get: { model.screenshotMode ? true : SMAppService.mainApp.status == .enabled }, set: { enabled in
                    do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; model.revision += 1 }
                    catch { model.notify("Couldn’t update login setting") }
                }))
            }
            Text("Choose the main output for your Mac. An app’s own output choice overrides it. Call audio is processed only when you change that app’s volume, mute or output.").foregroundStyle(muted).font(.system(size: 12)).lineSpacing(3)
            HStack {
                Action(title: "Audio access") { model.screen = "Permission" }
                Action(title: "Reset volumes") { model.confirmation = ("All app volumes will return to 100% and be unmuted.", { for key in Array(model.engine.settings.apps.keys) { model.engine.update(key) { $0.volume = 1; $0.muted = false } } }) }
            }
            Spacer(minLength: 0)
        }
    }
    var permission: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Allow app volume control").font(.system(size: 17, weight: .semibold))
            Text("Open Privacy & Security, then enable suya-unduck in Screen & System Audio Recording. Reopen the app afterwards.").foregroundStyle(muted).lineSpacing(4)
            Action(title: "Open System Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!) }
            Text("This is for adjusting app audio. suya-unduck doesn’t record your microphone or upload audio.").font(.system(size: 12)).foregroundStyle(muted)
            Spacer(minLength: 0)
        }
    }
    var footer: some View {
        HStack {
            Action(title: "Copy support info") { if !model.screenshotMode { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.engine.diagnostics(), forType: .string) }; model.notify("Copied") }
            Spacer()
            Action(title: "Quit") { model.quit() }
        }.font(.system(size: 11))
    }
}
