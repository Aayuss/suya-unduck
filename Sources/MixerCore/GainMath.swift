import Foundation

public enum GainMath {
    /// Slider 0...2 (1 = 100%). Perceptual below 100%, linear boost above.
    public static func gain(forSlider v: Float) -> Float {
        let c = min(max(v, 0), 2)
        return c <= 1 ? c * c : c
    }
    /// Soft limiter used ONLY when effective gain > 1. Transparent below 0.9, never exceeds 1.0.
    @inline(__always) public static func softLimit(_ x: Float) -> Float {
        let a = abs(x)
        if a <= 0.9 { return x }
        let y = 0.9 + 0.1 * tanhf((a - 0.9) / 0.1)
        return x < 0 ? -y : y
    }
}
