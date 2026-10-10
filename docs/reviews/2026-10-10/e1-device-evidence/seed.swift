import Foundation
let base = URL(fileURLWithPath: "/Users/sim/ProgrammingProjects/1-macOS/Conjoyn/01_Project/build/E1-Device-Acceptance")
let specs = try JSONSerialization.jsonObject(with: Data(contentsOf: base.appendingPathComponent("specs.json"))) as! [[String:String]]
var entries:[[String:Any]]=[]
for spec in specs {
    let root=URL(fileURLWithPath:spec["root"]!), output=URL(fileURLWithPath:spec["output"]!)
    entries.append(["id":spec["id"]!,"rootPath":root.path,"rootBookmark":try root.bookmarkData().base64EncodedString(),"outputPath":output.path,"outputBookmark":try output.bookmarkData().base64EncodedString(),"enabled":true,"settings":["enabled":true,"requiredStablePolls":3,"quietWindow":2,"pollInterval":0.75,"discoverTimeout":90]])
}
let data=try JSONSerialization.data(withJSONObject:entries, options:[.sortedKeys])
let defaults=UserDefaults(suiteName:"com.lucesumbrarum.conjoyn.e1device")!
defaults.set(data,forKey:"watchFolder.entries")
defaults.set(false,forKey:"SUEnableAutomaticChecks")
defaults.synchronize()
try data.write(to:base.appendingPathComponent("seeded-entries.json"))
print("Seeded \(entries.count) isolated watch entries")
