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
    @Published var micDraft: Float?
    @Published var outputDraft: Float?
    private var outputWork: DispatchWorkItem?
    private var lastOutputWrite = Date.distantPast
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
        micDraft = value
        micWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            do { try Hardware.setInputVolume(value); self?.lastMicWrite = Date(); self?.micDraft = nil; self?.revision += 1 }
            catch { self?.micDraft = nil; self?.notify("This microphone cannot adjust its level") }
        }
        micWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, 0.05 - Date().timeIntervalSince(lastMicWrite)), execute: work)
    }
    func pickMain(input: Bool, systemSounds: Bool = false) {
        let choices = engine.devices.filter { input ? $0.input : $0.output }
        let current = screenshotMode ? (input ? UInt32(3) : UInt32(1)) : Hardware.defaultDevice(input: input, systemSounds: systemSounds)
        deviceChoice = DeviceChoice(title: input ? "Microphone" : systemSounds ? "System sounds" : "Main output", values: choices.map { (String($0.id), $0.name) }, selected: String(current), apply: { [weak self] selected in
            guard let id = UInt32(selected), let self else { return }
            if !self.screenshotMode { do { try Hardware.setDefault(id, input: input, systemSounds: systemSounds); self.engine.refresh() } catch { self.notify("Couldn’t change the device") } }
        })
    }
    func pickApp(_ app: AudioApp) {
        deviceChoice = DeviceChoice(title: "Output for \(app.name)", values: [("", "Use main output")] + engine.devices.filter(\.output).map { ($0.uid, $0.name) }, selected: engine.settings.apps[app.id]?.output ?? "", apply: { [weak self] value in self?.engine.update(app.id) { $0.output = value.isEmpty ? nil : value } })
    }
    func output(_ value: Float) {
        outputDraft = value; outputWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            do { try Hardware.setOutputVolume(value); self?.lastOutputWrite = Date(); self?.outputDraft = nil; self?.revision += 1 }
            catch { self?.outputDraft = nil; self?.notify("Adjust this output on the device") }
        }
        outputWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, 0.05 - Date().timeIntervalSince(lastOutputWrite)), execute: work)
    }
    func quit() { engine.quit(); NSApp.terminate(nil) }
    var volumeLock: Binding<Bool> {
        Binding(get: { self.engine.settings.duckApproved }, set: { self.engine.settings.duckApproved = $0; self.engine.persist(); self.engine.reconcile() })
    }
}
@available(macOS 14.2, *) struct AppView: View {
    @ObservedObject var model: Model
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var scheme: ColorScheme { model.engine.settings.theme == "Dark" ? .dark : model.engine.settings.theme == "Light" ? .light : systemScheme }
    private var muted: Color { Color.muted(for: scheme) }
    private var motion: Animation? { reduceMotion || model.screenshotMode ? nil : .spring(duration: 0.24, bounce: 0.12) }
    var body: some View {
        let _ = model.revision
        ZStack {
            VStack(spacing: 10) {
                header
                Group {
                    if model.screen == "Settings" { preferences }
                    else if model.screen == "Permission" { permission }
                    else { mixer }
                }.id(model.screen).transition(.opacity.combined(with: .offset(y: 4)))
                footer
            }.padding(16)
                .allowsHitTesting(model.confirmation == nil && model.deviceChoice == nil)
                .accessibilityHidden(model.confirmation != nil || model.deviceChoice != nil)
            if let toast = model.toast {
                VStack { Spacer(); Text(toast).font(.system(size: 11)).padding(10).background(Color.surface(for: scheme), in: Capsule()).shadow(radius: 8).padding(48) }
                    .allowsHitTesting(false).transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if let choice = model.deviceChoice {
                scrim { model.deviceChoice = nil }
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text(choice.title).fontWeight(.semibold); Spacer(); SymbolAction(symbol: "xmark", label: "Close device picker") { model.deviceChoice = nil } }
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(choice.values, id: \.0) { value in
                                Button { model.deviceChoice = nil; choice.apply(value.0) } label: {
                                    HStack { Text(value.1).lineLimit(2); Spacer(); Image(systemName: "checkmark").opacity(value.0 == choice.selected ? 1 : 0).foregroundStyle(Color.accent(for: scheme)) }
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(9)
                                        .background(Color.primary.opacity(value.0 == choice.selected ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 6))
                                }.buttonStyle(PickerRowStyle()).accessibilityLabel(value.1).accessibilityAddTraits(value.0 == choice.selected ? .isSelected : [])
                            }
                        }
                    }.frame(height: min(CGFloat(choice.values.count) * 39, 260))
                }.padding(14).frame(width: 310).background(Color.surface(for: scheme), in: RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 6).accessibilityAddTraits(.isModal)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
            if let confirm = model.confirmation {
                scrim { model.confirmation = nil }
                VStack(alignment: .leading, spacing: 14) {
                    Text("Reset app volumes?").fontWeight(.semibold)
                    Text(confirm.0).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                    HStack { Action(title: "Cancel") { model.confirmation = nil }; Spacer(); Action(title: "Reset") { model.confirmation = nil; confirm.1() } }
                }.padding(18).frame(width: 300).background(Color.surface(for: scheme), in: RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 6).accessibilityAddTraits(.isModal)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }.frame(width: 380).frame(maxHeight: .infinity)
            .foregroundStyle(scheme == .dark ? Color(hex: 0xEFEFF1) : Color(hex: 0x202126))
            .background(Color.panel(for: scheme), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.10)))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .font(.system(size: 12))
            .environment(\.colorScheme, scheme)
            .preferredColorScheme(model.engine.settings.theme == "System" ? nil : scheme)
            .animation(motion, value: model.screen)
            .animation(motion, value: model.deviceChoice != nil)
            .animation(motion, value: model.confirmation != nil)
            .animation(motion, value: model.toast)
    }
    func scrim(_ dismiss: @escaping () -> Void) -> some View {
        Color.black.opacity(0.32).contentShape(Rectangle()).onTapGesture(perform: dismiss).transition(.opacity)
    }
    var header: some View {
        HStack {
            if model.screen == "Mixer" {
                Text("suya-unduck").font(.system(size: 15, weight: .semibold)); Spacer()
                SymbolAction(symbol: "gearshape", label: "Settings") { model.screen = "Settings" }
            } else {
                Button { model.screen = "Mixer" } label: { Label("Back", systemImage: "chevron.left") }.buttonStyle(QuietButtonStyle())
                Spacer(); Text(model.screen).fontWeight(.semibold)
            }
        }.frame(height: 28)
    }
    var mixer: some View {
        // A single viewport for hardware AND apps: scrolling never gets trapped in a tiny app list.
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Card { AccentSwitch(title: "Keep volume during calls", value: model.volumeLock) }
                hardwareControls
                HStack { Text("APP VOLUME").fontWeight(.semibold).tracking(0.8); Spacer(); Text("0–200%") }.font(.system(size: 10)).foregroundStyle(muted)
                if visibleApps.isEmpty {
                    VStack(spacing: 6) {
                        Text("Play something").fontWeight(.medium)
                        Text("Apps appear here when they use audio.").foregroundStyle(muted)
                    }.frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    Card {
                        VStack(spacing: 0) {
                            ForEach(Array(visibleApps.enumerated()), id: \.element.id) { index, app in
                                if index > 0 { Divider().opacity(0.3).padding(.vertical, 6) }
                                appRow(app)
                            }
                        }.animation(motion, value: visibleApps.map(\.id))
                    }
                }
            }.padding(.trailing, 3).padding(.bottom, 3)
        }.scrollBounceBehavior(.basedOnSize)
    }
    func routeButton(title: String? = nil, name: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            if let title { Text(title).font(.system(size: 11)).foregroundStyle(muted).lineLimit(1).frame(width: 94, alignment: .leading) }
            Button(action: action) {
                HStack(alignment: .center, spacing: 6) {
                    Text(name).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(muted).frame(width: 12, height: 16, alignment: .center)
                }.frame(height: 18).contentShape(Rectangle())
            }.buttonStyle(QuietButtonStyle(compact: true)).accessibilityLabel("\(title ?? "App output"): \(name)")
        }
    }
    var hardwareControls: some View {
        let outputID = model.screenshotMode ? UInt32(1) : Hardware.defaultDevice()
        let systemID = model.screenshotMode ? UInt32(1) : Hardware.defaultDevice(systemSounds: true)
        let inputID = model.screenshotMode ? UInt32(3) : Hardware.defaultDevice(input: true)
        return Card {
            VStack(spacing: 6) {
                routeButton(title: "Main output", name: deviceName(outputID)) { model.pickMain(input: false) }
                if let level = model.screenshotMode ? Float(0.5) : model.outputDraft ?? Hardware.outputVolume() {
                    levelRow(label: "Main output volume", symbol: "speaker.wave.2", value: Binding(get: { model.screenshotMode ? 0.5 : model.outputDraft ?? Hardware.outputVolume() ?? 0 }, set: { model.output($0) }), percent: level, mutedValue: model.screenshotMode ? false : Hardware.outputMuted()) {
                        do { try Hardware.setOutputMuted(!(Hardware.outputMuted() ?? false)); model.revision += 1 } catch { model.notify("Output mute unavailable") }
                    }
                }
                routeButton(title: "System sounds", name: deviceName(systemID)) { model.pickMain(input: false, systemSounds: true) }
                Divider().opacity(0.3).padding(.vertical, 3)
                routeButton(title: "Microphone", name: deviceName(inputID)) { model.pickMain(input: true) }
                if let level = model.screenshotMode ? Float(0.65) : model.micDraft ?? Hardware.inputVolume() {
                    levelRow(label: "Microphone input level", symbol: "mic", value: Binding(get: { model.screenshotMode ? 0.65 : model.micDraft ?? Hardware.inputVolume() ?? 0 }, set: { model.microphone($0) }), percent: level, mutedValue: model.screenshotMode ? false : Hardware.inputMuted()) {
                        do { try Hardware.setInputMuted(!(Hardware.inputMuted() ?? false)); model.revision += 1 } catch { model.notify("Mic mute unavailable") }
                    }
                } else { Text("Fixed microphone level").font(.system(size: 10)).foregroundStyle(muted).frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
    }
    func deviceName(_ id: UInt32) -> String { model.engine.devices.first { $0.id == id }?.name ?? "Unavailable" }
    func levelRow(label: String, symbol: String, value: Binding<Float>, percent: Float, mutedValue: Bool?, action: @escaping () -> Void) -> some View {
        HStack(spacing: 7) {
            SymbolAction(symbol: mutedValue == true ? (symbol == "mic" ? "mic.slash" : "speaker.slash") : symbol, label: (mutedValue == true ? "Unmute " : "Mute ") + label, action: action).disabled(mutedValue == nil)
            VolumeControl(label: label, value: value, maximum: 1)
            Text("\(Int(percent * 100))%").font(.system(size: 10)).monospacedDigit().foregroundStyle(muted).frame(width: 32, alignment: .trailing)
        }
    }
    var visibleApps: [AudioApp] {
        model.engine.apps.filter { app in
            AppPresentation.showInMixer(isUserApp: model.screenshotMode || Hardware.isUserFacing(app), playing: app.playing, hasSavedVolume: model.engine.settings.apps[app.id] != nil, hasAudioSession: model.screenshotMode || !app.processes.isEmpty)
        }.sorted { if $0.playing != $1.playing { return $0.playing }; return $0.name < $1.name }
    }
    func appRow(_ app: AudioApp) -> some View {
        let setting = model.engine.settings.apps[app.id] ?? AppSetting()
        return VStack(spacing: 3) {
            HStack(spacing: 8) {
                if let icon = NSRunningApplication.runningApplications(withBundleIdentifier: app.id).first?.icon { Image(nsImage: icon).resizable().frame(width: 22, height: 22) }
                else { Image(systemName: "app").font(.system(size: 20)).foregroundStyle(muted).frame(width: 22, height: 22) }
                Text(app.name).fontWeight(.medium).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                routeButton(name: setting.output.map { uid in model.engine.devices.first { $0.uid == uid }?.name ?? "Unavailable · main" } ?? "Main output") { model.pickApp(app) }.frame(width: 148)
            }
            HStack(spacing: 7) {
                SymbolAction(symbol: setting.muted ? "speaker.slash" : "speaker.wave.2", label: "\(setting.muted ? "Unmute" : "Mute") \(app.name)") { model.engine.update(app.id) { $0.muted.toggle() } }
                VolumeControl(label: "\(app.name) volume", value: model.setting(app.id, \.volume))
                Button { withAnimation(motion) { model.engine.update(app.id) { $0.volume = 1 } } } label: { Text("\(Int(setting.volume * 100))%").font(.system(size: 10)).monospacedDigit().foregroundStyle(muted).frame(width: 32, alignment: .trailing) }.buttonStyle(.plain).accessibilityLabel("Reset \(app.name) volume to 100 percent")
            }
            if model.engine.errors[app.id] != nil {
                Button { model.screen = "Permission" } label: { Text("Check audio access").font(.system(size: 10)).foregroundStyle(muted) }.buttonStyle(.plain)
            }
        }.padding(.vertical, 2)
    }
    var preferences: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card {
                    AccentSwitch(title: "Open at login", value: Binding(get: { model.screenshotMode ? true : SMAppService.mainApp.status == .enabled }, set: { enabled in
                        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; model.revision += 1 }
                        catch { model.notify("Couldn’t update login setting") }
                    }))
                }
                Text("An app’s output choice overrides Main output. System sounds use their own selected device. Call audio is processed only when you adjust that app.").foregroundStyle(muted).font(.system(size: 11)).lineSpacing(3)
                HStack {
                    Action(title: "Audio access") { model.screen = "Permission" }
                    Action(title: "Reset volumes") { model.confirmation = ("All app volumes will return to 100% and be unmuted.", { for key in Array(model.engine.settings.apps.keys) { model.engine.update(key) { $0.volume = 1; $0.muted = false } } }) }
                }
            }
        }
    }
    var permission: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Allow app volume control").font(.system(size: 16, weight: .semibold))
                Text("Enable suya-unduck in Privacy & Security → Screen & System Audio Recording. macOS may request this again after an update.").foregroundStyle(muted).lineSpacing(3)
                Action(title: "Open System Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!) }
                Text("Audio stays on your Mac. Your microphone is not recorded.").font(.system(size: 11)).foregroundStyle(muted)
            }
        }
    }
    var footer: some View {
        HStack {
            Action(title: "Copy support info") { if !model.screenshotMode { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.engine.diagnostics(), forType: .string) }; model.notify("Copied") }
            Spacer()
            Action(title: "Quit") { model.quit() }
        }.font(.system(size: 10))
    }
}
