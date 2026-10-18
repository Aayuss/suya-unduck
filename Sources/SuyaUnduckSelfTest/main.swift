import Foundation
import CoreAudio
import MixerCore
import MixerEngine
import CAtomics

var tests = 0
func check(_ value: @autoclosure () -> Bool, _ name: String) {
    tests += 1
    guard value() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
}
final class Buffers {
    let raw: UnsafeMutableRawPointer
    let pointer: UnsafeMutablePointer<AudioBufferList>
    let buffers: UnsafeMutableAudioBufferListPointer
    init(_ channels: [Int], frames: Int, nilFirst: Bool = false) {
        raw = .allocate(byteCount: MemoryLayout<AudioBufferList>.size + max(0, channels.count - 1) * MemoryLayout<AudioBuffer>.stride, alignment: 16)
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: MemoryLayout<AudioBufferList>.size + max(0, channels.count - 1) * MemoryLayout<AudioBuffer>.stride)
        pointer = raw.assumingMemoryBound(to: AudioBufferList.self); pointer.pointee.mNumberBuffers = UInt32(channels.count)
        buffers = UnsafeMutableAudioBufferListPointer(pointer)
        for (i, ch) in channels.enumerated() {
            let bytes = frames * ch * 4
            let p = nilFirst && i == 0 ? nil : UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: 16)
            p?.initializeMemory(as: UInt8.self, repeating: 0, count: bytes)
            buffers[i] = AudioBuffer(mNumberChannels: UInt32(ch), mDataByteSize: p == nil ? 0 : UInt32(bytes), mData: p)
        }
    }
    func values(_ i: Int) -> UnsafeMutableBufferPointer<Float> { UnsafeMutableBufferPointer(start: buffers[i].mData!.assumingMemoryBound(to: Float.self), count: Int(buffers[i].mDataByteSize)/4) }
    deinit { for b in buffers { b.mData?.deallocate() }; raw.deallocate() }
}
func render(_ input: Buffers, _ output: Buffers, gain: Float = 1, current: Float? = nil, tap: Int = 0, planar: Bool = false, channels: Int = 2, outChannels: Int = 2, inject: Bool = false, expectedInputs: Int? = nil) -> (UInt64, Bool) {
    let sh = am_shared_create(gain)!; defer { am_shared_destroy(sh) }
    var g = current ?? gain
    let layout = RenderLayout(expectedInputBuffers: expectedInputs ?? input.buffers.count, tapFirstBuffer: tap, tapNonInterleaved: planar, tapChannels: channels, expectedOutputBuffers: output.buffers.count, outputInterleavedChannels: outChannels)
    if inject { am_inject_fault(sh) }
    AudioRender.process(input: input.buffers, output: output.buffers, layout: layout, shared: sh, current: &g)
    return (am_get_format_errors(sh), am_is_failed(sh) != 0)
}
check(am_atomics_are_lock_free() == 1, "lock-free atomics")
let shared = am_shared_create(1)!
DispatchQueue.concurrentPerform(iterations: 2) { worker in
    for i in 0..<1_000_000 { am_set_target_gain(shared, Float((i + worker) % 200) / 100); _ = am_get_target_gain(shared); am_inc_callbacks(shared); am_store_peak(shared, 0.5); _ = am_load_peak(shared) }
}
check(am_get_callbacks(shared) == 2_000_000, "concurrent exact callback count")
am_shared_destroy(shared)
check(GainMath.gain(forSlider: 0.5) == 0.25, "perceptual slider")
check(GainMath.gain(forSlider: 1) == 1, "unity slider")
check(GainMath.gain(forSlider: 10) == 2, "slider clamping")
for value: Float in [0, 0.8, 0.9, 1, 1.6, -1.6, 100] { check(abs(GainMath.softLimit(value)) <= 1, "limiter bounded") }
let settings = try! JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
check(settings.apps.isEmpty && !settings.duckApproved && !settings.replay, "missing settings safe defaults")
let partial = try! JSONDecoder().decode(Settings.self, from: Data("{\"apps\":{\"test\":{\"volume\":0.3}}}".utf8))
check(partial.apps["test"]!.volume == 0.3 && !partial.apps["test"]!.muted, "partial settings migration")
let roundtrip = try! JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(partial))
check(roundtrip.apps["test"]!.volume == 0.3, "settings roundtrip")
check((try? JSONDecoder().decode(Settings.self, from: Data("garbage".utf8))) == nil, "corrupt settings detected")
check(Protection.group("com.google.Chrome.helper") == "com.google.Chrome", "Chrome grouping")
check(Protection.group("com.microsoft.edgemac.helper.renderer") == "com.microsoft.edgemac", "Edge grouping")
check(Protection.known.contains("net.whatsapp.WhatsApp"), "call protection")
let input = Buffers([2], frames: 512), output = Buffers([2], frames: 512)
var rng: UInt64 = 12345
for index in 0..<input.values(0).count { rng = rng &* 6364136223846793005 &+ 1; input.values(0)[index] = Float(Int32(truncatingIfNeeded: rng >> 32)) / Float(Int32.max) }
check(!render(input, output).1, "unity render accepted")
check(zip(input.values(0), output.values(0)).allSatisfy { $0.bitPattern == $1.bitPattern }, "unity bit-exact random samples")
_ = render(input, output, gain: 0)
check(output.values(0).allSatisfy { $0 == 0 }, "mute")
input.values(0).initialize(repeating: 1)
_ = render(input, output, gain: 1, current: 0)
check(output.values(0)[0] > 0 && output.values(0)[1023] == 1, "ramp endpoints")
check((1..<512).allSatisfy { output.values(0)[$0*2] >= output.values(0)[($0-1)*2] }, "ramp monotonic")
input.values(0).initialize(repeating: 0.8)
_ = render(input, output, gain: 2)
check(output.values(0).allSatisfy { $0.isFinite && abs($0) <= 1 }, "boost finite and bounded")
let mono = Buffers([1], frames: 512)
for f in 0..<512 { input.values(0)[f*2] = 0.2; input.values(0)[f*2+1] = 0.8 }
_ = render(input, mono, outChannels: 1)
check(mono.values(0).allSatisfy { $0 == 0.5 }, "mono downmix")
let quad = Buffers([4], frames: 512)
_ = render(input, quad, outChannels: 4)
check((0..<512).allSatisfy { quad.values(0)[$0*4] == 0.2 && quad.values(0)[$0*4+1] == 0.8 && quad.values(0)[$0*4+2] == 0 && quad.values(0)[$0*4+3] == 0 }, "multichannel output surplus silent")
let planar = Buffers([1, 1], frames: 512)
_ = render(input, planar, outChannels: 0)
check(planar.values(0).allSatisfy { $0 == 0.2 } && planar.values(1).allSatisfy { $0 == 0.8 }, "planar output")
let mic = Buffers([1, 2], frames: 512, nilFirst: true)
mic.values(1).initialize(repeating: 0.3)
_ = render(mic, output, tap: 1)
check(output.values(0).allSatisfy { $0 == 0.3 }, "disabled mic buffer ignored; tap offset used")
let short = Buffers([2], frames: 64)
check(!render(input, short).1 && short.values(0).allSatisfy { $0.isFinite }, "short output bounded")
for gain: Float in [1, 0.5, 2] {
    input.values(0)[0] = .nan; input.values(0)[1] = .infinity
    _ = render(input, output, gain: gain)
    check(output.values(0)[0] == 0 && output.values(0)[1] == 0, "NaN/Inf sanitized")
}
let failure = render(input, output, expectedInputs: 2)
check(failure.0 == 1 && failure.1 && output.values(0).allSatisfy { $0 == 0 }, "shape mismatch fails silent")
let fault = render(input, output, inject: true)
check(fault.0 == 1 && fault.1, "injected fault fails safe")
let badIndex = render(input, output, tap: 5)
check(badIndex.1, "invalid tap offset rejected")
var policy = Settings()
var appSetting = AppSetting()
func decide(playing: Bool = true, protected: Bool = false, silent: Double = 0, call: Bool = false) -> DesiredPipeline? {
    Decision.desired(setting: appSetting, global: policy, protected: protected, playing: playing, silentSeconds: silent, call: call, defaultOutput: "speakers", available: ["speakers", "headphones"])
}
check(decide() == nil, "default app bypasses engine")
appSetting.volume = 0.5
check(decide()?.gain == 0.25 && decide()?.running == true, "custom volume requires processing")
check(decide(playing: false, silent: 1000)?.running == true, "keep-running silent app")
policy.resumePolicy = "stop-io"
check(decide(playing: false, silent: 40)?.running == false, "stop-io after deadline")
check(decide(playing: false, silent: 10)?.running == true, "stop-io before deadline")
check(decide(playing: false, silent: 1000) != nil, "stop-io retains pipeline")
policy.resumePolicy = "destroy"
check(decide(playing: false, silent: 200) == nil, "destroy idle pipeline")
check(decide(protected: true) == nil, "protected call never processed")
appSetting.muted = true
check(decide()?.gain == 0, "mute policy")
appSetting = AppSetting(); appSetting.output = "missing"
check(decide() == nil, "missing route falls back without unnecessary processing")
appSetting.output = "headphones"
check(decide()?.outputUID == "headphones", "custom route")
appSetting = AppSetting(); policy.replay = true
check(decide(call: true)?.gain == 1, "call replay without digital boost")
check(decide(playing: false, silent: 200, call: true) == nil, "anti-duck-only idle removal")
policy.compensationEnabled = true; policy.compensation = 9
check(decide(call: true)?.gain == 3, "compensation clamped")
check(decide() == nil, "no compensation outside a call")
check(Protection.isProtected("net.whatsapp.WhatsApp.ServiceExtension"), "call extension protected")

