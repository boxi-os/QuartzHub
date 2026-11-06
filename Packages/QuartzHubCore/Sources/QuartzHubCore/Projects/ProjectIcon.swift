import CryptoKit
import Darwin
import Foundation
import ImageIO
import Synchronization
import UniformTypeIdentifiers

/// The project's picture, which is the site's favicon: `quartz/static/icon.png`, the one file
/// `@quartz-community/favicon` reads (no options, hard-coded path). A port of
/// `projectIconService.ts` with ImageIO in place of Electron's `nativeImage`
/// (decisions/plugins-and-config.md, "Das Projektbild ist das Favicon der Seite").
///
/// - **A file is not a choice.** Quartz ships an `icon.png` in every project and every template an
///   `icon-dark.png`, so which one the user chose is recorded in `.quartz-gui/project-icon.json`,
///   and the displaced original is kept as `icon-original.png`. "Entfernen" restores it, because
///   the emitter reads `icon.png` unconditionally.
/// - **Normalized on the way in:** PNG and JPEG, at most 512 px on the longer edge, always a PNG; a
///   PNG that fits is copied byte for byte.
/// - **Thumbnails of 128 px**, kept until the file's mtime or size changes, so a refreshed project
///   list decodes nothing again. As PNG data, which the UI turns into an image.
public enum ProjectIcon {
  public struct Info: Equatable, Sendable {
    /// `icon.png` scaled down for display; nil when there is no readable one.
    public var thumbnail: Data?
    /// The light picture was chosen in QuartzHub or QuartzControl, and it is readable.
    public var custom: Bool
    /// The pixel size of `icon.png`; 0 when there is none.
    public var width: Int
    public var height: Int
    public var darkThumbnail: Data?
    /// `icon-dark.png` was chosen here; false for one a template brought.
    public var darkCustom: Bool
    /// `icon.png` is neither Quartz's own nor recorded as chosen (`hasUnrecordedIcon`).
    public var unrecorded: Bool
  }

  public enum Failure: Error, Equatable {
    /// Not .png, .jpg or .jpeg.
    case unsupportedFormat
    /// The right extension, but nothing ImageIO can decode (a text file, an SVG).
    case unreadable

    public var message: String {
      switch self {
      case .unsupportedFormat: L10n.t("main.projectIconUnsupportedFormat")
      case .unreadable: L10n.t("main.projectIconUnreadable")
      }
    }
  }

  static let maxStoredEdge = 512
  /// 36 px in the sidebar, 40 on the start page, doubled for a retina panel.
  static let thumbnailEdge = 128
  static let acceptedExtensions: Set<String> = ["png", "jpg", "jpeg"]
  /// The git blob id of the `icon.png` Quartz ships, one since the file was added (2023-05-30,
  /// `ad6ce0d`), measured in QuartzControl on 2026-09-24. A blob id so `git hash-object` checks it.
  static let quartzIconBlob = "b6656a7a819cf41ba6502b9eddf4e580617bbaba"

  static func iconPath(_ project: URL) -> URL { project.appendingPathComponent("quartz/static/icon.png") }
  static func darkIconPath(_ project: URL) -> URL { project.appendingPathComponent("quartz/static/icon-dark.png") }
  static func originalPath(_ project: URL) -> URL { QuartzGuiDirectory(project: project).file("icon-original.png") }

  // MARK: - Reading

  public static func info(project: URL) -> Info {
    let path = iconPath(project), dark = darkIconPath(project)
    let marker = readMarker(project)
    let size = pixelSize(path)
    let darkExists = exists(dark)
    return Info(
      thumbnail: thumbnail(path),
      custom: marker.custom && size != nil,
      width: size?.width ?? 0,
      height: size?.height ?? 0,
      darkThumbnail: darkExists ? thumbnail(dark) : nil,
      darkCustom: marker.customDark && darkExists,
      unrecorded: hasUnrecordedIcon(project: project)
    )
  }

  /// What the project list shows, or nil when the project shows Quartz's own icon. A picture
  /// nobody recorded counts: a template's mark is what the site shows.
  public static func customThumbnail(project: URL) -> Data? {
    let marker = readMarker(project)
    guard marker.custom || hasUnrecordedIcon(project: project) else { return nil }
    return thumbnail(iconPath(project))
  }

