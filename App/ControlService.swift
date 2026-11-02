import Foundation
import CryptoKit

enum ControlService {
    static let installedURL = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/com.willowfan.engine")

    static func needsUpdate() -> Bool {
        guard let bundledURL = Bundle.main.url(forResource: "willowfan-engine", withExtension: nil),
              let bundled = try? Data(contentsOf: bundledURL),
              let installed = try? Data(contentsOf: installedURL) else { return false }
        return SHA256.hash(data: bundled) != SHA256.hash(data: installed)
    }
}
