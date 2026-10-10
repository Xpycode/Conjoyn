import Foundation
import CryptoKit
struct Manifest: Decodable {
    struct Archive: Decodable { let path: String; let signature: String; let length: Int }
    let publicKey: String
    let archives: [Archive]
}
let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: manifest.publicKey)!)
for archive in manifest.archives {
    let data = try Data(contentsOf: URL(fileURLWithPath: archive.path))
    guard data.count == archive.length,
          let signature = Data(base64Encoded: archive.signature),
          key.isValidSignature(signature, for: data) else {
        fatalError("Invalid signature or length: \(archive.path)")
    }
    print("Verified Ed25519 + length: \(URL(fileURLWithPath: archive.path).lastPathComponent)")
}
