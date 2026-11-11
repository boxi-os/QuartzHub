import Foundation

/// What `quartz plugin doctor` (Quartz 5.1, `handlePluginDoctor` in cli/plugin-git-handlers.js)
/// says, per line: QuartzHub asks the project's own check instead of rebuilding it (deprecated
/// plugins, `quartzVersion` requirements, packages not installed, options the manifest refuses).
///
/// Its lines are `✗ <subject>: <message>` (error) or `⚠ …` (warning), the subject left out where
/// the message starts with the plugin (`<name>[@<version>] requires Quartz …`, `<name> is
/// deprecated: …`), each followed by an optional `    → <hint>`. Informational lines (`ℹ`) only
/// come with --verbose. The text stays Quartz's (English); QuartzHub only sorts it to the plugins.
public struct PluginDoctorReport: Equatable, Sendable {
  public enum Severity: String, Equatable, Sendable { case error, warning }

  public struct Finding: Equatable, Sendable {
    public var severity: Severity
    /// `crawl-links`, `quartz.lock.json`, `plugins[3]`; nil when the message names the plugin itself.
    public var subject: String?
    public var message: String
    public var hint: String?
  }

  public var findings: [Finding]

  public init(findings: [Finding]) {
    self.findings = findings
  }

  public static func parse(_ output: String) -> PluginDoctorReport {
    let plain = output.replacing(/\x1b\[[0-9;]*m/, with: "")
    var findings: [Finding] = []
    for raw in plain.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = String(raw)
      if let hint = line.firstMatch(of: /^\s+→ (.*)$/), !findings.isEmpty, findings[findings.count - 1].hint == nil {
        findings[findings.count - 1].hint = String(hint.1)
        continue
      }
      let severity: Severity
      if line.hasPrefix("✗ ") { severity = .error } else if line.hasPrefix("⚠ ") { severity = .warning } else { continue }
      let body = String(line.dropFirst(2))
      // "<subject>: <message>", where a subject has no blank; else the whole line is the message.
      if let match = body.firstMatch(of: /^([^\s:]+): (.+)$/) {
        findings.append(Finding(severity: severity, subject: String(match.1), message: String(match.2)))
      } else {
        findings.append(Finding(severity: severity, subject: nil, message: body))
      }
    }
    return PluginDoctorReport(findings: findings)
  }

  /// The plugins QuartzHub enters more than once on purpose, one entry per navigation or box.
  /// Quartz renders such a plugin once per entry ("its component is rendered once per entry", a
  /// warning of the 5.1 build), while doctor calls the second entry an error ("configured twice —
  /// both copies would be loaded"); that finding is left out for them.
  static let instancePlugins: Set<String> = ["quartz-navigations", "quartz-layout-box"]

  /// The findings about one plugin, by the name QuartzHub derives from its source. Quartz labels
  /// an npm package by its whole name (`@quartz-community/hard-line-breaks`), a git plugin by
  /// its last segment, as QuartzHub does.
  public func findings(for name: String) -> [Finding] {
    guard !name.isEmpty else { return [] }
    let names = { (label: Substring) in label == name || label.hasSuffix("/\(name)") }
    return findings.filter { finding in
      if Self.instancePlugins.contains(name), finding.message.hasPrefix("configured twice") { return false }
      if let subject = finding.subject { return names(Substring(subject)) }
      // "<label>[@<version>] requires …": the version goes, a scope's leading "@" stays.
      guard var label = finding.message.split(separator: " ", maxSplits: 1).first else { return false }
      if let at = label.lastIndex(of: "@"), at != label.startIndex { label = label[..<at] }
      return names(label)
    }
  }
}
