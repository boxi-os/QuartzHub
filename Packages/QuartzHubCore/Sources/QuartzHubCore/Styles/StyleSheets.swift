import Foundation

/// The two stylesheets QuartzHub writes into and the load order between them: a port of the file
/// half of `styleService.ts` (custom.scss, `_quartzcontrol.scss`, the `imports` block, the
/// variables, the move of 1.1 and the build door's repairs).
///
/// **Two forms, one rule each.** Until 1.0.x the four managed blocks stood in custom.scss; since
/// 1.1 they live in `quartz/styles/_quartzcontrol.scss`, which custom.scss loads with
/// `@use "./quartzcontrol";` before its first rule. The move is a step of its own
/// (`migrate`), never a side effect of a write: a moved project is one an older app reads with no
/// variables and no stylesheets. Until then every writer keeps the blocks in custom.scss. Reading
/// looks in both files, the managed one first; a copy still in custom.scss comes from an older app
/// on another machine and stands later in the CSS, so it is the one the site shows.
///
/// **One writer at a time** (`ProjectLock.styles`), and every write atomic: the dev server
/// rebuilds on each of these files. The public mutators take the lock; the `…Now` functions are
/// for a caller that holds it (a template import).
public enum StyleSheets {
  // MARK: where

  public static func stylesDirectory(_ project: String) -> String {
    "\(project)/quartz/styles"
  }

  /// The file Quartz's build imports (`componentResources.ts`), already in the dev server's watch.
  public static func customScss(_ project: String) -> String {
    "\(stylesDirectory(project))/custom.scss"
  }

  public static func managedScss(_ project: String) -> String {
    "\(stylesDirectory(project))/\(ManagedBlocks.managedFile)"
  }

  /// `join(stylesDir, ...relativePath.split('/'))`, which also resolves `.` and `..`.
  static func styleFile(_ project: String, _ relativePath: String) -> String {
    NodePath.normalize(stylesDirectory(project) + "/" + relativePath)
  }

  static func exists(_ url: String) -> Bool { FileManager.default.fileExists(atPath: url) }

  /// `readFile(path, 'utf-8')`: invalid bytes become U+FFFD.
  static func readText(_ url: String) throws -> String {
    String(decoding: try Posix.read(url), as: UTF8.self)
  }

  static func writeText(_ text: String, to url: String) throws {
    try JSONStore.writeAtomic(Data(text.utf8), to: url)
  }

  // MARK: read

  public struct Info: Equatable, Sendable {
    public var path: String
    public var content: String
    public var managed: (path: String, content: String)?
    public var moved: Bool

    public static func == (a: Info, b: Info) -> Bool {
      a.path == b.path && a.content == b.content && a.managed?.path == b.managed?.path && a.managed?.content == b.managed?.content && a.moved == b.moved
    }
  }

  public static func readCustom(project: String) throws -> Info {
    let path = customScss(project)
    let content = exists(path) ? try readText(path) : ""
    let managedPath = managedScss(project)
    let managed = exists(managedPath) ? (managedPath, try readText(managedPath)) : nil
    return Info(path: path, content: content, managed: managed, moved: managed != nil || ManagedBlocks.hasManagedUse(content))
  }

  /// Both files as text; the managed one empty when it does not exist.
  public struct Sources: Equatable, Sendable {
    public var custom: String
    public var managed: String
    public var managedExists: Bool
  }

  public static func readSources(project: String) throws -> Sources {
    let info = try readCustom(project: project)
    return Sources(custom: info.content, managed: info.managed?.content ?? "", managedExists: info.managed != nil)
  }

  /// The body of a block across both files, the managed one first, every copy; nil if neither has it.
  public static func managedBody(_ sources: Sources, _ id: String) -> String? {
    let bodies = [sources.managed, sources.custom].flatMap { ManagedBlocks.findBlocks($0, id).map { JS.trim($0.body) } }
    guard !bodies.isEmpty else { return nil }
    return bodies.filter { !$0.isEmpty }.joined(separator: "\n\n")
  }

  /// Both files' text without one block, for "everything except this block".
  public static func sourcesWithout(_ sources: Sources, _ id: String) -> String {
    ManagedBlocks.strip(sources.managed, id) + "\n" + ManagedBlocks.strip(sources.custom, id)
  }

