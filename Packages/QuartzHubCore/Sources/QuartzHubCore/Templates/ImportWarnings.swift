import Foundation

/// The sentences for a template import's warnings, as QuartzControl's `ImportOutcome.tsx` made
/// them. Warnings arrive as `kind:detail`, not as sentences (an import of a 48-plugin package makes
/// 45 near-identical ones), and are grouped by kind: "45 Plugins übersprungen" is one line.
///
/// A kind whose sentence spells out the detail gets one line per case instead (at most six, the
/// sixth with "und n weitere Fälle"). Which kinds those are is asked of the catalog with a probe,
/// as QuartzControl asked i18next, not kept as a list: the sentence with the probe as detail
/// either contains it or not.
public enum ImportWarnings {
  static let detailsShown = 6
  static let probe = "\u{2063}qh-detail\u{2063}"

  public static func lines(_ warnings: [String], language: String = L10n.language) -> [String] {
    var order: [String] = []
    var details: [String: [String]] = [:]
    for warning in warnings {
      let kind = warning.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
      // `warning.slice(kind.length + 1)`: everything after the first colon, "" without one.
      let detail = warning.count > kind.count ? String(warning.dropFirst(kind.count + 1)) : ""
      if details[kind] == nil { order.append(kind) }
      details[kind, default: []].append(detail)
    }
    var lines: [String] = []
    for kind in order {
      let list = details[kind]!
      if sentence(kind, count: 1, detail: probe, language).contains(probe) {
        for (index, detail) in list.prefix(detailsShown).enumerated() {
          var line = sentence(kind, count: 1, detail: detail, language)
          if index == detailsShown - 1, list.count > detailsShown {
            line += " " + L10n.t(in: language, "templates.warningsMore", count: list.count - detailsShown)
          }
          lines.append(line)
        }
      } else {
        var line = sentence(kind, count: list.count, detail: list[0], language)
        if list.count > 1 {
          line += " — " + list.prefix(detailsShown).joined(separator: ", ") + (list.count > detailsShown ? " …" : "")
        }
        lines.append(line)
      }
    }
    return lines
  }

  /// `t(['templates.warnings.<kind>', 'templates.warnings.unknown'], { count, detail, kind })`,
  /// with the keys spelled out so `qh-check i18n` can see them.
  static func sentence(_ kind: String, count: Int, detail: String, _ language: String) -> String {
    let args = ["count": String(count), "detail": detail, "kind": kind]
    return switch kind {
    case "appearanceSkipped": L10n.t(in: language, "templates.warnings.appearanceSkipped", args, count: count)
    case "contentIsSymlink": L10n.t(in: language, "templates.warnings.contentIsSymlink", args, count: count)
    case "contentSkipped": L10n.t(in: language, "templates.warnings.contentSkipped", args, count: count)
    case "fileOutsideProject": L10n.t(in: language, "templates.warnings.fileOutsideProject", args, count: count)
    case "fontRemoved": L10n.t(in: language, "templates.warnings.fontRemoved", args, count: count)
    case "fontSkipped": L10n.t(in: language, "templates.warnings.fontSkipped", args, count: count)
    case "frameFailed": L10n.t(in: language, "templates.warnings.frameFailed", args, count: count)
    case "frameSkipped": L10n.t(in: language, "templates.warnings.frameSkipped", args, count: count)
    case "layoutSkipped": L10n.t(in: language, "templates.warnings.layoutSkipped", args, count: count)
    case "missingKey": L10n.t(in: language, "templates.warnings.missingKey", args, count: count)
    case "packageUnreadable": L10n.t(in: language, "templates.warnings.packageUnreadable", args, count: count)
    case "partFailed": L10n.t(in: language, "templates.warnings.partFailed", args, count: count)
    case "partUnreadable": L10n.t(in: language, "templates.warnings.partUnreadable", args, count: count)
    case "pluginInstallFailed": L10n.t(in: language, "templates.warnings.pluginInstallFailed", args, count: count)
    case "pluginSkipped": L10n.t(in: language, "templates.warnings.pluginSkipped", args, count: count)
    case "pluginUnsupported": L10n.t(in: language, "templates.warnings.pluginUnsupported", args, count: count)
    case "presetSkipped": L10n.t(in: language, "templates.warnings.presetSkipped", args, count: count)
    case "projectIconKept": L10n.t(in: language, "templates.warnings.projectIconKept", args, count: count)
    case "staticSkipped": L10n.t(in: language, "templates.warnings.staticSkipped", args, count: count)
    case "styleFileSkipped": L10n.t(in: language, "templates.warnings.styleFileSkipped", args, count: count)
    case "themeInstallFailed": L10n.t(in: language, "templates.warnings.themeInstallFailed", args, count: count)
    case "themeSkipped": L10n.t(in: language, "templates.warnings.themeSkipped", args, count: count)
    case "translationFailed": L10n.t(in: language, "templates.warnings.translationFailed", args, count: count)
    default: L10n.t(in: language, "templates.warnings.unknown", args, count: count)
    }
  }
}
