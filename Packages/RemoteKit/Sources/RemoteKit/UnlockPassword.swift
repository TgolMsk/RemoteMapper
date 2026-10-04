import Foundation
import Security

/// 「解锁屏幕」用的登录密码，存放在登录钥匙串（通用密码），配置文件、界面和日志里都不出现明文。
///
/// 钥匙串项的访问控制绑定到创建它的 App 签名：同一证书签名的新版本可以直接读取；
/// 签名变化后（例如 ad-hoc 签名的新构建）第一次读取会弹出钥匙串授权框，
/// 锁屏时没人能点，所以由 `prepareAccess()` 在 App 启动时提前触发。
public enum UnlockPassword {
    private static let service = "com.ws.RemoteMapper.unlock"
    private static var account: String { NSUserName() }

    public struct KeychainError: LocalizedError {
        let status: OSStatus
        public var errorDescription: String? {
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? L10n.format("错误码 %d", status)
            return L10n.format("钥匙串：%@", reason)
        }
    }

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// 是否已保存密码（只查属性，不读取密码，不会弹授权框）
    public static var isSet: Bool {
        SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    public static func save(_ password: String) throws {
        let data = Data(password.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "RemoteMapper 解锁密码"
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public static func delete() {
        SecItemDelete(query as CFDictionary)
    }

    /// 读取密码；未保存时返回 nil
    static func read() throws -> String? {
        var item = query
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return String(decoding: data, as: UTF8.self)
    }

    /// 在用户在场（未锁屏）时读一次，让可能出现的钥匙串授权框现在弹出，而不是在锁屏时
    public static func prepareAccess() {
        guard isSet else { return }
        _ = try? read()
    }
}
