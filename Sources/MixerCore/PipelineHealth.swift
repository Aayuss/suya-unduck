public enum PipelineHealth {
    /// An idle process tap may deliver no callbacks until its source emits audio.
    /// Format faults always fail safe; a stalled active source must also fail safe.
    public static func shouldStop(failed: Bool, stalledChecks: Int, sourcePlaying: Bool) -> Bool {
        failed || (sourcePlaying && stalledChecks >= 8)
    }
}
