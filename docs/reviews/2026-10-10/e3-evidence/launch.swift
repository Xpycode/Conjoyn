import AppKit
import Foundation
let path = CommandLine.arguments[1]
let old = NSWorkspace.shared.runningApplications.filter {
    $0.bundleIdentifier == "com.lucesumbrarum.conjoyn" || $0.executableURL?.lastPathComponent == "Conjoyn"
}
for app in old {
    print("Quit requested: \(app.processIdentifier) \(app.executableURL?.path ?? "unknown")")
    guard app.terminate() else { exit(2) }
}
let deadline = Date().addingTimeInterval(20)
while old.contains(where: { !$0.isTerminated }) && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
guard old.allSatisfy({ $0.isTerminated }) else {
    print("Termination pending; launch stopped without force")
    exit(3)
}
let config = NSWorkspace.OpenConfiguration()
config.activates = true
var finished = false
var okay = false
NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: config) { app, error in
    if let app {
        print("Launched: \(app.processIdentifier) \(app.executableURL?.path ?? "unknown")")
        okay = app.executableURL?.path == path + "/Contents/MacOS/Conjoyn"
    } else { print("Launch failed: \(String(describing: error))") }
    finished = true
}
while !finished { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
exit(okay ? 0 : 4)
