import CoreAudio
import Foundation
import CAtomics
import MixerCore

@available(macOS 14.2, *)
public final class TapPipeline {
    public let groupKey: String
    public let processObjectIDs: [AudioObjectID]
    public let outputDeviceID: AudioObjectID
    public let outputDeviceUID: String
    public private(set) var tapID = AudioObjectID.unknown
    public private(set) var aggregateID = AudioObjectID.unknown
    private var tapDescription: CATapDescription?
    private var procID: AudioDeviceIOProcID?
    public private(set) var isRunning = false
    private var destroyed = false
    public let shared: OpaquePointer                         // CAtomics AMShared*
    private let current = UnsafeMutablePointer<Float>.allocate(capacity: 1)   // RT-only
    public private(set) var layout: RenderLayout!
    private var listeners: [CAListener] = []
    public var onNeedsRebuild: ((String) -> Void)?

    public init(groupKey: String, processObjectIDs: [AudioObjectID], outputDeviceID: AudioObjectID,
         outputDeviceUID: String, initialGain: Float, controlQueue: DispatchQueue) throws {
        self.groupKey = groupKey; self.processObjectIDs = processObjectIDs
        self.outputDeviceID = outputDeviceID; self.outputDeviceUID = outputDeviceUID
        guard let s = am_shared_create(initialGain) else { throw CAError(status: -1, what: "am_shared_create") }
        shared = s
        current.initialize(to: initialGain)
        do {
            try createTap()
            try createAggregate()
            layout = try buildAndValidateLayout()      // §6.3 — throws on anything unexpected
            try createIOProc()
            try disableNonTapInputStreams()
            installListeners(queue: controlQueue)
        } catch { destroy(); throw error }
    }

    private func createTap() throws {
        let d = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        d.uuid = UUID()
        d.name = "suya-unduck-\(groupKey)"
        d.isPrivate = true
        d.muteBehavior = .mutedWhenTapped   // RULE 7: macOS unmutes the app whenever our IO isn't reading
        var t = AudioObjectID.unknown
        try caCheck(AudioHardwareCreateProcessTap(d, &t), "CreateProcessTap(\(groupKey))")
        tapID = t; tapDescription = d
    }

