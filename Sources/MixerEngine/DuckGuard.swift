import Foundation
import CoreAudio

/// The only undocumented selector in this project. Never enabled without explicit consent.
public final class DuckGuard {
    private static let selector: UInt32 = 0x6475636B
    private var original: [UInt32: [Float]] = [:]
    private var lastWritten: [UInt32: [Float]] = [:]
    private var listeners: [CAListener] = []
    private var times: [UInt32: Date] = [:]
    private var conflicts: [UInt32: [Date]] = [:]
    private var disabled = Set<UInt32>()
    private var applying = false
    private var pending: [UInt32: DispatchWorkItem] = [:]
    public var log: (String) -> Void = { _ in }
    public init() {}
    public static func read(_ id: UInt32) throws -> [Float] {
        let values = try id.readArray(selector, scope: kAudioObjectPropertyScopeOutput, zero: Float(0))
        guard values.count == 4, values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw CAError(status: -1, what: "Unknown duck property layout") }
        return values
    }
    public func start(devices: [UInt32], approved: Bool) {
        stop()
        guard approved else { log("Duck writes refused: approval required"); return }
        disabled.removeAll(); conflicts.removeAll(); times.removeAll()
        for id in Set(devices) {
            guard id.isSettable(Self.selector, scope: kAudioObjectPropertyScopeOutput), let value = try? Self.read(id) else { log("Duck unsupported on \(id)"); continue }
            original[id] = value
            listeners.append(CAListener(object: id, address: id.addr(Self.selector, kAudioObjectPropertyScopeOutput), queue: .main) { [weak self] in self?.apply(id) })
            apply(id)
        }
    }
    private func apply(_ id: UInt32) {
        guard original[id] != nil, !applying, !disabled.contains(id) else { return }
        applying = true; defer { applying = false }
        do {
            let current = try Self.read(id)
            guard current != [1, 0, 0, 0] else { return }
            let now = Date()
            conflicts[id] = (conflicts[id] ?? []).filter { now.timeIntervalSince($0) < 10 } + [now]
            guard conflicts[id]!.count <= 20 else { disabled.insert(id); log("Duck conflict on \(id); stopped writes"); return }
            if let time = times[id], now.timeIntervalSince(time) < 0.25 {
                pending[id]?.cancel()
                let work = DispatchWorkItem { [weak self] in self?.apply(id) }
                pending[id] = work
                DispatchQueue.main.asyncAfter(deadline: .now() + (0.25 - now.timeIntervalSince(time)), execute: work)
                return
            }
            let value: [Float] = [1, 0, 0, 0]
            var a = id.addr(Self.selector, kAudioObjectPropertyScopeOutput)
            let status = value.withUnsafeBytes { AudioObjectSetPropertyData(id, &a, 0, nil, 16, $0.baseAddress!) }
            try caCheck(status, "Duck write")
            times[id] = now; lastWritten[id] = value; log("Duck device \(id): \(current) → \(value), status \(status)")
        } catch { disabled.insert(id); log("Duck stopped on \(id): \(error)") }
    }
    public func stop() {
        pending.values.forEach { $0.cancel() }; pending.removeAll()
        listeners.removeAll()
        for (id, value) in original {
            guard let last = lastWritten[id], let current = try? Self.read(id), current == last else { log("Duck \(id): not restoring; value changed or never written"); continue }
            var a = id.addr(Self.selector, kAudioObjectPropertyScopeOutput)
            let status = value.withUnsafeBytes { AudioObjectSetPropertyData(id, &a, 0, nil, 16, $0.baseAddress!) }
            log("Duck restore \(id): status \(status)")
        }
        original.removeAll(); lastWritten.removeAll()
    }
    deinit { stop() }
}
