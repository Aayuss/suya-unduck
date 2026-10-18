import AppKit
import SwiftUI
import Combine

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
@available(macOS 14.2, *) final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var panel: KeyablePanel!
    private var model: Model!
    private var monitors: [Any] = []
    private var screenObservation: AnyCancellable?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 580), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
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
                if self.model.confirmation != nil { self.model.confirmation = nil } else { self.close() }; return nil
            }
            if e.type != .keyDown && e.window != self.panel && e.window != self.item.button?.window { self.close() }
            return e
        }) { monitors.append(monitor) }
        NotificationCenter.default.addObserver(self, selector: #selector(close), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if CommandLine.arguments.contains("--screenshots") { renderScreenshots(); NSApp.terminate(nil) }
        else if !UserDefaults.standard.bool(forKey: "onboarded") { model.screen = "Permission"; open(); UserDefaults.standard.set(true, forKey: "onboarded") }
    }
    @objc func clicked() {
        if panel.isVisible { close(); return }
        let event = NSApp.currentEvent
        model.screen = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true ? "Quick" : "Mixer"
        open()
    }
    func open() {
        guard let button = item.button, let window = button.window else { return }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let height = min(CGFloat(model.screen == "Quick" ? 300 : 580), visible.height - 16)
        panel.setFrame(NSRect(x: min(max(rect.midX - 190, visible.minX + 8), visible.maxX - 388), y: max(visible.minY + 8, rect.minY - height - 6), width: 380, height: height), display: true)
        panel.makeKeyAndOrderFront(nil); model.meters(true)
    }
    @objc func close() { panel?.orderOut(nil); model?.meters(false) }
    func applicationWillTerminate(_ notification: Notification) { if !CommandLine.arguments.contains("--screenshots") { model?.engine.quit() }; monitors.forEach { NSEvent.removeMonitor($0) } }
    func renderScreenshots() {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SUYA_SCREENSHOT_DIR"] ?? NSTemporaryDirectory()).appendingPathComponent("screenshots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for theme in ["Dark", "Light"] {
            model.engine.settings.theme = theme
            for screen in ["Mixer", "Settings", "Diagnostics", "Permission", "Quick"] {
                model.screen = screen
                let host = NSHostingView(rootView: AppView(model: model)); host.frame = NSRect(x: 0, y: 0, width: 380, height: screen == "Quick" ? 300 : 580)
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
