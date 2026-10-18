import Foundation
import CoreAudio

public struct DuckPropertyAccess {
    public var read: (UInt32) throws -> [Float]
    public var write: (UInt32, [Float]) throws -> Void
    public var supported: (UInt32) -> Bool
    public var observe: (UInt32, @escaping () -> Void) -> (() -> Void)
    public init(read: @escaping (UInt32) throws -> [Float], write: @escaping (UInt32, [Float]) throws -> Void, supported: @escaping (UInt32) -> Bool, observe: @escaping (UInt32, @escaping () -> Void) -> (() -> Void)) {
        self.read = read; self.write = write; self.supported = supported; self.observe = observe
    }
    public static var live: DuckPropertyAccess {
        DuckPropertyAccess(read: DuckGuard.read, write: { id, values in
            var a = id.addr(0x6475636B, kAudioObjectPropertyScopeOutput)
            let result = values.withUnsafeBytes { AudioObjectSetPropertyData(id, &a, 0, nil, 16, $0.baseAddress!) }
            try caCheck(result, "Duck write")
        }, supported: { $0.isSettable(0x6475636B, scope: kAudioObjectPropertyScopeOutput) }, observe: { id, handler in
            let listener = CAListener(object: id, address: id.addr(0x6475636B, kAudioObjectPropertyScopeOutput), queue: .main, handler: handler)
            return { listener.cancel() }
        })
    }
}

/// Undocumented device property, enabled only by the user's saved opt-in.
public final class DuckGuard {
    private static let selector: UInt32 = 0x6475636B
    private var original: [UInt32: [Float]] = [:]
    private var lastWritten: [UInt32: [Float]] = [:]
    private var listeners: [() -> Void] = []
    private let access: DuckPropertyAccess
    private var times: [UInt32: Date] = [:]
    private var conflicts: [UInt32: [Date]] = [:]
    private var disabled = Set<UInt32>()
    private var applying = false
    private var pending: [UInt32: DispatchWorkItem] = [:]
    private var timer: DispatchSourceTimer?
    public private(set) var status = "idle" { didSet { if status != oldValue { onStatusChange?() } } }
    public var onStatusChange: (() -> Void)?
    public var log: (String) -> Void = { _ in }
    public init(access: DuckPropertyAccess = .live) { self.access = access }
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
            guard access.supported(id), let value = try? access.read(id) else { log("Duck unsupported on \(id)"); continue }
            original[id] = value
            listeners.append(access.observe(id) { [weak self] in self?.apply(id, force: false) })
            apply(id, force: true)
        }
        status = original.keys.contains { !disabled.contains($0) } ? "active" : "unavailable"
        guard status == "active" else { return }
        // The previous listener-only method failed the user's real call. Core Audio
        // may reapply attenuation without a useful property change or readable delta.
        // Refresh the device command every 500 ms ONLY while the call is active.
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(75))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            for id in Array(self.original.keys) { self.apply(id, force: true) }
            if self.original.keys.allSatisfy({ self.disabled.contains($0) }) { self.timer?.cancel(); self.timer = nil; self.status = "unavailable" }
        }
        timer = source; source.resume()
        log("Call-volume guard started: 500 ms refresh plus device listeners")
    }
    private func apply(_ id: UInt32, force: Bool) {
        guard original[id] != nil, !applying, !disabled.contains(id) else { return }
        applying = true; defer { applying = false }
        do {
            let current = try access.read(id)
            guard force || current != [1, 0, 0, 0] else { return }
            let now = Date()
            if let time = times[id], now.timeIntervalSince(time) < 0.25 {
                pending[id]?.cancel()
                let work = DispatchWorkItem { [weak self] in self?.apply(id, force: force) }
                pending[id] = work
                DispatchQueue.main.asyncAfter(deadline: .now() + (0.25 - now.timeIntervalSince(time)), execute: work)
                return
            }
            // Count only externally observed resets, never our scheduled refreshes.
            if !force && current != [1, 0, 0, 0] {
                conflicts[id] = (conflicts[id] ?? []).filter { now.timeIntervalSince($0) < 10 } + [now]
                guard conflicts[id]!.count <= 20 else { disabled.insert(id); log("Duck conflict on \(id); stopped writes"); return }
            }
            let value: [Float] = [1, 0, 0, 0]
            try access.write(id, value)
            let firstWrite = lastWritten[id] == nil
            times[id] = now; lastWritten[id] = value
            if firstWrite || current != value { log("Duck device \(id): \(current) → \(value), status 0") }
        } catch { disabled.insert(id); log("Duck stopped on \(id): \(error)") }
    }
    public func stop() {
        timer?.cancel(); timer = nil
        pending.values.forEach { $0.cancel() }; pending.removeAll()
        listeners.forEach { $0() }; listeners.removeAll()
        for (id, value) in original {
            guard let last = lastWritten[id], let current = try? access.read(id), current == last else { log("Duck \(id): not restoring; value changed or never written"); continue }
            do { try access.write(id, value); log("Duck restore \(id): status 0") } catch { log("Duck restore \(id) failed: \(error)") }
        }
        original.removeAll(); lastWritten.removeAll(); status = "idle"
    }
    deinit { stop() }
}
