import Foundation
public struct AppSetting: Codable {
    public var volume: Float = 1
    public var muted = false
    public var output: String? = nil
    public var favorite = false
    public init() {}
    enum CodingKeys: CodingKey { case volume, muted, output, favorite }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        volume = min(2, max(0, try c.decodeIfPresent(Float.self, forKey: .volume) ?? 1))
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        output = try c.decodeIfPresent(String.self, forKey: .output)
        favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
    }
}
public struct Settings: Codable {
    public var apps: [String: AppSetting] = [:]
    public var resumePolicy = "keep-running"
    public var idleStopSeconds: Double = 30
    public var destroyIdleSeconds: Double = 120
    public var callMode = "Auto"
    public var replay = false
    public var duckApproved = false
    public var compensationEnabled = false
    public var compensation: Float = 1
    public var browserCalls = false
    public var theme = "System"
    public var extraProtected: [String] = []
    public init() {}
    enum CodingKeys: CodingKey { case apps, resumePolicy, idleStopSeconds, destroyIdleSeconds, callMode, replay, duckApproved, compensationEnabled, compensation, browserCalls, theme, extraProtected }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apps = try c.decodeIfPresent([String: AppSetting].self, forKey: .apps) ?? [:]
        resumePolicy = try c.decodeIfPresent(String.self, forKey: .resumePolicy) ?? "keep-running"
        idleStopSeconds = min(600, max(5, try c.decodeIfPresent(Double.self, forKey: .idleStopSeconds) ?? 30))
        destroyIdleSeconds = min(3600, max(idleStopSeconds, try c.decodeIfPresent(Double.self, forKey: .destroyIdleSeconds) ?? 120))
        callMode = try c.decodeIfPresent(String.self, forKey: .callMode) ?? "Auto"
        replay = try c.decodeIfPresent(Bool.self, forKey: .replay) ?? false
        duckApproved = try c.decodeIfPresent(Bool.self, forKey: .duckApproved) ?? false
        compensationEnabled = try c.decodeIfPresent(Bool.self, forKey: .compensationEnabled) ?? false
        compensation = min(3, max(1, try c.decodeIfPresent(Float.self, forKey: .compensation) ?? 1))
        browserCalls = try c.decodeIfPresent(Bool.self, forKey: .browserCalls) ?? false
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? "System"
        extraProtected = try c.decodeIfPresent([String].self, forKey: .extraProtected) ?? []
    }
}
