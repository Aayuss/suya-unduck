import SwiftUI
import AppKit
import ServiceManagement
import MixerCore
import MixerEngine

@available(macOS 14.2, *) final class Model: ObservableObject {
    let engine: Engine
    @Published var revision = 0
    @Published var screen = "Mixer"
    @Published var toast: String?
    @Published var confirmation: (String, () -> Void)?
    var screenshotMode = false
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
    func meters(_ visible: Bool) {} // No UI polling: volume controls need no live meters.
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
                    HStack { Text("APP VOLUME").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(muted); Spacer(); Text("0–200%").font(.system(size: 10)).foregroundStyle(muted) }
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            if visibleApps.isEmpty {
                                VStack(spacing: 10) {
                                    Text("Play something").font(.system(size: 16, weight: .medium))
                                    Text("Apps appear here when they play audio.\nThen adjust each app’s volume.").multilineTextAlignment(.center).foregroundStyle(muted).lineSpacing(4)
                                }.frame(maxWidth: .infinity).padding(.vertical, 40)
                            }
                            ForEach(visibleApps) { app in appRow(app) }
                        }.padding(.bottom, 4)
                    }.frame(maxHeight: .infinity)
                }
                footer
            }.padding(20).allowsHitTesting(model.confirmation == nil).accessibilityHidden(model.confirmation != nil)
            if let toast = model.toast {
                VStack { Spacer(); Text(toast).padding(12).background(Color.surface(for: scheme), in: Capsule()).shadow(radius: 8).padding(18) }.allowsHitTesting(false)
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
        }.frame(width: 360, height: model.screen == "Settings" ? 330 : model.screen == "Permission" ? 390 : 480)
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
                Text(model.engine.settings.duckApproved ? (model.engine.callActive ? (model.engine.unduckStatus == "active" ? "Call detected · keeping media volume steady" : "Call detected · volume control needs checking") : "Ready for FaceTime, WhatsApp and other calls") : "Off · macOS can lower media during calls")
                    .font(.system(size: 11)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    var visibleApps: [AudioApp] {
        model.engine.apps.filter { app in
            guard !app.protected, !model.engine.settings.extraProtected.contains(app.id) else { return false }
            let userApp = model.screenshotMode || NSRunningApplication.runningApplications(withBundleIdentifier: app.id).contains { $0.activationPolicy == .regular }
            return AppPresentation.showInMixer(isUserApp: userApp, playing: app.playing, hasSavedVolume: model.engine.settings.apps[app.id] != nil)
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
            Text("Call audio stays untouched so you can keep hearing the other person. Your music and video apps get their own volume controls.").foregroundStyle(muted).font(.system(size: 12)).lineSpacing(3)
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
