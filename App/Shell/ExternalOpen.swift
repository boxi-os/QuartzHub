import AppKit
import QuartzHubCore
import SwiftUI

/// Everything QuartzHub hands to another program: the browser, the Finder, an editor. One way out,
/// so a measurement can see what a button would open without opening it (DEBUG,
/// `-QHOpenLog <file>`: one line per call, `open <address or path>` or `reveal <path>`). Seven rows
/// of docs/gleichstand.md stayed unmeasured because the click would have opened the browser
/// (2026-11-11).
@MainActor enum ExternalOpen {
  static func open(_ url: URL) { // path boundary: an address or a file, handed on as it is
    if logged("open", url) { return }
    NSWorkspace.shared.open(url)
  }

  /// The Finder with these items selected.
  static func reveal(_ urls: [URL]) { // path boundary: handed on as they are
    if urls.allSatisfy({ logged("reveal", $0) }) { return }
    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }

  /// For SwiftUI's `openURL` and `Link`, set on every window.
  static let action = OpenURLAction { url in logged("open", url) ? .handled : .systemAction }

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
