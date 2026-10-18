public enum AppPresentation {
    public static func showInMixer(isUserApp: Bool, playing: Bool, hasSavedVolume: Bool) -> Bool {
        isUserApp && (playing || hasSavedVolume)
    }
}
public enum CallActivity {
    /// Known call-app output also counts: a call's microphone may be owned by a helper.
    public static func isCall(knownCallApp: Bool, browser: Bool, userApp: Bool, playing: Bool, recording: Bool) -> Bool {
        (knownCallApp && (playing || recording)) || (browser && recording) || (userApp && playing && recording)
    }
}