  /// The files under `quartz/static` that are the user's picture rather than a design, each only
  /// when it was recorded as chosen. A template import leaves these alone.
  public static func userChosenStaticFiles(project: URL) -> Set<String> {
    let marker = readMarker(project)
    var names: Set<String> = []
    if marker.custom { names.insert("icon.png") }
    if marker.customDark && exists(darkIconPath(project)) { names.insert("icon-dark.png") }
    return names
  }

  /// An `icon-dark.png` nobody recorded choosing: in practice a template's.
  public static func hasUnrecordedDarkIcon(project: URL) -> Bool {
    exists(darkIconPath(project)) && !readMarker(project).customDark
  }

  /// `icon.png` is neither Quartz's nor recorded. A project cloned through Git-Sync has the
  /// user's picture and no marker (`.quartz-gui/` is ignored); this cannot tell it from a picture an
  /// earlier template brought, so it protects nothing, it only lets the import's dry run name it.
  public static func hasUnrecordedIcon(project: URL) -> Bool {
    if readMarker(project).custom { return false }
    guard let data = try? Data(contentsOf: iconPath(project)) else { return false }
    return gitBlobId(data) != quartzIconBlob
  }

  // MARK: - Writing

  /// Writes `source` to `icon.png`, normalized. Only the first choice displaces something the
  /// project came with; after that the file being replaced is one of ours, and keeping it would
  /// overwrite the original held for "Entfernen".
  @discardableResult
  public static func set(project: URL, source: URL) throws -> Info {
    let image = try PreparedImage(source)
    let target = iconPath(project)
    let marker = readMarker(project)
    var hasOriginal = marker.hasOriginal
    if !marker.custom {
      if exists(target) {
        try QuartzGuiDirectory(project: project).create()
        try JSONStore.writeAtomic(Data(contentsOf: target), to: originalPath(project))
        hasOriginal = true
      } else {
        hasOriginal = false
      }
    }
    try image.store(to: target)
    try writeMarker(project, custom: true, hasOriginal: hasOriginal, customDark: marker.customDark)
    return info(project: project)
  }

  /// Puts back what the project had before a picture was chosen: a restore, not a delete.
  @discardableResult
  public static func clear(project: URL) throws -> Info {
    let marker = readMarker(project)
    let target = iconPath(project), original = originalPath(project)
    if marker.hasOriginal, exists(original) {
      try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONStore.writeAtomic(Data(contentsOf: original), to: target)
    } else if exists(target) {
      try FileManager.default.removeItem(at: target)
    }
    if exists(original) { try FileManager.default.removeItem(at: original) }
    // The dark picture is a choice of its own and outlives the light one.
    try writeMarker(project, custom: false, hasOriginal: false, customDark: marker.customDark)
    return info(project: project)
  }

  /// The picture for the dark scheme, normalized like the light one. Only the header image uses
  /// it; Quartz ships no file of this name, so removing it is a plain delete.
  @discardableResult
  public static func setDark(project: URL, source: URL) throws -> Info {
    try PreparedImage(source).store(to: darkIconPath(project))
    let marker = readMarker(project)
    try writeMarker(project, custom: marker.custom, hasOriginal: marker.hasOriginal, customDark: true)
    return info(project: project)
  }

  @discardableResult
  public static func clearDark(project: URL) throws -> Info {
    let dark = darkIconPath(project)
    if exists(dark) { try FileManager.default.removeItem(at: dark) }
    let marker = readMarker(project)
    try writeMarker(project, custom: marker.custom, hasOriginal: marker.hasOriginal, customDark: false)
    return info(project: project)
  }

  // MARK: - Marker

  struct Marker: Equatable {
    var custom: Bool
    var hasOriginal: Bool
    var customDark: Bool
  }

  static func readMarker(_ project: URL) -> Marker {
    let value = JSONStore.read(QuartzGuiDirectory(project: project).projectIcon, orEmpty: .object)
    let view = IconMarker(object: value.objectValue ?? JSONObject())
    return Marker(custom: view.custom, hasOriginal: view.hasOriginal,
                  customDark: view.customDark(darkIconExists: exists(darkIconPath(project))))
  }

