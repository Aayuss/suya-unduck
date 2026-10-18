import AppKit
import SwiftUI
import Combine
import CAtomics

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
@available(macOS 14.2, *) final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var panel: KeyablePanel!
    private var model: Model!
    private var monitors: [Any] = []
    private var terminationSignal: DispatchSourceSignal?
    private var screenObservation: AnyCancellable?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        signal(SIGTERM, SIG_IGN)
        let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termination.setEventHandler { NSApp.terminate(nil) }; termination.resume(); terminationSignal = termination
        model = Model(preview: CommandLine.arguments.contains("--screenshots"))
        item = NSStatusBar.system.statusItem(withLength: 30)
        item.button?.toolTip = "suya-unduck"
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"), let original = NSImage(contentsOf: url) {
            // Template images use the supplied alpha and adapt to light/dark menu bars.
            let icon = NSImage(size: NSSize(width: 27, height: 18), flipped: false) { rect in
                original.draw(in: rect, from: NSRect(x: original.size.width * 0.21, y: original.size.height * 0.25, width: original.size.width * 0.60, height: original.size.height * 0.46), operation: .sourceOver, fraction: 1)
                return true
            }
            icon.isTemplate = true; item.button?.image = icon
        }
        item.button?.target = self; item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 640), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]; panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: AppView(model: model))
        screenObservation = model.$screen.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.panel.isVisible else { return }
                self.open()
            }
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in self?.close() }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown], handler: { [weak self] e in
            guard let self else { return e }
            if e.type == .keyDown && e.keyCode == 53 {
                if self.model.deviceChoice != nil { self.model.deviceChoice = nil } else if self.model.confirmation != nil { self.model.confirmation = nil } else { self.close() }; return nil
            }
            if e.type != .keyDown && e.window != self.panel && e.window != self.item.button?.window { self.close() }
            return e
        }) { monitors.append(monitor) }
        NotificationCenter.default.addObserver(self, selector: #selector(close), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if CommandLine.arguments.contains("--screenshots") { renderScreenshots(); NSApp.terminate(nil) }
        else if CommandLine.arguments.contains("--show") { open() }
        else if !UserDefaults.standard.bool(forKey: "onboarded") { model.screen = "Permission"; open(); UserDefaults.standard.set(true, forKey: "onboarded") }
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--verify-volume"), i + 1 < args.count,
           let report = args.firstIndex(of: "--verify-report"), report + 1 < args.count {
            verifyVolume(bundle: args[i + 1], reportURL: URL(fileURLWithPath: args[report + 1]))
        }
    }
    @objc func clicked() {
        if panel.isVisible { close(); return }
        let event = NSApp.currentEvent
        model.screen = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true ? "Settings" : "Mixer"
        open()
    }
    func open() {
        guard let button = item.button, let window = button.window else { return }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let height = min(CGFloat(model.screen == "Settings" ? 330 : model.screen == "Permission" ? 390 : 640), visible.height - 16)
        panel.setFrame(NSRect(x: min(max(rect.midX - 180, visible.minX + 8), visible.maxX - 368), y: max(visible.minY + 8, rect.minY - height - 6), width: 360, height: height), display: true)
        panel.makeKeyAndOrderFront(nil); model.meters(true)
    }
    @objc func close() { panel?.orderOut(nil); model?.meters(false) }
    func applicationWillTerminate(_ notification: Notification) { if !CommandLine.arguments.contains("--screenshots") { model?.engine.quit() }; monitors.forEach { NSEvent.removeMonitor($0) } }
    /// Opt-in engineering smoke test on this app's actual signed audio path.
    /// Saves metadata only; restores the user's exact settings after four seconds.
    func verifyVolume(bundle: String, reportURL: URL) {
        let previous = model.engine.settings.apps[bundle]
        var results: [[String: Any]] = []
        func sample(_ stage: String) {
            let pipeline = self.model.engine.pipelines[bundle]
            results.append(["stage": stage, "sourcePlaying": self.model.engine.apps.first { $0.id == bundle }?.playing ?? false,
                            "pipeline": pipeline != nil, "callbacks": pipeline.map { am_get_callbacks($0.shared) } ?? 0,
                            "peak": pipeline.map { am_load_peak($0.shared) } ?? 0,
                            "formatErrors": pipeline.map { am_get_format_errors($0.shared) } ?? 0,
                            "error": self.model.engine.errors[bundle] ?? ""])
        }
        model.engine.update(bundle) { $0.volume = 0.8; $0.muted = false }
        let deadline = Date().addingTimeInterval(90)
        func beginWhenReady() {
            guard self.model.engine.pipelines[bundle] != nil || Date() >= deadline else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { beginWhenReady() }
                return
            }
            self.model.engine.refresh()
            self.model.engine.update(bundle) { $0.volume = 0.8; $0.muted = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                sample("80-percent")
                self.model.engine.update(bundle) { $0.volume = 0.5 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    sample("50-percent")
                    if let previous { self.model.engine.settings.apps[bundle] = previous } else { self.model.engine.settings.apps.removeValue(forKey: bundle) }
                    self.model.engine.persist(); self.model.engine.reconcile()
                    let report: [String: Any] = ["samples": results, "restored": true, "unduck": self.model.engine.unduckStatus]
                    if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: reportURL, options: .atomic) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        guard let view = self.panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                        view.cacheDisplay(in: view.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: reportURL.deletingLastPathComponent().appendingPathComponent("live-panel-0.3.0.png"))
                    }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { beginWhenReady() }
    }
    func renderScreenshots() {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SUYA_SCREENSHOT_DIR"] ?? NSTemporaryDirectory()).appendingPathComponent("screenshots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for theme in ["Dark", "Light"] {
            model.engine.settings.theme = theme
            for screen in ["Mixer", "Settings", "Permission", "Dialog", "Empty", "Outputs"] {
                model.engine.loadPreview(); model.engine.settings.theme = theme
                model.confirmation = nil; model.deviceChoice = nil
                model.screen = screen == "Dialog" ? "Settings" : "Mixer"
                if screen == "Settings" || screen == "Permission" { model.screen = screen }
                if screen == "Dialog" { model.confirmation = ("All app volumes will return to 100% and be unmuted.", {}) }
                if screen == "Outputs" { model.pickApp(model.engine.apps[0]) }
                if screen == "Empty" { model.engine.loadEmptyPreview() }
                let host = NSHostingView(rootView: AppView(model: model)); host.frame = NSRect(x: 0, y: 0, width: 360, height: model.screen == "Settings" ? 330 : model.screen == "Permission" ? 390 : 640)
                host.layoutSubtreeIfNeeded()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("\(screen.lowercased())-\(theme.lowercased()).png"))
            }
        }
    }
}
let app = NSApplication.shared
if #available(macOS 14.2, *) {
    let delegate = AppDelegate(); app.delegate = delegate; app.run(); withExtendedLifetime(delegate) {}
} else { fputs("suya-unduck requires macOS 14.2 or later.\n", stderr); exit(1) }
