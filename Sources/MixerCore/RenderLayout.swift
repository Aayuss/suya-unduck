/// Computed on the control queue when a pipeline is built. Captured BY VALUE in the IO block.
public struct RenderLayout: Equatable {
    public var expectedInputBuffers: Int     // device input streams + tap streams
    public var tapFirstBuffer: Int           // BUFFER index of the first tap buffer (from StreamConfiguration mapping)
    public var tapFirstStream: Int = 0       // STREAM index of the first tap stream (for IOProc stream usage)
    public var inputStreamCount: Int = 0     // aggregate input streams (device inputs + tap)
    public var tapNonInterleaved: Bool       // tap format flag
    public var tapChannels: Int              // usually 2
    public var expectedOutputBuffers: Int
    public var outputInterleavedChannels: Int // channels in output buffer 0 if interleaved (1 = mono), 0 if non-interleaved
    public init(expectedInputBuffers: Int, tapFirstBuffer: Int, tapNonInterleaved: Bool, tapChannels: Int,
                expectedOutputBuffers: Int, outputInterleavedChannels: Int) {
        self.expectedInputBuffers = expectedInputBuffers; self.tapFirstBuffer = tapFirstBuffer
        self.tapNonInterleaved = tapNonInterleaved; self.tapChannels = tapChannels
        self.expectedOutputBuffers = expectedOutputBuffers; self.outputInterleavedChannels = outputInterleavedChannels
    }
}