  /// Whole, in QuartzControl's key order; nothing left to record removes the file, so a later
  /// read does not fall back to the guess for markers from before `customDark`.
  static func writeMarker(_ project: URL, custom: Bool, hasOriginal: Bool, customDark: Bool) throws {
    let dir = QuartzGuiDirectory(project: project)
    guard custom || customDark else {
      if exists(dir.projectIcon) { try FileManager.default.removeItem(at: dir.projectIcon) }
      return
    }
    try dir.create()
    try JSONStore.write(.object(JSONObject([
      ("custom", .bool(custom)), ("hasOriginal", .bool(hasOriginal)), ("customDark", .bool(customDark))
    ])), to: dir.projectIcon)
  }

  // MARK: - Images

  /// Checked now, written later: `set` moves the original aside in between, and only for a file
  /// that is known to be stored.
  struct PreparedImage {
    let source: URL
    let imageSource: CGImageSource
    let size: (width: Int, height: Int)
    let isPNG: Bool

    init(_ source: URL) throws {
      guard ProjectIcon.acceptedExtensions.contains(source.pathExtension.lowercased()) else { throw Failure.unsupportedFormat }
      guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
            CGImageSourceGetCount(imageSource) > 0,
            let size = ProjectIcon.pixelSize(imageSource),
            CGImageSourceCreateImageAtIndex(imageSource, 0, nil) != nil else { throw Failure.unreadable }
      self.source = source
      self.imageSource = imageSource
      self.size = size
      // The bytes decide, not the name: QuartzControl copied any ".png" that fit, a JPEG under
      // that name included.
      isPNG = (CGImageSourceGetType(imageSource) as String?) == UTType.png.identifier
    }

    func store(to target: URL) throws {
      try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      let fits = size.width <= ProjectIcon.maxStoredEdge && size.height <= ProjectIcon.maxStoredEdge
      // Atomic: a running dev server watches quartz/static and must not read half a file.
      if isPNG && fits {
        try JSONStore.writeAtomic(Data(contentsOf: source), to: target)
        return
      }
      guard let png = ProjectIcon.scaledPNG(imageSource, edge: ProjectIcon.maxStoredEdge) else { throw Failure.unreadable }
      try JSONStore.writeAtomic(png, to: target)
    }
  }

  /// A PNG that fits a square of `edge`, the aspect ratio kept. `MaxPixelSize` never scales up by
  /// itself (measured: a 40 × 30 JPEG with 512 stays 40 × 30, the test holds it). ImageIO applies
  /// the EXIF orientation of a photo as it scales (`WithTransform`).
  static func scaledPNG(_ source: CGImageSource, edge: Int) -> Data? {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: edge
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
  }

  static func pixelSize(_ source: CGImageSource) -> (width: Int, height: Int)? {
    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0 else { return nil }
    return (width, height)
  }

  static func pixelSize(_ url: URL) -> (width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { return nil }
    return pixelSize(source)
  }

  // MARK: - Thumbnail cache

  struct CacheEntry {
    var mtime: timespec
    var size: off_t
    var png: Data
  }

  static let cache = Mutex<[String: CacheEntry]>([:])
  /// How often a thumbnail was decoded, for the cache test.
  static let decodes = Atomic<Int>(0)

  static func thumbnail(_ url: URL) -> Data? {
    var info = stat()
    guard stat(url.path, &info) == 0 else { return nil }
    if let hit = cache.withLock({ $0[url.path] }), hit.mtime.tv_sec == info.st_mtimespec.tv_sec,
       hit.mtime.tv_nsec == info.st_mtimespec.tv_nsec, hit.size == info.st_size {
      return hit.png
    }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let png = scaledPNG(source, edge: thumbnailEdge) else { return nil }
    decodes.add(1, ordering: .relaxed)
    cache.withLock { $0[url.path] = CacheEntry(mtime: info.st_mtimespec, size: info.st_size, png: png) }
    return png
  }

  static func gitBlobId(_ data: Data) -> String {
    var hash = Insecure.SHA1()
    hash.update(data: Data("blob \(data.count)\0".utf8))
    hash.update(data: data)
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
  }

  static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
}
