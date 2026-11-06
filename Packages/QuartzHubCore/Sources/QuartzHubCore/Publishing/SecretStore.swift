import Foundation
import Synchronization

/// Where QuartzHub keeps the secret half of a connection and of a relay: one generic password per
/// secret. The app uses `KeychainSecrets`; the tests use `MemorySecrets`, so no test touches the
/// user's Keychain.
public protocol SecretStore: Sendable {
  /// The secret, or nil when there is no item.
  func read(account: String) throws(Keychain.Failure) -> String?
  func write(_ secret: String, account: String, label: String) throws(Keychain.Failure)
  /// Nothing to delete is no failure.
  func delete(account: String) throws(Keychain.Failure)
}

/// The login Keychain under the service "QuartzHub" (`Keychain`), the same items the takeover from
/// QuartzControl writes: `connection:<id>` and `relay:<projectId>`.
public struct KeychainSecrets: SecretStore {
  public init() {}

  public func read(account: String) throws(Keychain.Failure) -> String? {
    do throws(Keychain.Failure) {
      return try Keychain.read(service: Keychain.service, account: account)
    } catch {
      if error == .notFound { return nil }
      throw error
    }
  }

  public func write(_ secret: String, account: String, label: String) throws(Keychain.Failure) {
    try Keychain.write(secret, account: account, label: label)
  }

  public func delete(account: String) throws(Keychain.Failure) {
    try Keychain.delete(account: account)
  }
}

/// A store in memory, for tests and for a caller that wants to see what would be written.
public final class MemorySecrets: SecretStore {
  private let items = Mutex<[String: String]>([:])
  /// Answered by `read` instead of the item, to stand for a "Deny" in the system's dialog.
  private let failure = Mutex<Keychain.Failure?>(nil)

  public init(_ items: [String: String] = [:]) { self.items.withLock { $0 = items } }

  public var all: [String: String] { items.withLock { $0 } }

  public func fail(with failure: Keychain.Failure?) { self.failure.withLock { $0 = failure } }

  public func read(account: String) throws(Keychain.Failure) -> String? {
    if let failure = failure.withLock({ $0 }) { throw failure }
    return items.withLock { $0[account] }
  }

  public func write(_ secret: String, account: String, label: String) throws(Keychain.Failure) {
    if let failure = failure.withLock({ $0 }) { throw failure }
    items.withLock { $0[account] = secret }
  }

  public func delete(account: String) throws(Keychain.Failure) {
    if let failure = failure.withLock({ $0 }) { throw failure }
    _ = items.withLock { $0.removeValue(forKey: account) }
  }
}
