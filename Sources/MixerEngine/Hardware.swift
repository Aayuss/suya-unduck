import Foundation
import CoreAudio
import AppKit

public struct AudioDevice: Identifiable, Equatable {
    public let id: AudioObjectID
    public let uid: String
    public let name: String
    public let rate: Double
    public let input: Bool
    public let output: Bool
}
public struct AudioApp: Identifiable {
    public let id: String
    public let name: String
    public let processes: [AudioObjectID]
    public let playing: Bool
    public let recording: Bool
    public var protected: Bool { Protection.isProtected(id) || recording }
}
public enum Protection {
    public static let known: Set<String> = ["net.whatsapp.WhatsApp", "desktop.WhatsApp", "WhatsApp", "us.zoom.xos", "com.microsoft.teams", "com.microsoft.teams2", "com.apple.FaceTime", "com.apple.TelephonyUtilities", "com.hnc.Discord", "com.tinyspeck.slackmacgap", "com.skype.skype", "ru.keepcoder.Telegram", "org.telegram.desktop", "org.whispersystems.signal-desktop", "com.cisco.webexmeetingsapp", "Cisco-Systems.Spark"]
    public static func isProtected(_ id: String) -> Bool { known.contains(id) || known.contains { id.hasPrefix($0 + ".") } }
    public static func group(_ id: String) -> String {
        for suffix in [".helper.renderer", ".helper.plugin", ".helper.gpu", ".helper", ".Helper"] { if id.hasSuffix(suffix) { return String(id.dropLast(suffix.count)) } }
        if id.hasPrefix("com.apple.WebKit.") { return "com.apple.Safari" }
        return id
    }
}
public enum Hardware {
    public static func defaultDevice(input: Bool = false) -> AudioObjectID {
        (try? AudioObjectID.system.read(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice, initial: UInt32(0))) ?? 0
    }
    public static func devices() -> [AudioDevice] {
        let ids = (try? AudioObjectID.system.readArray(kAudioHardwarePropertyDevices, zero: UInt32(0))) ?? []
        return ids.compactMap { id in
            guard let uid = try? id.readString(kAudioDevicePropertyDeviceUID), !uid.hasPrefix("com.ayus.suya-unduck"), !uid.hasPrefix("CADefaultDeviceAggregate") else { return nil }
            let name = (try? id.readString(kAudioObjectPropertyName)) ?? uid
            let ins = (try? id.readArray(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput, zero: UInt32(0))) ?? []
            let outs = (try? id.readArray(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput, zero: UInt32(0))) ?? []
            return AudioDevice(id: id, uid: uid, name: name, rate: (try? id.read(kAudioDevicePropertyNominalSampleRate, initial: Double(0))) ?? 0, input: !ins.isEmpty, output: !outs.isEmpty)
        }
    }
    @available(macOS 14.2, *) public static func apps() -> [AudioApp] {
        let ids = (try? AudioObjectID.system.readArray(kAudioHardwarePropertyProcessObjectList, zero: UInt32(0))) ?? []
        var grouped: [String: (String, [UInt32], Bool, Bool)] = [:]
        for id in ids {
            let pid = (try? id.read(kAudioProcessPropertyPID, initial: pid_t(0))) ?? 0
            if pid == getpid() { continue }
            let running = NSRunningApplication(processIdentifier: pid)
            let bundle = (try? id.readString(kAudioProcessPropertyBundleID)) ?? ""
            var owner = running
            var p = pid
            for _ in 0..<10 {
                if let app = NSRunningApplication(processIdentifier: p), let url = app.bundleURL, !url.path.contains(".app/") { owner = app; break }
                var info = kinfo_proc(); var size = MemoryLayout<kinfo_proc>.size
                var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, p]
                if sysctl(&mib, 4, &info, &size, nil, 0) != 0 { break }
                let parent = info.kp_eproc.e_ppid
                if parent <= 1 || parent == p { break }; p = parent
            }
            let rawKey = owner?.bundleIdentifier ?? (bundle.isEmpty ? "proc:\(pid)" : bundle)
            let key = rawKey.hasPrefix("com.apple.WebKit.") && NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").isEmpty ? rawKey : Protection.group(rawKey)
            if key.hasPrefix("com.apple.audio.") || ["com.apple.controlcenter", "com.apple.SystemUIServer"].contains(key) { continue }
            let output = (try? id.read(kAudioProcessPropertyIsRunningOutput, initial: UInt32(0))) == 1
            let input = (try? id.read(kAudioProcessPropertyIsRunningInput, initial: UInt32(0))) == 1
            let old = grouped[key]
            grouped[key] = (owner?.localizedName ?? key, (old?.1 ?? []) + [id], output || (old?.2 ?? false), input || (old?.3 ?? false))
        }
        return grouped.map { AudioApp(id: $0.key, name: $0.value.0, processes: $0.value.1.sorted(), playing: $0.value.2, recording: $0.value.3) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    public static func setDefault(_ id: UInt32, input: Bool) throws { try AudioObjectID.system.write(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice, value: id) }
    private static func inputElements(_ selector: UInt32) -> [UInt32] {
        let id = defaultDevice(input: true)
        if id.isSettable(selector, scope: kAudioObjectPropertyScopeInput) { return [kAudioObjectPropertyElementMain] }
        let channels = (try? shape(id, kAudioObjectPropertyScopeInput).reduce(0, +)) ?? 0
        if channels == 0 { return [] }
        return (1...min(channels, 32)).filter { id.isSettable(selector, scope: kAudioObjectPropertyScopeInput, element: $0) }
    }
    public static func inputVolume() -> Float? {
        let id = defaultDevice(input: true)
        guard let element = inputElements(kAudioDevicePropertyVolumeScalar).first else { return nil }
        return try? id.read(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput, element: element, initial: Float(0))
    }
    public static func setInputVolume(_ value: Float) throws {
        let elements = inputElements(kAudioDevicePropertyVolumeScalar)
        guard !elements.isEmpty else { throw CAError(status: -1, what: "Microphone has no adjustable hardware volume") }
        for element in elements { try defaultDevice(input: true).write(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput, element: element, value: min(max(value, 0), 1)) }
    }
    public static func inputMuted() -> Bool? {
        guard let element = inputElements(kAudioDevicePropertyMute).first else { return nil }
        return (try? defaultDevice(input: true).read(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput, element: element, initial: UInt32(0))).map { $0 != 0 }
    }
    public static func setInputMuted(_ muted: Bool) throws {
        let elements = inputElements(kAudioDevicePropertyMute)
        guard !elements.isEmpty else { throw CAError(status: -1, what: "Microphone has no hardware mute") }
        for element in elements { try defaultDevice(input: true).write(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput, element: element, value: UInt32(muted ? 1 : 0)) }
    }
}