  public static func isMoved(_ sources: Sources) -> Bool {
    sources.managedExists || ManagedBlocks.hasManagedUse(sources.custom)
  }

  // MARK: custom.scss as a whole

  /// The whole file, from the CSS tab. In a moved project the line that loads
  /// `_quartzcontrol.scss` is put back when the text lacks it: without it the site loses every
  /// managed block and the Sass check still passes. The answer says whether it was.
  public static func saveCustom(_ content: String, project: String) async throws -> Bool {
    try await ProjectLock.styles.run(project) {
      let restore = exists(managedScss(project)) && !ManagedBlocks.hasManagedUse(content)
      try writeText(restore ? ManagedBlocks.ensureManagedUse(content) : content, to: customScss(project))
      return restore
    }
  }

  /// custom.scss with a new free body, for the template import; the blocks other parts own stay
  /// (in the other file when moved, put back into the new body when not). The caller holds the lock.
  public static func replaceCustomBodyNow(_ body: String, project: String) throws {
    let sources = try readSources(project: project)
    if isMoved(sources) {
      try writeText(ManagedBlocks.ensureManagedUse(body), to: customScss(project))
      return
    }
    var kept: [String: String?] = [:]
    for marker in ManagedBlocks.movedMarkers { kept[marker] = .some(managedBody(sources, marker)) }
    try writeText(body, to: customScss(project))
    try writeManagedBlocksNow(kept, project: project)
  }

  // MARK: the build door

  public enum Repair: String, Sendable {
    case lineRestored
    case fileCreated
  }

  /// A moved project whose `@use` line is gone gets it back; one with the line but without the file
  /// gets an empty managed file. Either half alone empties or breaks the build. A project with
  /// neither has not been moved and is left alone.
  public static func repairManagedUse(project: String) async throws -> Repair? {
    try await ProjectLock.styles.run(project) {
      let info = try readCustom(project: project)
      guard exists(info.path) else { return nil }
      let line = ManagedBlocks.hasManagedUse(info.content)
      if info.managed != nil && !line {
        try writeText(ManagedBlocks.ensureManagedUse(info.content), to: customScss(project))
        return .lineRestored
      }
      if info.managed == nil && line {
        try writeText(ManagedBlocks.managedFileHeader, to: managedScss(project))
        return .fileCreated
      }
      return nil
    }
  }

  /// The font URLs of the `fonts` block made relative in both files, written where that changed
  /// something. Every write does this too, but a project nobody saves in kept `/static/fonts/…`,
  /// which finds nothing on a site under a sub-path (eight of nine projects QuartzControl measured).
  /// Not the marker rename: that costs an older build every block it can read, and pressing
  /// "build" is no reason to pay it.
  public static func migrateFontUrls(project: String) async throws -> Bool {
    try await ProjectLock.styles.run(project) {
      var changed = false
      for path in [customScss(project), managedScss(project)] {
        let content = exists(path) ? try readText(path) : ""
        if content.isEmpty { continue }
        var out = content
        for span in ManagedBlocks.findBlocks(content, "fonts").reversed() {
          out = JSText.slice(out, 0, span.from) + ManagedBlocks.relativeFontUrls(JSText.slice(out, span.from, span.to)) + JSText.slice(out, span.to)
        }
        if out == content { continue }
        try writeText(out, to: path)
        changed = true
      }
      return changed
    }
  }

  // MARK: the blocks

