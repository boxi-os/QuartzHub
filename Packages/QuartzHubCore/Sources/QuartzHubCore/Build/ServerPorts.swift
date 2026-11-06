import Darwin
import Foundation

/// The ports of a dev server: is one free, the next free one, waiting for one to open or close
/// (QuartzControl's `portState`, `nextFreePort`, `waitForPort`, `waitUntilFree` in buildService.ts).
public enum ServerPorts {
  public enum State: Sendable, Equatable {
    case free
    /// In use (EADDRINUSE on the bind, or something answers on loopback).
    case taken
    /// Not in use but not bindable either (EACCES below 1024, EADDRNOTAVAIL): no reason to move on.
    case unusable
  }

  /// How far a taken port moves before the start keeps the asked-for one and lets the spawn fail
  /// with the real error.
  public static let searchSpan = 100

  /// Two questions, because one is not enough on macOS: Quartz binds the wildcard address with
  /// SO_REUSEADDR (Node sets it), and under BSD rules that bind succeeds beside a server holding
  /// the same port on 127.0.0.1 alone, which the browser would then reach. So a port is free only if
  /// the wildcard bind works and nothing answers on loopback (QuartzControl, review 2026-10-13).
  public static func state(_ port: Int) async -> State {
    switch bindWildcard(port) {
    case .some(let error) where error == EADDRINUSE: return .taken
    case .some: return .unusable
    case .none: break
    }
    async let v4 = answers(host: "127.0.0.1", port: port, timeoutMs: 300)
    async let v6 = answers(host: "::1", port: port, timeoutMs: 300)
    let (a, b) = await (v4, v6)
    return a || b ? .taken : .free
  }

  /// The first free port from `start` on that is not in `taken` (ports of QuartzHub's own servers,
  /// which count without asking: one spawned a moment ago may not have bound yet). nil when the
  /// search ends or meets an unusable port.
  public static func nextFree(from start: Int, taken: Set<Int>) async -> Int? {
    var port = start
    while port < start + searchSpan && port <= 65535 {
      defer { port += 1 }
      if taken.contains(port) { continue }
      switch await state(port) {
      case .free: return port
      case .unusable: return nil
      case .taken: continue
      }
    }
    return nil
  }

  /// Retries a connect to 127.0.0.1 every 250 ms while `waiting()` holds; true once it opened.
  /// No deadline: a server listens only after its first build, which has no upper bound
  /// (QuartzControl measured 195 to 210 s on an emulated VM, and a fixed two minutes left such a
  /// server on "starting" for good). One that never listens ends, and `waiting` says so.
  public static func waitForOpen(_ port: Int, while waiting: @Sendable () async -> Bool) async -> Bool {
    while await waiting() {
      if await answers(host: "127.0.0.1", port: port, timeoutMs: 1000) { return true }
      try? await Task.sleep(for: .milliseconds(250))
    }
    return false
  }

  /// Until all of `ports` are free, at most `timeout`: a restart's node may hold its sockets a
  /// moment after npx has ended.
  public static func waitUntilFree(_ ports: [Int], timeout: Duration) async {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      var all = true
      for port in ports where await state(port) != .free { all = false }
      if all { return }
      try? await Task.sleep(for: .milliseconds(100))
    }
  }

  /// errno of binding the IPv6 wildcard (dual stack, as Node's `listen(port)`) with SO_REUSEADDR;
  /// nil when it bound.
  static func bindWildcard(_ port: Int) -> Int32? {
    let fd = socket(AF_INET6, SOCK_STREAM, 0)
    guard fd >= 0 else { return errno }
    defer { close(fd) }
    var on: Int32 = 1, off: Int32 = 0
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
    setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &off, socklen_t(MemoryLayout<Int32>.size))
    var address = sockaddr_in6()
    address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
    address.sin6_family = sa_family_t(AF_INET6)
    address.sin6_port = in_port_t(UInt16(port).bigEndian)
    address.sin6_addr = in6addr_any
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) }
    }
    if bound != 0 { return errno }
    return listen(fd, 1) == 0 ? nil : errno
  }

  /// A connect to host:port within `timeoutMs`.
  static func answers(host: String, port: Int, timeoutMs: Int32) async -> Bool {
    await withCheckedContinuation { continuation in
      DispatchQueue.global().async { continuation.resume(returning: connects(host, port, timeoutMs)) }
    }
  }

  static func connects(_ host: String, _ port: Int, _ timeoutMs: Int32) -> Bool {
    var hints = addrinfo(ai_flags: AI_NUMERICHOST | AI_NUMERICSERV, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM,
                         ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
    var info: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, String(port), &hints, &info) == 0, let address = info else { return false }
    defer { freeaddrinfo(info) }
    let fd = socket(address.pointee.ai_family, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    if connect(fd, address.pointee.ai_addr, address.pointee.ai_addrlen) == 0 { return true }
    guard errno == EINPROGRESS else { return false }
    var poller = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
    guard poll(&poller, 1, timeoutMs) == 1 else { return false }
    var error: Int32 = 0
    var length = socklen_t(MemoryLayout<Int32>.size)
    return getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0 && error == 0
  }
}
