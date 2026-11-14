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
  /// Whether there is an item, without reading the secret: in the file-based login Keychain only
  /// reading the data meets the item's access list, so this never brings up the system's dialog.
  func contains(account: String) throws(Keychain.Failure) -> Bool
}

extension SecretStore {
  public func contains(account: String) throws(Keychain.Failure) -> Bool { try read(account: account) != nil }
}

/// The login Keychain under the service "QuartzHub" (`Keychain`): `connection:<id>` and
/// `relay:<projectId>`.
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

  public func contains(account: String) throws(Keychain.Failure) -> Bool {
    try Keychain.contains(service: Keychain.service, account: account)
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

  /// How often a secret was read, as the Keychain would meet its access list (and ask).
  public var reads: Int { readCount.withLock { $0 } }
  private let readCount = Mutex(0)

  public func read(account: String) throws(Keychain.Failure) -> String? {
    readCount.withLock { $0 += 1 }
    if let failure = failure.withLock({ $0 }) { throw failure }
    return items.withLock { $0[account] }
  }

  public func contains(account: String) throws(Keychain.Failure) -> Bool {
    if let failure = failure.withLock({ $0 }) { throw failure }
    return items.withLock { $0[account] != nil }
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
