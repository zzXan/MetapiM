import Foundation

// Both targets resolve the group from their own signed provisioning profile.
// Never use a different app's group or assume a team identifier.
enum SharedGroup {
    static func resolve(bundle: Bundle = .main) -> String? {
        let base = "group.com.zzxan.metapim"
        var candidates = [base]
        if let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
           let data = try? Data(contentsOf: url),
           let start = data.range(of: Data("<?xml".utf8)),
           let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
           let profile = try? PropertyListSerialization.propertyList(
               from: data.subdata(in: start.lowerBound..<end.upperBound), options: [], format: nil) as? [String: Any],
           let entitlements = profile["Entitlements"] as? [String: Any],
           let groups = entitlements["com.apple.security.application-groups"] as? [String] {
            candidates = groups.filter { $0 == base || $0.hasPrefix(base + ".") }.sorted() + candidates
        }
        return candidates.first {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        }
    }
}
