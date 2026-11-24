import Foundation

/// What a build's log says about the theme: core 3 that cannot load its theme does not stop the
/// build. Quartz skips the plugin, ends with exit 0 and a site without theme, and says so in two
/// lines (measured with Quartz 5.2.2 and core 3.1.1, `theme: Minmal`):
///
/// ```
/// ✗ @quartz-themes/core@3.1.1 was skipped: it failed to initialise: theme "Minmal" is not in …
/// ✗ 1 error — the build continued, but parts of the site may be missing:
/// ```
///
/// Vorschau & Build reads them to send the user to the theme (docs/plan-themes-core-3.md, step 0
/// and 6). The consoles keep up to 999 lines of several runs; a run starts with Quartz's banner
/// („Quartz v5.2.2“), and only the newest run counts.
public enum ThemeBuildLog {
  static let banner = #"\A\s*Quartz v\d"#
  static let skipped = #"\A\s*✗\s+@quartz-themes/core(?:@[^\s]+)?\s+was skipped:\s*(?:it failed to initiali[sz]e:\s*)?(.*)\z"#

  /// core's reason when the newest run in `chunks` skipped the theme plugin, else nil. The chunks
  /// are the console's, as the process wrote them: a line may be cut in two or share a chunk.
  public static func skippedReason(_ chunks: [String]) -> String? {
    var reason: String?
    for raw in JSText.split(chunks.joined(), "\n") {
      let line = JSText.replaceAll(raw, "\u{1B}\\[[0-9;]*[A-Za-z]|\r\\z", with: "")
      if JSText.test(line, banner) {
        reason = nil
      } else if reason == nil, let match = JSText.matches(line, skipped).first {
        reason = JS.trim(match.groups[1] ?? "")
      }
    }
    return reason
  }
}
