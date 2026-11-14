import Foundation
import Security

/// Generic passwords in the login Keychain. QuartzHub keeps one item per secret under the service
/// "QuartzHub" (account `connection:<id>`, `relay:<projectId>`).
///
/// The file-based login Keychain, not the data-protection one: that needs a keychain-access-group
/// entitlement, which an ad hoc signature cannot carry. The price: an item's access list names the
/// app's signature, so after a new ad hoc build macOS asks again.
public enum Keychain {
  public enum Failure: Error, Equatable {
    case notFound
    /// The user declined the system prompt (or it could not be shown).
    case denied
    case other(OSStatus)

    init(_ status: OSStatus) {
      switch status {
      case errSecItemNotFound: self = .notFound
      case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed: self = .denied
      default: self = .other(status)
      }
    }
  }

  public static let service = "QuartzHub"

  public static func read(service: String, account: String?) throws(Failure) -> String {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    if let account { query[kSecAttrAccount as String] = account }
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess else { throw Failure(status) }
    guard let data = result as? Data, let text = String(data: data, encoding: .utf8) else { throw .other(errSecDecode) }
    return text
  }

  /// Whether an item exists, without reading its secret (and so without a prompt); a Keychain that
  /// cannot be asked is a failure, not "no item".
  public static func contains(service: String, account: String) throws(Failure) -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnAttributes as String: true
    ]
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    if status == errSecSuccess { return true }
    if status == errSecItemNotFound { return false }
    throw Failure(status)
  }

  /// Whether an item exists, without reading its secret (and so without a prompt).
  public static func exists(service: String, account: String) -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnAttributes as String: true
    ]
    return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
  }

  public static func write(_ secret: String, service: String = service, account: String, label: String? = nil) throws(Failure) {
    let match: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
    let data = Data(secret.utf8)
    let status = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecSuccess { return }
    guard status == errSecItemNotFound else { throw Failure(status) }
    var add = match
    add[kSecValueData as String] = data
    if let label { add[kSecAttrLabel as String] = label }
    let added = SecItemAdd(add as CFDictionary, nil)
    guard added == errSecSuccess else { throw Failure(added) }
  }

  public static func delete(service: String = service, account: String) throws(Failure) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status) }
  }
}
