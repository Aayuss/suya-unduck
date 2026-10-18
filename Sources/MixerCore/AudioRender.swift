import CoreAudio
import CAtomics

public enum AudioRender {
    /// `current` is RT-thread-only memory (UnsafeMutablePointer<Float>, allocated once).
    @inline(__always)
    public static func process(input: UnsafeMutableAudioBufferListPointer,
                               output: UnsafeMutableAudioBufferListPointer,
                               layout: RenderLayout,
                               shared: OpaquePointer,
                               current: UnsafeMutablePointer<Float>) {
        am_inc_callbacks(shared)

        let callback = am_get_callbacks(shared)
        if callback <= 3 {
            let base = UInt32(callback - 1) * 50
            for side in 0..<2 {
                let buffers = side == 0 ? input : output
                let offset = base + UInt32(side * 25)
                am_probe_store(shared, offset, UInt32(buffers.count))
                for i in 0..<min(8, buffers.count) {
                    am_probe_store(shared, offset + UInt32(1 + i * 3), buffers[i].mNumberChannels)
                    am_probe_store(shared, offset + UInt32(2 + i * 3), buffers[i].mDataByteSize)
                    am_probe_store(shared, offset + UInt32(3 + i * 3), buffers[i].mData == nil ? 0 : 1)
                }
            }
        }
        // Silence first.
        for i in 0..<output.count { if output[i].mDataByteSize <= 16_777_216, let d = output[i].mData { memset(d, 0, Int(output[i].mDataByteSize)) } }

        // Validate against the layout computed at setup. Mismatch → count it + raise the one-way failed
        // flag; the 250 ms watchdog destroys the pipeline (control queue, never here) so the app's own
        // audio returns. Worst-case silence is bounded (~250 ms + teardown) and measured by fault-inject.
        if am_take_fault(shared) != 0 || am_is_failed(shared) != 0
            || input.count != layout.expectedInputBuffers || output.count != layout.expectedOutputBuffers {
            am_inc_format_errors(shared); am_set_failed(shared); return
        }

        guard layout.tapFirstBuffer >= 0, (1...2).contains(layout.tapChannels),
              layout.tapFirstBuffer < input.count,
              (!layout.tapNonInterleaved || layout.tapFirstBuffer + layout.tapChannels <= input.count),
              output.count > 0, (layout.outputInterleavedChannels > 0 || output.count >= 2) else {
            am_inc_format_errors(shared); am_set_failed(shared); return
        }
        for i in 0..<output.count {
            guard output[i].mDataByteSize <= 16_777_216, output[i].mDataByteSize % 4 == 0 else {
                am_inc_format_errors(shared); am_set_failed(shared); return
            }
        }
        // Source pointers.
        let srcL: UnsafeMutablePointer<Float>, srcR: UnsafeMutablePointer<Float>
        let stride: Int, srcFrames: Int
        if layout.tapNonInterleaved {
            let bl = input[layout.tapFirstBuffer]
            let br = input[layout.tapFirstBuffer + (layout.tapChannels > 1 ? 1 : 0)]
            guard bl.mNumberChannels == 1, br.mNumberChannels == 1, bl.mDataByteSize % 4 == 0, br.mDataByteSize % 4 == 0, let l = bl.mData?.assumingMemoryBound(to: Float.self),
                  let r = br.mData?.assumingMemoryBound(to: Float.self) else { am_inc_format_errors(shared); am_set_failed(shared); return }
            srcL = l; srcR = r; stride = 1
            srcFrames = Int(min(bl.mDataByteSize, br.mDataByteSize)) / 4
        } else {
            let b = input[layout.tapFirstBuffer]
            let ch = Int(b.mNumberChannels)
            guard ch == layout.tapChannels, ch > 0, b.mDataByteSize % UInt32(4 * ch) == 0, let p = b.mData?.assumingMemoryBound(to: Float.self) else {
                am_inc_format_errors(shared); am_set_failed(shared); return
            }
            srcL = p; srcR = ch > 1 ? p + 1 : p; stride = ch
            srcFrames = Int(b.mDataByteSize) / (4 * ch)
        }

        guard srcFrames <= 1_048_576 else { am_inc_format_errors(shared); am_set_failed(shared); return }
        let target = am_get_target_gain(shared)
        guard target.isFinite, target >= 0, target <= 6, current.pointee.isFinite else { am_inc_format_errors(shared); am_set_failed(shared); return }
        var g = current.pointee
        let unity = (g == 1 && target == 1)
        var peak: Float = 0

        @inline(__always) func shape(_ x: Float, _ gain: Float) -> Float {
            if !x.isFinite { return 0 }              // NaN/Inf from a broken source never reaches speakers
            if unity { return x }                    // bit-exact passthrough for every finite sample
            let y = x * gain
            return gain > 1 ? GainMath.softLimit(y) : y // limiter only when boosting
        }
        // Validation failures always flag a fail-safe teardown.
        // every other `am_inc_format_errors(shared); am_set_failed(shared); return` in this function must ALSO call
        // `am_set_failed(shared)`. All loops are bounded by validated byte sizes (`n = min(...)`).

        if layout.outputInterleavedChannels >= 1 {
            let o = output[0]
            let outCh = layout.outputInterleavedChannels
            guard Int(o.mNumberChannels) == outCh, let dst = o.mData?.assumingMemoryBound(to: Float.self) else {
                am_inc_format_errors(shared); am_set_failed(shared); return
            }
            let n = min(srcFrames, Int(o.mDataByteSize) / (4 * outCh))
            let step = n > 0 ? (target - g) / Float(n) : 0
            for f in 0..<n {
                g += step
                let l = srcL[f * stride], r = srcR[f * stride]
                if outCh == 1 {
                    let m = shape((l + r) * 0.5, g); dst[f] = m; peak = max(peak, abs(m))
                } else {
                    let lo = shape(l, g), ro = shape(r, g)
                    dst[f * outCh] = lo; dst[f * outCh + 1] = ro   // channels 3+ stay silent
                    peak = max(peak, abs(lo), abs(ro))
                }
            }
        } else {
            guard output[0].mNumberChannels == 1, output[1].mNumberChannels == 1, let d0 = output[0].mData?.assumingMemoryBound(to: Float.self),
                  let d1 = output[1].mData?.assumingMemoryBound(to: Float.self) else {
                am_inc_format_errors(shared); am_set_failed(shared); return
            }
            let n = min(srcFrames, Int(output[0].mDataByteSize) / 4, Int(output[1].mDataByteSize) / 4)
            let step = n > 0 ? (target - g) / Float(n) : 0
            for f in 0..<n {
                g += step
                let lo = shape(srcL[f * stride], g), ro = shape(srcR[f * stride], g)
                d0[f] = lo; d1[f] = ro; peak = max(peak, abs(lo), abs(ro))
            }
        }
        current.pointee = target
        am_store_peak(shared, peak)
    }
}
