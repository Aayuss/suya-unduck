import Foundation
import os

public enum EventLog {
    private static let queue = DispatchQueue(label: "com.ayus.suya-unduck.log", qos: .utility)
    private static let logger = Logger(subsystem: "com.ayus.suya-unduck", category: "engine")
    public static let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/suya-unduck")
    public static func write(_ message: String) {
        logger.info("\(message, privacy: .public)")
        queue.async {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let file = folder.appendingPathComponent("suya-unduck.log")
                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 5_000_000 {
                    let old = file.appendingPathExtension("old")
                    try? FileManager.default.removeItem(at: old); try FileManager.default.moveItem(at: file, to: old)
                }
                if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
                let handle = try FileHandle(forWritingTo: file); defer { try? handle.close() }
                try handle.seekToEnd(); try handle.write(contentsOf: Data("\(Date()) \(message)\n".utf8))
            } catch { logger.error("Log write failed: \(String(describing: error), privacy: .public)") }
        }
    }
}
