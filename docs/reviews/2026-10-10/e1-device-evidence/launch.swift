import AppKit
import Foundation
let base = "/Users/sim/ProgrammingProjects/1-macOS/Conjoyn/01_Project/build/"
let path = base + (CommandLine.arguments.contains("--restore") ? "ReleaseBlockers-App-DD/Build/Products/Debug/Conjoyn.app" : "E1-Device-Acceptance/Conjoyn.app")
let old = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == "com.lucesumbrarum.conjoyn" || $0.executableURL?.lastPathComponent == "Conjoyn" }
for app in old { print("Quit \(app.processIdentifier)"); guard app.terminate() else { exit(2) } }
let deadline=Date().addingTimeInterval(15)
while old.contains(where: { !$0.isTerminated }) && Date()<deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.1)) }
guard old.allSatisfy({ $0.isTerminated }) else { print("Quit pending; stopped");exit(3) }
if CommandLine.arguments.contains("--quit-only") { exit(0) }
let config=NSWorkspace.OpenConfiguration(); config.activates=true
if !CommandLine.arguments.contains("--restore") {
 var env=ProcessInfo.processInfo.environment
 env["HOME"]=base+"E1-Device-Acceptance/Home";env["CFFIXED_USER_HOME"]=base+"E1-Device-Acceptance/Home"
 config.environment=env
 config.arguments=["-SUEnableAutomaticChecks","NO","-ApplePersistenceIgnoreState","YES"]
}
var finished=false;var okay=false
NSWorkspace.shared.openApplication(at:URL(fileURLWithPath:path),configuration:config) { app,error in
 if let app { print("Launched \(app.processIdentifier) \(app.executableURL?.path ?? "unknown")");okay=app.executableURL?.path == path+"/Contents/MacOS/Conjoyn" } else { print("Failed \(String(describing:error))") }
 finished=true
}
while !finished { RunLoop.current.run(until:Date().addingTimeInterval(0.1)) }
exit(okay ? 0:4)