check(CallActivity.isCall(knownCallApp: true, browser: false, userApp: true, playing: true, recording: false), "WhatsApp output detects call even with helper-owned mic")
check(CallActivity.isCall(knownCallApp: true, browser: false, userApp: false, playing: false, recording: true), "call audio helper input detects call")
check(!CallActivity.isCall(knownCallApp: true, browser: false, userApp: true, playing: false, recording: false), "idle WhatsApp does not enable timer")
check(CallActivity.isCall(knownCallApp: false, browser: true, userApp: true, playing: false, recording: true), "browser call input detects call")
check(!CallActivity.isCall(knownCallApp: false, browser: false, userApp: false, playing: true, recording: true), "background speech helper does not detect call")
check(CallActivity.isCall(knownCallApp: false, browser: false, userApp: true, playing: true, recording: true), "other user call apps detected")
check(!AppPresentation.showInMixer(isUserApp: false, playing: true, hasSavedVolume: true), "hide internal system audio processes")
check(AppPresentation.showInMixer(isUserApp: true, playing: true, hasSavedVolume: false), "show playing media apps")
check(AppPresentation.showInMixer(isUserApp: true, playing: false, hasSavedVolume: true), "retain saved app volume rows")
var legacy = try! JSONDecoder().decode(Settings.self, from: Data("{\"duckApproved\":true,\"replay\":true,\"compensationEnabled\":true,\"apps\":{\"music\":{\"volume\":0.4,\"muted\":true,\"output\":\"old-device\"}}}".utf8))
legacy.simplifyInterface()
check(legacy.duckApproved && !legacy.replay && !legacy.compensationEnabled, "migration preserves anti-duck opt-in and removes hidden processing")
check(legacy.apps["music"]?.volume == 0.4 && legacy.apps["music"]?.muted == true && legacy.apps["music"]?.output == nil, "migration retains volumes and unmutes no apps")
check(legacy.interfaceVersion == 2 && legacy.resumePolicy == "keep-running", "simple interface migration versioned")

