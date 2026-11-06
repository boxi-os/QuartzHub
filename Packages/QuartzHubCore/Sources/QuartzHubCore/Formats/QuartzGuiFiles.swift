import Foundation

// The JSON files in <project>/.quartz-gui/ that both apps share (docs/formats.md, "In
// .quartz-gui/"; details with file:line in docs/formats/quartz-gui.md). They keep QuartzControl
// 1.3's form, so each view reads with its rules and writes back into the object it read.

/// `<project>/.quartz-gui/`. Only locates; creating it (with the .gitignore line) belongs to the
/// first writer, in Phase 3. "Ein Lesepfad legt nie .quartz-gui/ an."
public struct QuartzGuiDirectory: Sendable {
  public let project: String
  public init(project: String) { self.project = project }

  public var path: String { "\(project)/.quartz-gui" }
  public func file(_ name: String) -> String { "\(path)/\(name)" }

  public var publishTargets: String { file("publish-targets.json") }
  public var projectPrefs: String { file("project-prefs.json") }
  public var layoutBreakpoints: String { file("layout-breakpoints.json") }
  public var themePresets: String { file("theme-presets.json") }
  public var formsRelay: String { file("forms-relay.json") }
  public var projectIcon: String { file("project-icon.json") }
  public var coreUpdate: String { file("core-update.json") }
  public var snapshotSettings: String { file("snapshot-settings.json") }
  public func deployManifest(_ key: String) -> String { file("deploy-manifest-\(key).json") }
}

/// One entry of `publish-targets.json` (`shared/ipc-contract.ts` `PublishTarget`).
public struct PublishTarget: JSONView {
  public var object: JSONObject
  public init(object: JSONObject) { self.object = object }

  public enum DestinationType: String, Sendable {
    case sftp, ftp, folder, webhook, gitBranch = "git-branch", document
  }

  public var id: String { string("id") ?? "" }
  public var name: String { string("name") ?? "" }
  /// Missing for folder, git-branch and document targets.
  public var connectionId: String? { string("connectionId") }
  public var destination: JSONObject { object["destination"]?.objectValue ?? JSONObject() }
  public var destinationType: DestinationType? { destination["type"]?.stringValue.flatMap(DestinationType.init) }
  public var excludes: [String] { strings("excludes") ?? [] }
  public var withDocuments: [String] { strings("withDocuments") ?? [] }
}

/// `project-prefs.json`. `outputDir` '' means Quartz's own `public/`; it may be absolute.
public struct ProjectPrefs: JSONView {
  public var object: JSONObject
  public init(object: JSONObject) { self.object = object }

  public var outputDir: String {
    get { string("outputDir") ?? "" }
    set { set("outputDir", newValue) }
  }
}

/// `layout-breakpoints.json`: the max-width thresholds of the generated frame media queries.
public struct FrameBreakpointWidths: JSONView {
  public var object: JSONObject
  public init(object: JSONObject) { self.object = object }

  public static let defaults = (tablet: 1200.0, mobile: 800.0)  // shared/gridFrameCss.ts

  /// `getBreakpointWidths`: `Number(raw.x)`; not finite, or mobile not below tablet, is the default.
  public var widths: (tablet: Double, mobile: Double) {
    let tablet = JS.toNumber(object["tablet"])
    let mobile = JS.toNumber(object["mobile"])
    guard tablet.isFinite, mobile.isFinite, mobile < tablet else { return Self.defaults }
    return (tablet, mobile)
  }
}

/// One entry of `theme-presets.json`. `options` is a loose object (`z.looseObject`).
public struct ThemePreset: JSONView {
  public var object: JSONObject
  public init(object: JSONObject) { self.object = object }

  public var id: String { string("id") ?? "" }
  public var name: String { string("name") ?? "" }
  public var createdAt: String? { string("createdAt") }
  public var baseThemeId: String? { string("baseThemeId") }
  public var options: JSONObject { object["options"]?.objectValue ?? JSONObject() }
}

/// `forms-relay.json`: the quartz-forms relay's settings that are not secret, and the last upload.
public struct RelayFile: JSONView {
  public var object: JSONObject
  public init(object: JSONObject) { self.object = object }

  /// `DEFAULT_RELAY` in formsService.ts; the read is `{ ...DEFAULT_RELAY, ...file.settings }`.
  public static let defaultSettings = JSONObject([
    ("subdir", .string("forms")),
    ("from", .string("")),
    ("allowedOrigins", .array([])),
    ("subjectPrefix", .string("")),
    ("mailer", .string("mail")),
    ("sendmailPath", .string("/usr/sbin/sendmail -t -i")),
    ("counterDir", .string("")),
    ("configReadable", .bool(false)),
    ("envelopeSender", .bool(true))
  ])

  /// The stored settings over the defaults, as QuartzControl spreads them (a key in the file wins,
  /// even with a value of the wrong type).
  public var settings: JSONObject {
    var merged = Self.defaultSettings
    for key in object["settings"]?.objectValue?.keys ?? [] { merged[key] = object["settings"]?[key] }
    return merged
  }

