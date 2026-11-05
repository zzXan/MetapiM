import Foundation
import Security

struct WidgetSession: Codable {
    let server: String
    let token: String
    static func query(_ group: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "metapim.widget.session",
         kSecAttrAccount as String: "current",
         kSecAttrAccessGroup as String: group]
    }
    static func read(group: String) -> WidgetSession? {
        var q = query(group)
        q[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    func save(group: String) throws {
        let q = Self.query(group)
        let fields: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(self),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let update = SecItemUpdate(q as CFDictionary, fields as CFDictionary)
        if update == errSecItemNotFound {
            let status = SecItemAdd(q.merging(fields) { _, new in new } as CFDictionary, nil)
            guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        } else if update != errSecSuccess { throw NSError(domain: NSOSStatusErrorDomain, code: Int(update)) }
    }
    static func clear(group: String) throws {
        let status = SecItemDelete(query(group) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

