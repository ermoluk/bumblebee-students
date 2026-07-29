import Foundation
import Security

/// Tiny wrapper over the app's own login-keychain for remembering the WiFi
/// password the operator types during drone setup. This is the app's private
/// generic-password item — NOT the System "AirPort" keychain — so reading and
/// writing it never triggers a macOS admin authorization prompt.
enum AppKeychain {
    private static let service = "com.bumblebee.gcs.wifi"

    static func password(for ssid: String) -> String? {
        guard !ssid.isEmpty else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ssid,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setPassword(_ password: String, for ssid: String) {
        guard !ssid.isEmpty else { return }
        let account: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ssid,
        ]
        SecItemDelete(account as CFDictionary)
        guard let data = password.data(using: .utf8) else { return }
        var add = account
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }
}
