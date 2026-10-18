import AppKit
import Foundation
let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.ayus.suya-unduck")
for app in running where !app.terminate() { fputs("Could not request a graceful quit. Installation cancelled.\n", stderr); exit(1) }
let deadline = Date().addingTimeInterval(8)
while running.contains(where: { !$0.isTerminated }) && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
guard running.allSatisfy(\.isTerminated) else { fputs("The old app did not quit safely. Installation cancelled.\n", stderr); exit(1) }