    private func createAggregate() throws {
        let desc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "suya-unduck \(groupKey)",
            kAudioAggregateDeviceUIDKey: "com.ayus.suya-unduck.agg.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceClockDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputDeviceUID,
                                                     kAudioSubDeviceDriftCompensationKey: false]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapDescription!.uuid.uuidString,
                                               kAudioSubTapDriftCompensationKey: true]],
        ]
        var agg = AudioObjectID.unknown
        try caCheck(AudioHardwareCreateAggregateDevice(desc as CFDictionary, &agg), "CreateAggregate(\(groupKey))")
        aggregateID = agg
        for _ in 0..<20 {   // wait ≤200 ms for it to come alive (control queue only)
            if (try? agg.read(kAudioDevicePropertyDeviceIsAlive, initial: UInt32(0))) == 1 { break }
            usleep(10_000)
        }
    }



    private func createIOProc() throws {
        let sh = shared, cur = current, lay = layout!
        let block: AudioDeviceIOBlock = { _, inData, _, outData, _ in
            // REAL-TIME THREAD. Only this call. Nothing else.
            AudioRender.process(input: UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData)),
                                output: UnsafeMutableAudioBufferListPointer(outData),
                                layout: lay, shared: sh, current: cur)
        }
        var p: AudioDeviceIOProcID?
        try caCheck(AudioDeviceCreateIOProcIDWithBlock(&p, aggregateID, nil, block), "CreateIOProc(\(groupKey))")
        procID = p
    }

    /// If the output device also has inputs (AirPods, USB headsets), the aggregate exposes them.
    /// Turn them OFF for our IOProc so macOS never opens the headset mic (which would force
    /// low-quality Bluetooth call mode).
    private func disableNonTapInputStreams() throws {
        guard let procID, layout.tapFirstStream > 0 else { return }
        var a = aggregateID.addr(kAudioDevicePropertyIOProcStreamUsage, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(aggregateID, &a, 0, nil, &size) == noErr, size > 0 else { throw CAError(status: -1, what: "Cannot disable physical input streams") }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        let usage = raw.assumingMemoryBound(to: AudioHardwareIOProcStreamUsage.self)
        usage.pointee.mIOProc = unsafeBitCast(procID, to: UnsafeMutableRawPointer.self)
        guard AudioObjectGetPropertyData(aggregateID, &a, 0, nil, &size, raw) == noErr else { throw CAError(status: -1, what: "Read stream usage") }
        let n = Int(usage.pointee.mNumberStreams)
        let flags = (raw + MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mStreamIsOn)!)
            .assumingMemoryBound(to: UInt32.self)
        // Stream usage is indexed by STREAM (same order as kAudioDevicePropertyStreams), not by buffer.
        guard n == layout.inputStreamCount else { print("\(groupKey): stream usage count \(n) != streams \(layout.inputStreamCount); refusing input"); throw CAError(status: -1, what: "Stream usage mismatch") }
        for i in 0..<n { flags[i] = i >= layout.tapFirstStream ? 1 : 0 }
        let st = AudioObjectSetPropertyData(aggregateID, &a, 0, nil, size, raw)
        print("\(groupKey): input streams \(n), tap stream from \(layout.tapFirstStream), usage status \(st)")
        try caCheck(st, "Disable physical input streams")
        // The first-callback probe (§6.3 step 8) then confirms the buffer list we actually receive.
    }

    private func installListeners(queue: DispatchQueue) {
        let r: (String) -> Void = { [weak self] why in self?.onNeedsRebuild?(why) }
        let o = outputDeviceID
        listeners = [
            CAListener(object: aggregateID, address: aggregateID.addr(kAudioDevicePropertyDeviceIsAlive), queue: queue) { r("aggregate died") },
            CAListener(object: o, address: o.addr(kAudioDevicePropertyNominalSampleRate), queue: queue) { r("sample rate changed") },
            CAListener(object: o, address: o.addr(kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeOutput), queue: queue) { r("stream config changed") },
            CAListener(object: o, address: o.addr(kAudioDevicePropertyDeviceIsAlive), queue: queue) { r("output device gone") },
        ]
    }

    public func probeReport() -> String {
        (0..<min(3, Int(am_get_callbacks(shared)))).map { frame in
            let base = UInt32(frame * 50)
            return "callback \(frame + 1): " + (0..<2).map { side in
                let offset = base + UInt32(side * 25)
                let count = am_probe_load(shared, offset)
                return "\(side == 0 ? "in" : "out") count=\(count) " + (0..<min(8, Int(count))).map { buffer in
                    let index = offset + UInt32(1 + buffer * 3)
                    return "[channels=\(am_probe_load(shared, index)), bytes=\(am_probe_load(shared, index + 1)), data=\(am_probe_load(shared, index + 2))]"
                }.joined(separator: " ")
            }.joined(separator: "; ")
        }.joined(separator: " | ")
    }

    public func setGain(_ g: Float) { am_set_target_gain(shared, g) }

    public func start() throws {
        guard !isRunning, !destroyed, let procID else { return }
        try caCheck(AudioDeviceStart(aggregateID, procID), "Start(\(groupKey))")
        isRunning = true
    }

    /// With .mutedWhenTapped, stopping IO automatically un-mutes the app (macOS guarantees it).
    public func stop() {
        guard isRunning, let procID else { return }
        AudioDeviceStop(aggregateID, procID); isRunning = false
    }

    /// Order: listeners → stop IO → destroy IOProc → destroy aggregate → destroy tap → free shared memory.
    public func destroy() {
        guard !destroyed else { return }
        destroyed = true
        listeners.forEach { $0.cancel() }; listeners = []
        var safeToFree = true
        if let procID, aggregateID != .unknown {
            if isRunning { AudioDeviceStop(aggregateID, procID) }
            let status = AudioDeviceDestroyIOProcID(aggregateID, procID)
            if status != noErr { safeToFree = false; EventLog.write("IOProc destruction failed (\(status)); retaining callback storage for safety") }
        }
        procID = nil; isRunning = false
        if aggregateID != .unknown { AudioHardwareDestroyAggregateDevice(aggregateID); aggregateID = .unknown }
        if tapID != .unknown { AudioHardwareDestroyProcessTap(tapID); tapID = .unknown }
        if safeToFree {
            am_shared_destroy(shared)
            current.deinitialize(count: 1); current.deallocate()
        }
    }
    deinit { if !destroyed { destroy() } }
}