  /// Writes the managed blocks. `changes` names the blocks this write is about: a string is the
  /// new body, nil removes the block. The caller holds the lock.
  ///
  /// Not moved (and no `move`): each named block where it stands in custom.scss, or appended (the
  /// load order before the first rule), and nothing else touched. Moved, or `move`: every block is
  /// carried over as it reads now, from either file, into the managed file in a fixed order
  /// (imports before any rule, the variables last), then custom.scss without the blocks and with
  /// the `@use` line. A write that breaks off in between leaves a block in both files, read twice
  /// and joined by the next write, never in neither.
  public static func writeManagedBlocksNow(_ changes: [String: String?], move: Bool = false, project: String) throws {
    let sources = try readSources(project: project)
    if !move && !isMoved(sources) {
      var custom = sources.custom
      for marker in ManagedBlocks.movedMarkers {
        guard let change = changes[marker] else { continue }
        if marker == "imports" {
          custom = ManagedBlocks.upsertImportBlock(custom, change ?? "")
        } else if let body = change {
          custom = ManagedBlocks.upsert(custom, marker, body)
        } else {
          custom = ManagedBlocks.migrateOnWrite(ManagedBlocks.strip(custom, marker))
        }
      }
      if custom != sources.custom { try writeText(custom, to: customScss(project)) }
      return
    }
    let bodies: [(String, String?)] = ManagedBlocks.movedMarkers.map { marker in
      if let change = changes[marker] { return (marker, change) }
      return (marker, marker == "imports" ? carriedImports(project, sources) : managedBody(sources, marker))
    }
    var managed = sources.managedExists ? sources.managed : ManagedBlocks.managedFileHeader
    for marker in ManagedBlocks.movedMarkers { managed = ManagedBlocks.strip(managed, marker) }
    for (marker, body) in bodies {
      guard let body else { continue }
      if marker == "imports" {
        managed = ManagedBlocks.upsertImportBlock(managed, body)
      } else {
        let (start, end) = ManagedBlocks.markers(marker)
        managed = JSText.replaceAll(managed, "[\(JSText.space)]+\\z", with: "") + "\n\n\(start)\n\(body)\n\(end)\n"
      }
    }
    managed = ManagedBlocks.migrateOnWrite(managed)
    if !sources.managedExists || managed != sources.managed { try writeText(managed, to: managedScss(project)) }

    var custom = sources.custom
    for marker in ManagedBlocks.movedMarkers { custom = ManagedBlocks.strip(custom, marker) }
    custom = ManagedBlocks.ensureManagedUse(ManagedBlocks.migrateOnWrite(custom))
    if custom != sources.custom { try writeText(custom, to: customScss(project)) }
  }

  /// The load order a write carries over unchanged, unless it holds what breaks the build: two
  /// copies name the same stylesheets, and two `@use` of one module stop Sass ("There's already a
  /// module with namespace"). Then it is rebuilt from the order as it reads, deduplicated and
  /// without files that are gone. One copy without a duplicate stays byte for byte.
  static func carriedImports(_ project: String, _ sources: Sources) -> String? {
    guard let body = managedBody(sources, "imports") else { return nil }
    let copies = [sources.managed, sources.custom].reduce(0) { $0 + ManagedBlocks.findBlocks($1, "imports").count }
    let order = importOrder(project, sources)
    if copies == 1 && JSText.matches(body, "@use[\(JSText.space)]").count == order.count { return body }
    guard !order.isEmpty else { return nil }
    var taken: Set<String> = []
    return order.map { useLine(for: $0, taken: &taken) }.joined(separator: "\n")
  }

  public struct Migration: Equatable, Sendable {
    public var moved: Bool
    public var snapshotId: String?
  }

  /// Moves a project's blocks to `_quartzcontrol.scss`; a moved project is left as it is. With
  /// `snapshot` (the Styles page) one comes first, of the kind the thinning keeps: the way back
  /// for a machine that stays on 1.0.x. Without, for a project just created.
  public static func migrate(project: String, snapshot: StyleFiles.Snapshot?) async throws -> Migration {
    try await ProjectLock.styles.run(project) {
      if isMoved(try readSources(project: project)) { return Migration(moved: false, snapshotId: nil) }
      let id = try await snapshot?(project, "styleMigration") ?? nil
      try writeManagedBlocksNow([:], move: true, project: project)
      return Migration(moved: true, snapshotId: id)
    }
  }

  // MARK: the load order

  static let styleDirectories = ["custom", "imported"]

