import Foundation

/// "No network" for a measurement (DEBUG, `-QHOffline YES`): every URLSession QuartzHub makes
/// answers a request to another machine with `notConnectedToInternet`, what URLSession says with
/// the Wi-Fi off. Loopback still answers, as it does then (the server scan asks localhost). npm,
/// a child process, gets `npm_config_offline` (the theme catalog is `npm search`); git keeps the
/// network.
///
/// Turning the Wi-Fi off was the first idea and cannot work: the session that measures runs over
/// the same network (2026-11-11, the marketplace and theme catalog rows of docs/gleichstand.md).
public enum Offline {
  public static var isOn: Bool {
    #if DEBUG
    return LaunchArgument.string("QHOffline") == "YES"
    #else
    return false
    #endif
  }

  /// For a session's own configuration, before the session is made.
  public static func apply(_ configuration: URLSessionConfiguration) {
    guard isOn else { return }
    configuration.protocolClasses = [NotConnected.self] + (configuration.protocolClasses ?? [])
  }

  /// For `URLSession.shared`, which takes its classes from the registry; once per process.
  public static func registerForShared() {
    guard isOn else { return }
    _ = registered
  }

  private static let registered: Bool = {
    URLProtocol.registerClass(NotConnected.self)
    return true
  }()

  final class NotConnected: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
      guard let host = request.url?.host?.lowercased() else { return false }
      return !["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
      client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
  }
}
