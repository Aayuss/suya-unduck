import Foundation
import CoreAudio
import MixerCore
import MixerEngine
import CAtomics

func option(_ flag: String, _ fallback: String) -> String {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return fallback }; return args[i+1]
}
func run(_ seconds: Double, tick: (() -> Void)? = nil) {
    var stopped = false
    signal(SIGINT, SIG_IGN); signal(SIGTERM, SIG_IGN)
    let signals = [SIGINT, SIGTERM].map { sig -> DispatchSourceSignal in
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler { stopped = true }; source.resume(); return source
    }
    let end = Date().addingTimeInterval(seconds)
    while !stopped && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.25)); tick?() }
    signals.forEach { $0.cancel() }
}
@available(macOS 14.2, *) func execute() throws {
    let command = CommandLine.arguments.dropFirst().first ?? "help"
    let minutes = min(240, max(0.01, Double(option("--minutes", "3")) ?? 3))
    let bundle = option("--bundle", "com.google.Chrome")
    func stamp(_ s: String) { print("\(ISO8601DateFormatter().string(from: Date())) \(s)") }
    switch command {
    case "env":
        print("suya-unduck lab · \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("SDKROOT=\(ProcessInfo.processInfo.environment["SDKROOT"] ?? "see build report")")
        print("HAL plug-ins: \((try? FileManager.default.contentsOfDirectory(atPath: "/Library/Audio/Plug-Ins/HAL")) ?? [])")
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/bin/ps"); task.arguments = ["-axo", "comm="]
        let pipe = Pipe(); task.standardOutput = pipe; try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").filter { line in ["soundsource", "loopback", "blackhole", "audio hijack", "loom", "parrot"].contains { line.lowercased().contains($0) } }
        print(lines.joined(separator: "\n"))
        if lines.contains(where: { $0.lowercased().contains("soundsource") }) { print("WARNING: Quit SoundSource before any tap or anti-ducking test.") }
    case "probe-layout":
        print(try inspectTapLayout())
    case "devices":
        for d in Hardware.devices() {
            print("\(d.id) \(d.name) \(d.rate) Hz input=\(d.input) output=\(d.output) UID=\(d.uid)")
            print("duck output: \((try? DuckGuard.read(d.id)).map(String.init(describing:)) ?? "unsupported")")
        }
    case "processes":
        for a in Hardware.apps() { print("\(a.id) \(a.name) processes=\(a.processes) output=\(a.playing) input=\(a.recording) protected=\(a.protected) userApp=\(Hardware.isUserFacing(a))") }
    case "watch-duck":
        let devices = Hardware.devices().filter(\.output)
        var listeners: [CAListenerToken] = []
        for d in devices {
            listeners.append(CAListenerToken(id: d.id) { stamp("LISTENER \(d.name) \((try? DuckGuard.read(d.id)) ?? [])") })
        }
        var last = Date.distantPast
        run(minutes * 60) { if Date().timeIntervalSince(last) >= 1 { last = Date(); for d in devices { stamp("SNAPSHOT \(d.name) \((try? DuckGuard.read(d.id)) ?? [])") } } }
        withExtendedLifetime(listeners) {}
    case "method", "layout", "soak", "resume-test", "fault-inject":
        let method = command == "method" ? (CommandLine.arguments.dropFirst(2).first ?? "replay") : "replay"
        guard ["replay", "duck-device", "replay+duck"].contains(method) else { throw LabError("Unknown method") }
        let duck = DuckGuard(); duck.log = stamp
        defer { duck.stop() }
        let output = Hardware.defaultDevice()
        guard let defaultDevice = Hardware.devices().first(where: { $0.id == output }) else { throw LabError("No output device") }
        if method != "replay" && !CommandLine.arguments.contains("--i-approve-duck-writes") { throw LabError("This experimental device-wide write requires --i-approve-duck-writes") }
        if method == "duck-device" {
            print("WARNING: Writing an undocumented setting affecting all apps on \(defaultDevice.name). Conditional restore on exit.")
            duck.start(devices: [output], approved: true); run(minutes * 60); return
        }
        guard let app = Hardware.apps().first(where: { $0.id == bundle }) else { throw LabError("No audio process for \(bundle). Play audio first.") }
        guard !app.protected else { throw LabError("Refusing to tap a protected call/microphone app") }
        let gain = min(2, max(0, Float(option("--gain", "1")) ?? 1))
        let outputs = command == "layout" ? Hardware.devices().filter(\.output) : [defaultDevice]
        for device in outputs {
            print("Building \(app.name) → \(device.name), \(device.rate) Hz")
            let p = try TapPipeline(groupKey: app.id, processObjectIDs: app.processes, outputDeviceID: device.id, outputDeviceUID: device.uid, initialGain: gain, controlQueue: .main)
            defer { p.destroy() }
            try p.start()
            if method == "replay+duck" { duck.start(devices: [output, p.aggregateID], approved: true) }
            if command == "layout" { run(0.5); print("callbacks=\(am_get_callbacks(p.shared)), format_errors=\(am_get_format_errors(p.shared))"); print(p.probeReport()); continue }
            if command == "fault-inject" {
                run(0.5); let start = Date(); am_inject_fault(p.shared)
                run(0.25); let detected = am_is_failed(p.shared) != 0; p.destroy()
                print("Injected failure detected=\(detected). Teardown completed in \(Date().timeIntervalSince(start) * 1000) ms. This measures teardown, NOT audible recovery; an external recording is required."); continue
            }
            let strategy = option("--strategy", "keep-running")
            var lastLog = Date.distantPast, silentSince: Date?, stopped = false, destroyed = false
            run(minutes * 60) {
                if destroyed { return }
                if am_is_failed(p.shared) != 0 && !destroyed { p.destroy(); destroyed = true; stamp("FAIL-SAFE: format error; app now on original path") }
                if destroyed { return }
                if command == "resume-test" {
                    let playing = Hardware.apps().first { $0.id == bundle }?.playing ?? false
                    if playing {
                        silentSince = nil
                        if stopped { do { try p.start(); stopped = false; stamp("IO resumed. Check for a full-volume burst.") } catch { stamp("Resume failed: \(error)") } }
                    } else {
                        if silentSince == nil { silentSince = Date() }
                        if Date().timeIntervalSince(silentSince!) > 10 && !stopped {
                            if strategy == "stop-io" { p.stop(); stopped = true; stamp("IO stopped after silence") }
                            if strategy == "destroy" { p.destroy(); destroyed = true; stamp("Pipeline destroyed. Rerun to resume processing; original audio is now active.") }
                        }
                    }
                }
                if Date().timeIntervalSince(lastLog) >= (command == "soak" ? 30 : 1) {
                    lastLog = Date(); stamp("callbacks=\(am_get_callbacks(p.shared)) peak=\(am_load_peak(p.shared)) format_errors=\(am_get_format_errors(p.shared))")
                }
            }
        }
    default:
        print("""
        suya-unduck-lab env | devices | processes
        suya-unduck-lab watch-duck --minutes 2
        suya-unduck-lab method replay --bundle com.google.Chrome --minutes 2
        suya-unduck-lab method duck-device --minutes 2 --i-approve-duck-writes
        suya-unduck-lab method replay+duck --bundle com.google.Chrome --minutes 2 --i-approve-duck-writes
        suya-unduck-lab layout --bundle com.google.Chrome
        suya-unduck-lab resume-test --bundle com.google.Chrome --gain 0.2 --strategy keep-running
        suya-unduck-lab fault-inject --bundle com.google.Chrome
        suya-unduck-lab soak --bundle com.google.Chrome --minutes 120 --gain 1
        """)
    }
}
struct LabError: Error, CustomStringConvertible { let description: String; init(_ s: String) { description = s } }
final class CAListenerToken {
    var address = AudioObjectPropertyAddress(mSelector: 0x6475636B, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    let id: UInt32
    let block: AudioObjectPropertyListenerBlock
    init(id: UInt32, handler: @escaping () -> Void) { self.id = id; block = { _, _ in handler() }; AudioObjectAddPropertyListenerBlock(id, &address, .main, block) }
    deinit { AudioObjectRemovePropertyListenerBlock(id, &address, .main, block) }
}
if #available(macOS 14.2, *) { do { try execute() } catch { fputs("suya-unduck-lab: \(error)\n", stderr); exit(1) } }
else { fputs("macOS 14.2 required\n", stderr); exit(1) }
