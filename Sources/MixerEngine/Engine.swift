import Foundation
import CoreAudio
import AppKit
import MixerCore
import CAtomics

@available(macOS 14.2, *) public final class Engine {
    // All control state is confined to the main thread. RT memory uses C atomics only.
    public private(set) var apps: [AudioApp] = []
    public private(set) var devices: [AudioDevice] = []
    public private(set) var callActive = false
    public private(set) var errors: [String: String] = [:]
    public private(set) var pipelines: [String: TapPipeline] = [:]
    public var settings: Settings
    public var changed: (() -> Void)?
    private var systemListeners: [CAListener] = []
    private var processListeners: [CAListener] = []
    private var deviceListeners: [CAListener] = []
    private var discovery: DispatchSourceTimer?
    private var observedProcesses = Set<UInt32>()
    private var observedDevices: [AudioDevice] = []
    private struct PendingRequest: Equatable {
        let processes: [UInt32]
        let output: UInt32
        let desired: DesiredPipeline
    }
    private var pending: [String: (UUID, PendingRequest)] = [:]
    private let setupQueue = DispatchQueue(label: "com.ayus.suya-unduck.setup", qos: .userInitiated)
    private var shuttingDown = false
    private var snapshotSignature = ""
    private var watchdog: DispatchSourceTimer?
    private var failures: [String: [Date]] = [:]
    private var lastCounts: [String: (UInt64, Int)] = [:]
    private let duck = DuckGuard()
    private var duckDevices = Set<UInt32>()
    private var sleeping = false
    private var saveWork: DispatchWorkItem?
    private var lastOutput: [String: Date] = [:]
    private var idleWork: DispatchWorkItem?
    private var reconcileWork: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    public private(set) var logLines: [String] = []
    public let settingsURL: URL
    public init(preview: Bool = false) {
        settingsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/suya-unduck/settings.json")
        if preview { settings = Settings(); return }
        if let data = try? Data(contentsOf: settingsURL) {
            do {
                settings = try JSONDecoder().decode(Settings.self, from: data)
                if settings.interfaceVersion < 2 {
                    let backup = settingsURL.deletingLastPathComponent().appendingPathComponent("settings.pre-0.2.0.json")
                    if !FileManager.default.fileExists(atPath: backup.path) { try data.write(to: backup, options: .atomic) }
                    settings.simplifyInterface()
                }
            }
            catch { try? FileManager.default.copyItem(at: settingsURL, to: settingsURL.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")); settings = Settings() }
        } else { settings = Settings() }
    }
    public func log(_ text: String) {
        EventLog.write(text)
        logLines.append("\(ISO8601DateFormatter().string(from: Date())) \(text)")
        if logLines.count > 200 { logLines.removeFirst(logLines.count - 200) }
    }
    /// Deterministic rendering data; no device changes, taps, IO or settings writes.
    public func loadPreview() {
        settings = Settings(); settings.duckApproved = true
        devices = [AudioDevice(id: 1, uid: "preview-speakers", name: "Mac speakers", rate: 48000, input: false, output: true), AudioDevice(id: 2, uid: "preview-headphones", name: "Headphones", rate: 48000, input: false, output: true), AudioDevice(id: 3, uid: "preview-mic", name: "Built-in microphone", rate: 48000, input: true, output: false)]
        apps = [AudioApp(id: "com.google.Chrome", name: "Google Chrome", processes: [], playing: true, recording: false), AudioApp(id: "com.spotify.client", name: "Spotify", processes: [], playing: true, recording: false), AudioApp(id: "net.whatsapp.WhatsApp", name: "WhatsApp", processes: [], playing: false, recording: false)]
        var chrome = AppSetting(); chrome.volume = 0.58
        var spotify = AppSetting(); spotify.volume = 0.84; spotify.output = "preview-headphones"
        settings.apps = ["com.google.Chrome": chrome, "com.spotify.client": spotify]
    }
    public func loadEmptyPreview() { apps = []; settings.apps = [:] }
    public func start() {
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyProcessObjectList] {
            systemListeners.append(CAListener(object: .system, address: AudioObjectID.system.addr(selector), queue: .main) { [weak self] in self?.refresh() })
        }
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.sleeping = true; self?.stop() })
        observers.append(nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.sleeping = false; self?.refresh() } })
        duck.log = { [weak self] in self?.log($0) }
        duck.onStatusChange = { [weak self] in self?.changed?() }
        refresh(); persist()
    }
    public func refresh() {
        guard !sleeping, !shuttingDown else { return }
        if discovery == nil {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
            timer.setEventHandler { [weak self] in self?.refresh() }
            discovery = timer; timer.resume()
        }
        apps = Hardware.apps(); devices = Hardware.devices()
        let processIDs = Set(apps.flatMap(\.processes))
        if processIDs != observedProcesses {
        observedProcesses = processIDs
        processListeners.removeAll()
        for app in apps { for id in app.processes { for selector in [kAudioProcessPropertyIsRunningInput, kAudioProcessPropertyIsRunningOutput] {
            processListeners.append(CAListener(object: id, address: id.addr(selector), queue: .main) { [weak self] in self?.refresh() })
        } } }
        }
        if devices != observedDevices {
        observedDevices = devices
        deviceListeners.removeAll()
        for device in devices {
            for selector in [kAudioDevicePropertyNominalSampleRate, kAudioDevicePropertyDeviceIsAlive] {
                deviceListeners.append(CAListener(object: device.id, address: device.id.addr(selector), queue: .main) { [weak self] in self?.stop(); self?.refresh() })
            }
            for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
                deviceListeners.append(CAListener(object: device.id, address: device.id.addr(selector, kAudioObjectPropertyScopeInput, kAudioObjectPropertyElementWildcard), queue: .main) { [weak self] in self?.changed?() })
            }
        }
        }
        reconcile()
    }
    public func update(_ key: String, _ body: (inout AppSetting) -> Void) {
        var setting = settings.apps[key] ?? AppSetting(); body(&setting); settings.apps[key] = setting
        var instantGain = setting.muted ? Float(0) : GainMath.gain(forSlider: setting.volume)
        if settings.compensationEnabled && callActive { instantGain *= min(3, max(1, settings.compensation)) }
        pipelines[key]?.setGain(instantGain)
        persist(); reconcile()
    }
    public func persist() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    private func save() {
        do { try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true); try JSONEncoder().encode(settings).write(to: settingsURL, options: .atomic) }
        catch { log("Settings save failed: \(error)") }
    }
    public func reconcile() {
        guard !sleeping else { return }
        let browsers = ["com.google.Chrome", "com.apple.Safari", "org.mozilla.firefox", "com.microsoft.edgemac", "company.thebrowser.Browser", "com.brave.Browser"]
        let wasCallActive = callActive
        let activeCalls = apps.filter { app in
            let foregroundApp = NSRunningApplication.runningApplications(withBundleIdentifier: app.id).contains { $0.activationPolicy == .regular }
            return CallActivity.isCall(knownCallApp: Protection.isProtected(app.id), browser: browsers.contains(app.id), userApp: foregroundApp, playing: app.playing, recording: app.recording)
        }
        callActive = settings.callMode == "Always" || (settings.callMode == "Auto" && !activeCalls.isEmpty)
        if callActive != wasCallActive { log("Call \(callActive ? "detected" : "ended"): \(activeCalls.map(\.name).joined(separator: ", "))") }

        let output = Hardware.defaultDevice()
        let defaultUID = devices.first { $0.id == output }?.uid ?? ""
        let available = Set(devices.filter(\.output).map(\.uid))
        idleWork?.cancel()
        var nextBoundary: Double?
        let keys = Set(apps.map(\.id))
        for key in Set(pipelines.keys).union(pending.keys) where !keys.contains(key) { remove(key) }
        for app in apps {
            let setting = settings.apps[app.id] ?? AppSetting()
            let protected = app.protected || settings.extraProtected.contains(app.id) || !Hardware.isUserFacing(app)
            if app.playing { lastOutput[app.id] = Date() }
            let silentSeconds = app.playing ? 0 : lastOutput[app.id].map { Date().timeIntervalSince($0) } ?? .infinity
            if !app.playing && silentSeconds.isFinite && settings.resumePolicy != "keep-running" {
                for threshold in [settings.idleStopSeconds, settings.destroyIdleSeconds] where threshold > silentSeconds {
                    nextBoundary = min(nextBoundary ?? .infinity, threshold - silentSeconds)
                }
            }
            guard let desired = Decision.desired(setting: setting, global: settings, protected: protected, playing: app.playing, silentSeconds: silentSeconds, call: callActive, defaultOutput: defaultUID, available: available),
                  let device = devices.first(where: { $0.uid == desired.outputUID }) else { remove(app.id); continue }
            let recent = (failures[app.id] ?? []).filter { Date().timeIntervalSince($0) < 60 }
            failures[app.id] = recent
            if recent.count >= 3 {
                nextBoundary = min(nextBoundary ?? .infinity, max(0.1, 60 - Date().timeIntervalSince(recent[0])))
                continue
            }
            let gain = desired.gain
            if let p = pipelines[app.id], p.processObjectIDs != app.processes || p.outputDeviceID != device.id { remove(app.id) }
            if pipelines[app.id] == nil {
                let request = PendingRequest(processes: app.processes, output: device.id, desired: desired)
                if let existing = pending[app.id], existing.1 == request { continue }
                let token = UUID(); pending[app.id] = (token, request)
                // Core Audio can wait for a system permission prompt here. Never block the panel.
                setupQueue.async { [weak self] in
                    let result = Result {
                        let p = try TapPipeline(groupKey: app.id, processObjectIDs: app.processes, outputDeviceID: device.id, outputDeviceUID: device.uid, initialGain: gain, controlQueue: .main)
                        if desired.running { try p.start() }
                        return p
                    }
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.pending[app.id]?.0 == token, !self.sleeping, !self.shuttingDown else {
                            if case .success(let pipeline) = result { DispatchQueue.global(qos: .utility).async { pipeline.destroy() } }
                            return
                        }
                        self.pending[app.id] = nil
                        switch result {
                        case .success(let p):
                            p.onNeedsRebuild = { [weak self] reason in self?.log(reason); self?.remove(app.id); self?.schedule() }
                            self.pipelines[app.id] = p; self.errors[app.id] = nil
                            self.log("Started \(app.name) → \(device.name), layout=\(String(describing: p.layout))")
                        case .failure(let error):
                            self.errors[app.id] = String(describing: error)
                            self.failures[app.id, default: []].append(Date()); self.log("\(app.name): \(error)")
                        }
                        self.reconcile()
                    }
                }
            } else if let p = pipelines[app.id] {
                p.setGain(gain)
                do { if desired.running { try p.start() } else { p.stop(); lastCounts[app.id] = nil } }
                catch { errors[app.id] = String(describing: error); failures[app.id, default: []].append(Date()); remove(app.id) }
            }
        }
        if let nextBoundary {
            let work = DispatchWorkItem { [weak self] in self?.reconcile() }; idleWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.05, nextBoundary), execute: work)
        }
        let desiredDuck = settings.duckApproved ? Set([output] + pipelines.values.map(\.aggregateID) + pipelines.values.map(\.outputDeviceID)) : Set<UInt32>()
        if desiredDuck != duckDevices { duck.stop(); duckDevices = desiredDuck; if !desiredDuck.isEmpty { duck.start(devices: Array(desiredDuck), approved: true) } }
        if !pipelines.values.contains(where: \.isRunning) { watchdog?.cancel(); watchdog = nil }
        else if watchdog == nil {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + 0.25, repeating: 0.25, leeway: .milliseconds(25))
            timer.setEventHandler { [weak self] in self?.checkHealth() }; watchdog = timer; timer.resume()
        }
        publishSnapshot()
        changed?()
    }
    private func schedule() {
        reconcileWork?.cancel(); let work = DispatchWorkItem { [weak self] in self?.refresh() }; reconcileWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    private func checkHealth() {
        for key in Array(pipelines.keys) {
            guard let p = pipelines[key], p.isRunning else { continue }
            let count = am_get_callbacks(p.shared)
            let old = lastCounts[key] ?? (0, 0)
            let stalled = old.0 == count ? old.1 + 1 : 0
            lastCounts[key] = (count, stalled)
            if am_is_failed(p.shared) != 0 || stalled >= 8 {
                errors[key] = "Processing stopped; playing normally."
                failures[key, default: []].append(Date()); log("Fail-safe teardown: \(key)"); remove(key)
            }
        }
        if !pipelines.values.contains(where: \.isRunning) { watchdog?.cancel(); watchdog = nil }
        changed?()
    }
    private func remove(_ key: String) { pending[key] = nil; if let p = pipelines.removeValue(forKey: key) { p.onNeedsRebuild = nil; setupQueue.async { p.destroy() }; log("Stopped \(key)") }; lastCounts[key] = nil }
    public func stop() { pending.removeAll(); discovery?.cancel(); discovery = nil; idleWork?.cancel(); reconcileWork?.cancel(); duck.stop(); duckDevices = []; for key in Array(pipelines.keys) { remove(key) }; watchdog?.cancel(); watchdog = nil }
    public func quit() { shuttingDown = true; saveWork?.cancel(); save(); stop() }
    private func publishSnapshot() {
        let rows: [[String: Any]] = apps.map { app in
            ["id": app.id, "name": app.name, "playing": app.playing, "recording": app.recording,
             "processes": app.processes, "volume": settings.apps[app.id]?.volume ?? 1,
             "route": settings.apps[app.id]?.output ?? "main-output",
             "pipeline": pipelines[app.id] != nil, "error": errors[app.id] ?? ""]
        }
        let data: [String: Any] = ["version": "0.3.0", "apps": rows, "unduck": duck.status, "enabled": settings.duckApproved,
            "mainOutput": Hardware.defaultDevice(), "input": Hardware.defaultDevice(input: true)]
        guard let json = try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys]),
              let signature = String(data: json, encoding: .utf8), signature != snapshotSignature else { return }
        snapshotSignature = signature
        // Local diagnostics only: no samples or microphone recordings are stored.
        try? FileManager.default.createDirectory(at: EventLog.folder, withIntermediateDirectories: true)
        try? json.write(to: EventLog.folder.appendingPathComponent("runtime.json"), options: .atomic)
    }
    public var unduckStatus: String { duck.status }
    public func diagnostics() -> String {
        "suya-unduck\n\(ProcessInfo.processInfo.operatingSystemVersionString)\nCall: \(callActive)\nKeep volume: \(settings.duckApproved), state: \(duck.status)\n" + devices.map { "\($0.name): \($0.rate) Hz [\($0.uid)]" }.joined(separator: "\n") + "\n" + pipelines.map { key, p in "\(key): callbacks=\(am_get_callbacks(p.shared)), errors=\(am_get_format_errors(p.shared)), peak=\(am_load_peak(p.shared)), layout=\(String(describing: p.layout)), firstCallbacks=\(p.probeReport())" }.joined(separator: "\n") + "\n" + errors.description + "\n" + logLines.joined(separator: "\n")
    }
}
