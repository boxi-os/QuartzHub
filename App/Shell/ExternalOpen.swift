import AppKit
import QuartzHubCore
import SwiftUI

/// Everything QuartzHub hands to another program: the browser, the Finder, an editor. One way out,
/// so a measurement can see what a button would open without opening it (DEBUG,
/// `-QHOpenLog <file>`: one line per call, `open <address or path>`, `reveal <path>` or
/// `refused <address>`). Seven rows of docs/gleichstand.md stayed unmeasured because the click
/// would have opened the browser (2026-11-11).
///
/// An address goes to the system only as http(s), as QuartzControl's `setWindowOpenHandler` and
/// `will-navigate` allowed (`electron/main/index.ts`). A link in a preview comes from the site,
/// and a `file://` one would launch an app or run a `.command` without asking (Review 2026-11-11
/// (2), M2). QuartzHub's own folders and files go through `openFolder` and `openFile`, which take
/// a path, never an address from a web view.
@MainActor enum ExternalOpen {
  /// A web address in the browser; anything else is refused.
  static func open(_ url: URL) { // path boundary: an address, checked, handed on as it is
    guard isWeb(url) else { refuse(url); return }
    if logged("open", url) { return }
    NSWorkspace.shared.open(url)
  }

  /// A folder QuartzHub names, shown in the Finder. Rooted, not opened: a folder named `*.app`
  /// would launch.
  static func openFolder(_ path: String) {
    if logged("open", URL(fileURLWithPath: path, isDirectory: true)) { return } // path boundary: logged only
    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
  }

  /// A file QuartzHub names (a stylesheet), in the app the system has for its type.
  static func openFile(_ path: String) {
    let url = URL(fileURLWithPath: path) // path boundary: handed to the system as it is
    if logged("open", url) { return }
    NSWorkspace.shared.open(url)
  }

  /// The Finder with these items selected.
  static func reveal(_ urls: [URL]) { // path boundary: handed on as they are
    if urls.allSatisfy({ logged("reveal", $0) }) { return }
    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }

  /// For SwiftUI's `openURL` and `Link`, set on every window: release notes, repositories, the
  /// running server. The same rule as `open`.
  static let action = OpenURLAction { url in
    guard isWeb(url) else { refuse(url); return .discarded }
    return logged("open", url) ? .handled : .systemAction
  }

  static func isWeb(_ url: URL) -> Bool { // not a file path
    ["http", "https"].contains(url.scheme?.lowercased() ?? "")
  }

  /// Said in the log, as QuartzControl's "refused to navigate"; the scheme only, the rest may name
  /// a file of the user.
  private static func refuse(_ url: URL) { // path boundary
    NSLog("QuartzHub refused to open a %@ address", url.scheme ?? "relative")
    _ = logged("refused", url)
  }

  private static func logged(_ verb: String, _ url: URL) -> Bool { // path boundary
    #if DEBUG
    guard let log = LaunchArgument.string("QHOpenLog") else { return false }
    let target = url.isFileURL ? Posix.path(url) : url.absoluteString
    let line = Array("\(verb) \(target)\n".utf8)
    let fd = Darwin.open(log, O_WRONLY | O_APPEND | O_CREAT, 0o644)
    if fd >= 0 {
      _ = line.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
      close(fd)
    }
    return true
    #else
    return false
    #endif
  }
}
