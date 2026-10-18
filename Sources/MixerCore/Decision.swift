import Foundation

public struct DesiredPipeline: Equatable {
    public let outputUID: String
    public let gain: Float
    public let running: Bool
}
public enum Decision {
    /// Pure policy, independent of Core Audio and the UI.
    public static func desired(setting: AppSetting, global: Settings, protected: Bool, playing: Bool, silentSeconds: Double, call: Bool, defaultOutput: String, available: Set<String>) -> DesiredPipeline? {
        let output = setting.output.flatMap { available.contains($0) ? $0 : nil } ?? defaultOutput
        let custom = setting.muted || abs(setting.volume - 1) > 0.001 || output != defaultOutput
        // Explicit volume/mute/routing is the user opt-in for call-app processing.
        guard !protected || custom else { return nil }
        let replay = playing && (global.duckApproved || (global.replay && call))
        guard custom || replay else { return nil }
        var gain = setting.muted ? Float(0) : GainMath.gain(forSlider: setting.volume)
        if global.compensationEnabled && call { gain *= min(3, max(1, global.compensation)) }
        if custom && global.resumePolicy == "destroy" && !playing && silentSeconds >= global.destroyIdleSeconds { return nil }
        let running = playing || global.resumePolicy == "keep-running" || silentSeconds < global.idleStopSeconds
        return DesiredPipeline(outputUID: output, gain: gain, running: running)
    }
}