  /// `custom/typography.scss` → `./custom/typography`: Sass tries .sass/.scss/.css for a URL
  /// without extension, and the line stays what the import always wrote.
  static func useSpecifier(_ relativePath: String) -> String {
    "./" + JSText.replaceAll(relativePath, #"\.(scss|css)\z"#, with: "")
  }

  /// The file a `@use` names, resolved against the disk (an extensionless specifier could be
  /// either extension, a partial may be `_name.scss`); nil outside custom/ and imported/.
  static func relativePath(forSpecifier specifier: String, project: String) -> String? {
    let bare = JSText.replaceAll(JSText.replaceAll(specifier, #"\A\./"#, with: ""), #"\.(scss|css)\z"#, with: "")
    let parts = JSText.split(bare, "/")
    let dir = parts[0], name = parts.dropFirst().joined(separator: "/")
    guard styleDirectories.contains(dir), !name.isEmpty, !JSText.includes(name, "/") else { return nil }
    for candidate in ["\(name).scss", "_\(name).scss", "\(name).css"] where exists("\(stylesDirectory(project))/\(dir)/\(candidate)") {
      return "\(dir)/\(candidate)"
    }
    return nil
  }

  /// The stylesheets the block loads, in order. A line whose file is gone is dropped: the block is
  /// written only by the app, so an unresolvable `@use` means a file deleted outside it, and
  /// keeping it would break the next build.
  static func importOrder(_ project: String, _ sources: Sources) -> [String] {
    guard let body = managedBody(sources, "imports"), !body.isEmpty else { return [] }
    var out: [String] = []
    for match in JSText.matches(body, "@use[\(JSText.space)]+[\"']([^\"']+)[\"']") {
      if let path = relativePath(forSpecifier: match.groups[1]!, project: project), !out.contains(path) { out.append(path) }
    }
    return out
  }

  public static func currentOrder(project: String) throws -> [String] {
    importOrder(project, try readSources(project: project))
  }

  /// The namespace Sass derives for a `@use` without `as`: the last component, without extension
  /// and leading underscore, up to the first dot.
  static func defaultNamespace(_ relativePath: String) -> String {
    let base = JSText.split(relativePath, "/").last ?? relativePath
    let bare = JSText.replaceAll(JSText.replaceAll(base, #"\.(scss|css)\z"#, with: ""), #"\A_"#, with: "")
    return JSText.split(bare, ".")[0]
  }

  /// A namespace is a Sass identifier, so not one starting with a digit; an explicit `as` fixes
  /// both failures QuartzControl measured (`01-typografie`, and `typo.grafie` beside `typo`), and
  /// is written only where needed.
  static func useLine(for relativePath: String, taken: inout Set<String>) -> String {
    let specifier = useSpecifier(relativePath)
    let wanted = defaultNamespace(relativePath)
    let valid = JSText.test(wanted, #"\A[A-Za-z_][A-Za-z0-9_-]*\z"#)
    if valid && !taken.contains(wanted) {
      taken.insert(wanted)
      return "@use \"\(specifier)\";"
    }
    let base = valid ? wanted : "ns-\(wanted)"
    var namespace = base
    var n = 2
    while taken.contains(namespace) {
      namespace = "\(base)-\(n)"
      n += 1
    }
    taken.insert(namespace)
    return "@use \"\(specifier)\" as \(namespace);"
  }

  public static func setImportOrder(_ relativePaths: [String], project: String) async throws {
    try await ProjectLock.styles.run(project) { try setImportOrderNow(relativePaths, project: project) }
  }

  public static func setImportOrderNow(_ relativePaths: [String], project: String) throws {
    var taken: Set<String> = []
    let body = relativePaths.map { useLine(for: $0, taken: &taken) }.joined(separator: "\n")
    let change: String? = body.isEmpty ? nil : body
    let changes: [String: String?] = ["imports": change]
    try writeManagedBlocksNow(changes, project: project)
  }

  /// The project stylesheets whose rules reach the site, the one whose rules come last first:
  /// custom.scss, `_quartzcontrol.scss`, then the load order from its end. A file in custom/ that
  /// the block does not load is not listed.
  public static func loadedStylesheetsLastFirst(project: String) throws -> [String] {
    let order = try currentOrder(project: project)
    return ([customScss(project), managedScss(project)] + order.reversed().map { styleFile(project, $0) }).filter(exists)
  }

  // MARK: the variables

  public static func variableOverrides(project: String) throws -> [VariableOverride] {
    managedBody(try readSources(project: project), "css-vars").map(VariableOverrides.parse) ?? []
  }

  public static func variableCollisions(project: String) throws -> [String] {
    VariableOverrides.collisions(try readSources(project: project))
  }

  /// An empty list (or one of emptied values) clears the block rather than leaving stale rules.
  public static func saveVariableOverrides(_ overrides: [VariableOverride], project: String) async throws {
    try await ProjectLock.styles.run(project) {
      let body = VariableOverrides.render(overrides)
      let change: String? = body.isEmpty ? nil : body
      let changes: [String: String?] = ["css-vars": change]
      try writeManagedBlocksNow(changes, project: project)
    }
  }
}
