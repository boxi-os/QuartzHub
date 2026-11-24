import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The catalog's screenshots, small: Obsidian's list points at a picture in each theme's repo,
/// some of them several MB (`maxBytes`). Each is fetched when its row appears, scaled down once to
/// `maxPixels` on its long side and kept as a JPEG in the profile (`theme-docs/screenshots/`), so
/// the list scrolls without the network after the first time (docs/plan-themes-core-3.md, step 6).
///
/// Offline (`-QHOffline`) is a normal state: a kept copy answers, otherwise nil. A copy older than
/// `lifetime` is asked for again and stays the answer when that fails. A failed address is not
/// asked again for a quarter of an hour, so scrolling past it does not ask at every appearance.
public actor ThemeScreenshots {
  /// Wide enough for the inspector's large picture on a Retina screen; the list shows it smaller.
  public static let maxPixels = 800
  static let lifetime: TimeInterval = 7 * 24 * 60 * 60
  static let retryAfterFailure: TimeInterval = 15 * 60
  /// Above the largest screenshot measured, small enough that a wrong address does not fill the
  /// memory. Measured 2026-11-24 on 250 of the list's 1064 themes: median 0.13 MB, largest 44.9 MB,
  /// then 3.6 MB. 981 are PNG, 72 JPEG, 6 WebP, one GIF, one SVG (which ImageIO does not read).
  static let maxBytes = 64 * 1024 * 1024
  /// The decoder's limit, read from the file's header before decoding (conventions: every
  /// decompression gets a limit, and the file does not set it).
  static let maxSourcePixels = 16_384
  static let memoryLimit = 300

  let session: URLSession
  let directory: String
  let now: @Sendable () -> Date
  private var memory: [String: Data] = [:]
  private var memoryOrder: [String] = []
  private var failed: [String: Date] = [:]
  private var loading: [String: Task<Data?, Never>] = [:]

  public init(profile: ProfileDirectory = .quartzHub, configuration: URLSessionConfiguration = .ephemeral, timeout: Duration = .seconds(30),
              now: @escaping @Sendable () -> Date = Date.init) {
    let configuration = configuration.copy() as! URLSessionConfiguration
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    let seconds = Double(timeout.components.seconds)
    configuration.timeoutIntervalForRequest = seconds
    configuration.timeoutIntervalForResource = seconds
    configuration.httpMaximumConnectionsPerHost = 4
    Offline.apply(configuration)
    session = URLSession(configuration: configuration)
    directory = profile.file("theme-docs/screenshots")
    self.now = now
  }

  /// The scaled JPEG, or nil when neither the network nor a copy has it or it is no image.
  public func image(_ address: String) async -> Data? {
    if let kept = memory[address] { return kept }
    if let running = loading[address] { return await running.value }
    let task = Task { await self.load(address) }
    loading[address] = task
    let result = await task.value
    loading[address] = nil
    if let result { remember(address, result) }
    return result
  }

  func file(_ address: String) -> String {
    let digest = SHA256.hash(data: Data(address.utf8)).map { String(format: "%02x", $0) }.joined()
    return NodePath.join(directory, String(digest.prefix(32)) + ".jpg")
  }

  private func load(_ address: String) async -> Data? {
    let time = now()
    let path = file(address)
    let copy = readCopy(path)
    if let copy, time.timeIntervalSince(copy.modified) < Self.lifetime { return copy.data }
    if let failedAt = failed[address], time.timeIntervalSince(failedAt) < Self.retryAfterFailure { return copy?.data }
    guard let url = URL(string: address), url.scheme == "https" || url.scheme == "http",
          let (data, response) = try? await session.data(from: url), let http = response as? HTTPURLResponse,
          (200..<300).contains(http.statusCode), data.count <= Self.maxBytes, let scaled = Self.scale(data) else {
      failed[address] = time
      return copy?.data
    }
    failed[address] = nil
    try? Posix.mkdirs(directory)
    try? JSONStore.writeAtomic(scaled, to: path)
    return scaled
  }

  private func readCopy(_ path: String) -> (data: Data, modified: Date)? {
    var info = stat()
    guard stat(path, &info) == 0, info.st_size > 0, info.st_size <= Self.maxBytes, let data = try? Posix.read(path) else { return nil }
    return (data, Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9))
  }

  private func remember(_ address: String, _ data: Data) {
    if memory[address] == nil { memoryOrder.append(address) }
    memory[address] = data
    while memoryOrder.count > Self.memoryLimit { memory[memoryOrder.removeFirst()] = nil }
  }

  /// The picture scaled to `maxPixels` on its long side (never up), as a JPEG; nil for anything
  /// ImageIO does not read as an image or whose header names more than `maxSourcePixels` a side.
  static func scale(_ data: Data) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
          CGImageSourceGetCount(source) > 0,
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
          width > 0, height > 0, width <= maxSourcePixels, height <= maxSourcePixels else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: min(maxPixels, max(width, height)),
      kCGImageSourceShouldCacheImmediately: true
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    let out = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return out as Data
  }
}
