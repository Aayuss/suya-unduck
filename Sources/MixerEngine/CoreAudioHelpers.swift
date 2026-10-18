import CoreAudio
import Foundation

struct CAError: Error, CustomStringConvertible {
    let status: OSStatus
    let what: String
    var description: String { "\(what) failed: \(status) '\(fourCC(UInt32(bitPattern: status)))'" }
}

func fourCC(_ v: UInt32) -> String {
    let b = [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    return b.allSatisfy({ $0 >= 32 && $0 < 127 }) ? String(decoding: b, as: UTF8.self) : "\(v)"
}

@inline(__always) func caCheck(_ s: OSStatus, _ what: @autoclosure () -> String) throws {
    if s != noErr { throw CAError(status: s, what: what()) }
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = AudioObjectID(kAudioObjectUnknown)

    func addr(_ sel: AudioObjectPropertySelector,
              _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
              _ el: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        .init(mSelector: sel, mScope: scope, mElement: el)
    }
    func has(_ sel: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
             element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Bool {
        var a = addr(sel, scope, element); return AudioObjectHasProperty(self, &a)
    }
    func isSettable(_ sel: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Bool {
        var a = addr(sel, scope, element); var s: DarwinBoolean = false
        return AudioObjectIsPropertySettable(self, &a, &s) == noErr && s.boolValue
    }
    func read<T>(_ sel: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                 element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain, initial: T) throws -> T {
        var a = addr(sel, scope, element); var v = initial; var size = UInt32(MemoryLayout<T>.size)
        try withUnsafeMutableBytes(of: &v) { bytes in
            try caCheck(AudioObjectGetPropertyData(self, &a, 0, nil, &size, bytes.baseAddress!), "get \(fourCC(sel)) on \(self)")
        }
        guard size == MemoryLayout<T>.size else { throw CAError(status: -1, what: "Unexpected property size") }
        return v
    }
    func write<T>(_ sel: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                  element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain, value: T) throws {
        var a = addr(sel, scope, element); var v = value
        try withUnsafeBytes(of: &v) { bytes in
            try caCheck(AudioObjectSetPropertyData(self, &a, 0, nil, UInt32(MemoryLayout<T>.size), bytes.baseAddress!), "set \(fourCC(sel)) on \(self)")
        }
    }
    func readArray<T>(_ sel: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                      element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain, zero: T) throws -> [T] {
        var a = addr(sel, scope, element); var size: UInt32 = 0
        try caCheck(AudioObjectGetPropertyDataSize(self, &a, 0, nil, &size), "size \(fourCC(sel))")
        guard size <= 16_777_216, Int(size) % MemoryLayout<T>.stride == 0 else { throw CAError(status: -1, what: "Invalid property array size") }
        let n = Int(size) / MemoryLayout<T>.stride
        if n == 0 { return [] }
        var arr = [T](repeating: zero, count: n)
        try arr.withUnsafeMutableBytes { raw in
            try caCheck(AudioObjectGetPropertyData(self, &a, 0, nil, &size, raw.baseAddress!), "get \(fourCC(sel))")
        }
        return Array(arr.prefix(Int(size) / MemoryLayout<T>.stride))
    }
    func readString(_ sel: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> String {
        var a = addr(sel, scope); var v: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try caCheck(AudioObjectGetPropertyData(self, &a, 0, nil, &size, &v), "get string \(fourCC(sel))")
        return (v?.takeRetainedValue() as String?) ?? ""
    }
}

/// One listener registration. Removal needs the SAME block instance, so we keep it.
final class CAListener {
    private let object: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let queue: DispatchQueue
    private let block: AudioObjectPropertyListenerBlock
    private(set) var active = false
    init(object: AudioObjectID, address: AudioObjectPropertyAddress, queue: DispatchQueue, handler: @escaping () -> Void) {
        self.object = object; self.address = address; self.queue = queue
        self.block = { _, _ in handler() }
        active = AudioObjectAddPropertyListenerBlock(object, &self.address, queue, block) == noErr
    }
    func cancel() {
        guard active else { return }
        AudioObjectRemovePropertyListenerBlock(object, &address, queue, block); active = false
    }
    deinit { cancel() }
}

func processObject(for pid: pid_t) -> AudioObjectID? {
    var a = AudioObjectID.system.addr(kAudioHardwarePropertyTranslatePIDToProcessObject)
    var p = pid; var obj = AudioObjectID.unknown; var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let s = AudioObjectGetPropertyData(.system, &a, UInt32(MemoryLayout<pid_t>.size), &p, &size, &obj)
    return (s == noErr && obj != .unknown) ? obj : nil
}