  public var lastUpload: JSONObject? { object["lastUpload"]?.objectValue }
  public var removedAt: String? { string("removedAt") }
}

/// `project-icon.json`: whether icon.png / icon-dark.png were chosen in the app.
public struct IconMarker: JSONView {
  public var object: JSONObject
  public init(object: JSONObject) { self.object = object }

  public var custom: Bool { isTrue("custom") }
  public var hasOriginal: Bool { isTrue("hasOriginal") }
  /// A marker from before `customDark`: the dark picture is the user's when a light one was
  /// recorded and `quartz/static/icon-dark.png` exists (`readMarker`).
  public func customDark(darkIconExists: Bool) -> Bool {
    object["customDark"]?.boolValue ?? (custom && darkIconExists)
  }
}

/// `core-update.json`: what a core update still has to do (`readPendingInstall` in updateService.ts).
public struct PendingInstall: JSONView {
  public var object: JSONObject
  public init(object: JSONObject) { self.object = object }

  public static let sections: Set<String> = ["dependencies", "devDependencies", "optionalDependencies", "peerDependencies"]

  /// The empty state `clearInstallPending` writes, in its key order.
  public static var cleared: PendingInstall {
    PendingInstall(object: JSONObject([
      ("installPendingFor", .string("")),
      ("reinstall", .array([])),
      ("filesAtHead", .bool(false)),
      ("installFailed", .bool(false)),
      ("putBack", .array([]))
    ]))
  }

  private static func safe(_ value: JSONValue?) -> String? {
    guard let string = value?.stringValue, !string.isEmpty, !string.hasPrefix("-") else { return nil }
    return string
  }

  /// The full hash of the merge commit, or '' when nothing is pending (40 hex for SHA-1, 64 for SHA-256).
  public var head: String {
    guard let value = string("installPendingFor"),
          value.wholeMatch(of: /[0-9a-f]{40}([0-9a-f]{24})?/) != nil else { return "" }
    return value
  }

  public struct Package: Equatable, Sendable {
    public let name: String
    public let section: String
    public let range: String
  }

  public var reinstall: [Package] { reinstallEntries.compactMap(Self.package) }

  /// The entries of `reinstall` that pass, as they are in the file: QuartzControl filters the raw
  /// objects and writes those back, extra keys and all.
  var reinstallEntries: [JSONValue] {
    (object["reinstall"]?.arrayValue ?? []).filter { Self.package($0) != nil }
  }

  private static func package(_ entry: JSONValue) -> Package? {
    guard let name = safe(entry["name"]), let range = safe(entry["range"]),
          let section = entry["section"]?.stringValue, sections.contains(section) else { return nil }
    return Package(name: name, section: section, range: range)
  }

  public var filesAtHead: Bool { isTrue("filesAtHead") }
  public var installFailed: Bool { isTrue("installFailed") }
  public var putBack: [String] { (object["putBack"]?.arrayValue ?? []).compactMap(Self.safe) }

  /// `noteInstallSucceeded`: an `npm install` over the whole project went through outside a core
  /// update (the one caller is duplicating). The copy inherits the note with its commit, and with
  /// `installFailed` it said "npm install failed" a second after its own install had not
  /// (QuartzControl's twenty-sixth review, finding 5). Only that field changes; the rest is
  /// written the way `markInstallPending` writes it. Nil when there is nothing to change.
  public func afterInstallSucceeded() -> PendingInstall? {
    guard !head.isEmpty, installFailed else { return nil }
    let names = Set(reinstall.map(\.name))
    var seen = Set<String>()
    let putBack = putBack.filter { seen.insert($0).inserted && names.contains($0) }
    return PendingInstall(object: JSONObject([
      ("installPendingFor", .string(head)),
      ("reinstall", .array(reinstallEntries)),
      ("filesAtHead", .bool(filesAtHead)),
      ("installFailed", .bool(false)),
      ("putBack", .array(putBack.map(JSONValue.string)))
    ]))
  }
}

/// `snapshot-settings.json`. Not a jsonStore file: QuartzControl reads it with a bare JSON.parse
/// and treats any failure as "never saved", without moving it aside.
public struct SnapshotSettingsFile: JSONView {
  public var object: JSONObject
  public init(object: JSONObject) { self.object = object }

  /// `contentIsSymlink ? false : (stored.includeContent ?? contentExists)`.
  public func includeContent(contentExists: Bool, contentIsSymlink: Bool) -> Bool {
    if contentIsSymlink { return false }
    guard let stored = object["includeContent"], stored != .null else { return contentExists }
    return JS.truthy(stored)
  }
}

/// `deploy-manifest-<key>.json`: path relative to the upload root → sha256 hex ('' after the tilde
/// re-anchoring, 'remove' in the relay's removal run). Written with a plain writeFile and read with
/// a bare JSON.parse; a broken one means "upload everything".
public struct DeployManifest: Equatable, Sendable {
  public var object: JSONObject
  public init(_ value: JSONValue) { object = value.objectValue ?? JSONObject() }
  public var json: JSONValue { .object(object) }
  public var paths: [String] { object.keys }
  public subscript(path: String) -> String? { object[path]?.stringValue }
}