// Regression for the failed real-call behavior: a constant readable property and
// no listener events must still receive scheduled unity commands while active.
var property: [Float] = [0, 0, 0, 0]
var writes = 0
var shouldFail = false
let access = DuckPropertyAccess(read: { _ in property }, write: { _, values in
    writes += 1
    if shouldFail { throw NSError(domain: "test", code: 1) }
    property = values
}, supported: { _ in true }, observe: { _, _ in {} })
let guardUnderTest = DuckGuard(access: access)
guardUnderTest.start(devices: [123], approved: false)
check(writes == 0, "no approval means no device writes")
guardUnderTest.start(devices: [123], approved: true)
check(property == [1, 0, 0, 0] && writes == 1 && guardUnderTest.status == "active", "initial approved unity command")
RunLoop.main.run(until: Date().addingTimeInterval(1.2))
check(writes >= 2, "refresh unity even without listener events or readable delta")
guardUnderTest.stop()
check(property == [0, 0, 0, 0], "restore original value on call end")
let countAfterStop = writes
RunLoop.main.run(until: Date().addingTimeInterval(0.7))
check(writes == countAfterStop, "no polling or writes after call ends")
guardUnderTest.start(devices: [123], approved: true)
property = [0.3, 0, 0, 0]
let beforeExternalStop = writes
guardUnderTest.stop()
check(writes == beforeExternalStop && property[0] == 0.3, "do not overwrite someone else's newer value on exit")
shouldFail = true
guardUnderTest.start(devices: [123], approved: true)
let countAfterFailure = writes
RunLoop.main.run(until: Date().addingTimeInterval(0.7))
check(writes == countAfterFailure && guardUnderTest.status == "unavailable", "write failure disables refresh without retry loops")
guardUnderTest.stop()
print("PASS: \(tests) suya-unduck self-tests, including 2,000,000 concurrent atomic operations")
