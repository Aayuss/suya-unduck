import Foundation
import CoreAudio
import MixerCore

func shape(_ device: UInt32, _ scope: UInt32) throws -> [UInt32] {
    var a = device.addr(kAudioDevicePropertyStreamConfiguration, scope)
    var size: UInt32 = 0
    try caCheck(AudioObjectGetPropertyDataSize(device, &a, 0, nil, &size), "stream configuration size")
    guard size >= MemoryLayout<AudioBufferList>.size else { return [] }
    let p = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
    defer { p.deallocate() }
    try caCheck(AudioObjectGetPropertyData(device, &a, 0, nil, &size, p), "stream configuration")
    let b = UnsafeMutableAudioBufferListPointer(p.assumingMemoryBound(to: AudioBufferList.self))
    return b.map(\.mNumberChannels)
}
@available(macOS 14.2, *) extension TapPipeline {
    func buildAndValidateLayout() throws -> RenderLayout {
        func unsupported() -> CAError { CAError(status: -1, what: "Unsupported aggregate layout; app plays normally") }
        let tap = try tapID.read(kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
        let rate = try aggregateID.read(kAudioDevicePropertyNominalSampleRate, initial: Double(0))
        func valid(_ f: AudioStreamBasicDescription) -> Bool {
            f.mFormatID == kAudioFormatLinearPCM && f.mFormatFlags & kAudioFormatFlagIsFloat != 0 && f.mBitsPerChannel == 32 && f.mSampleRate == rate && f.mBytesPerFrame > 0
        }
        guard valid(tap), (1...2).contains(tap.mChannelsPerFrame) else { throw unsupported() }
        let ins = try aggregateID.readArray(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput, zero: UInt32(0))
        let outs = try aggregateID.readArray(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput, zero: UInt32(0))
        let physical = try outputDeviceID.readArray(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput, zero: UInt32(0))
        let ib = try shape(aggregateID, kAudioObjectPropertyScopeInput)
        let ob = try shape(aggregateID, kAudioObjectPropertyScopeOutput)
        guard ins.count == ib.count, outs.count == ob.count, ins.count > physical.count, !ob.isEmpty else { throw unsupported() }
        for (i, stream) in ins.enumerated() {
            let f = try stream.read(kAudioStreamPropertyVirtualFormat, initial: AudioStreamBasicDescription())
            let start = try stream.read(kAudioStreamPropertyStartingChannel, initial: UInt32(0))
            let direction = try stream.read(kAudioStreamPropertyDirection, initial: UInt32(0))
            print("input stream \(stream), starting channel \(start), direction \(direction), format \(f), buffer channels \(ib[i])")
            guard f.mChannelsPerFrame == ib[i] else { throw unsupported() }
            if i >= physical.count {
                guard valid(f), f.mChannelsPerFrame == tap.mChannelsPerFrame, f.mFormatFlags == tap.mFormatFlags else { throw unsupported() }
            }
        }
        for (i, stream) in outs.enumerated() {
            let f = try stream.read(kAudioStreamPropertyVirtualFormat, initial: AudioStreamBasicDescription())
            guard valid(f), f.mChannelsPerFrame == ob[i] else { throw unsupported() }
        }
        let planar = tap.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        // Refuse ambiguous planar tap stream mapping rather than guessing.
        guard !planar, ins.count == physical.count + 1, ob.count == 1 || (ob.count >= 2 && ob.allSatisfy { $0 == 1 }) else { throw unsupported() }
        var l = RenderLayout(expectedInputBuffers: ib.count, tapFirstBuffer: physical.count, tapNonInterleaved: false, tapChannels: Int(tap.mChannelsPerFrame), expectedOutputBuffers: ob.count, outputInterleavedChannels: ob.count == 1 ? Int(ob[0]) : 0)
        l.tapFirstStream = physical.count; l.inputStreamCount = ins.count
        print("validated layout: \(l)")
        return l
    }
}

/// Setup-only probe: the tap is unmuted, no IOProc is installed or started.
/// It cannot attenuate or reroute an application's audio or open an input stream.
@available(macOS 14.2, *) public func inspectTapLayout() throws -> String {
    let description = CATapDescription(stereoMixdownOfProcesses: [])
    description.uuid = UUID(); description.name = "suya-unduck format probe"; description.isPrivate = true; description.muteBehavior = .unmuted
    var tap: UInt32 = 0
    try caCheck(AudioHardwareCreateProcessTap(description, &tap), "Create unmuted format probe")
    defer { AudioHardwareDestroyProcessTap(tap) }
    let format = try tap.read(kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
    guard let device = Hardware.devices().first(where: { $0.id == Hardware.defaultDevice() }) else { throw CAError(status: -1, what: "No default device") }
    let config: [String: Any] = [kAudioAggregateDeviceNameKey: "suya-unduck format probe", kAudioAggregateDeviceUIDKey: "com.ayus.suya-unduck.probe.\(UUID().uuidString)", kAudioAggregateDeviceIsPrivateKey: true, kAudioAggregateDeviceMainSubDeviceKey: device.uid, kAudioAggregateDeviceClockDeviceKey: device.uid, kAudioAggregateDeviceTapAutoStartKey: true, kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: device.uid]], kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]]]
    var aggregate: UInt32 = 0
    try caCheck(AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate), "Create format probe aggregate")
    defer { AudioHardwareDestroyAggregateDevice(aggregate) }
    var report = "Tap format: \(format)\n"
    for scope in [kAudioObjectPropertyScopeInput, kAudioObjectPropertyScopeOutput] {
        let streams = try aggregate.readArray(kAudioDevicePropertyStreams, scope: scope, zero: UInt32(0))
        report += "Scope \(fourCC(scope)): buffer channels \(try shape(aggregate, scope)), streams \(streams)\n"
        for stream in streams { report += "\(stream): \(try stream.read(kAudioStreamPropertyVirtualFormat, initial: AudioStreamBasicDescription()))\n" }
    }
    return report + "No IO started; original application audio was left unmuted."
}
