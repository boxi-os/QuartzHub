import Foundation

/// The SCSS check and Quartz's own frame measures, compiled with the project's own Sass: a port of
/// `checkStyles`, `checkStyleSource` and `readQuartzFrameMeasures` in `styleService.ts`. The
/// compiling happens in the `sass-check` helper; what it means happens here.
///
/// A project without a Sass that loads is "unavailable", never "no errors": one that never had
/// `npm install` cannot be checked, and saying it passed would be a lie. While npm unpacks, the
/// load is not even tried (`ProjectDependencies.halfUnpackedModule`).
public enum ScssCheck {
  public struct Diagnostic: Equatable, Sendable {
    public var message: String
    /// Relative to quartz/styles, when the error is in one of the project's own files.
    public var relativePath: String?
    public var line: Int?
    public var column: Int?
    /// An older build (beta.2) wrote its imports block inside QuartzHub's: two `@use` of one
    /// namespace, and rewriting the load order once is the way out.
    public var nestedImportBlock = false
    /// custom.scss loads `_quartzcontrol.scss`, and the file is not there.
    public var managedFileMissing = false
  }

  public enum Result: Equatable, Sendable {
    case ok
    case error(Diagnostic)
    case unavailable(String)
  }

  struct Call {
    var json: JSONValue
    static func compile(_ path: String, loadPaths: [String]) -> Call {
      Call(json: .object(JSONObject([("kind", .string("compile")), ("path", .string(path)), ("loadPaths", .array(loadPaths.map { .string($0) }))])))
    }
    static func compileString(_ source: String, url: String, syntax: String?, loadPaths: [String]) -> Call {
      var pairs: [(String, JSONValue)] = [("kind", .string("compileString")), ("source", .string(source)), ("url", .string(url))]
      if let syntax { pairs.append(("syntax", .string(syntax))) }
      pairs.append(("loadPaths", .array(loadPaths.map { .string($0) })))
      return Call(json: .object(JSONObject(pairs)))
    }
  }

  enum Compiled {
    case css(String)
    case failed(JSONValue)
  }

  /// The helper's answer per call, or why there is no Sass to ask.
  static func compile(_ project: URL, _ calls: [Call], runtime: RuntimeLocation) async -> Swift.Result<[Compiled], Unanswered> {
    if let unpacking = ProjectDependencies.halfUnpackedModule(project: project, "sass") {
      return .failure(Unanswered(reason: L10n.t("main.styleSassUnpacking", ["name": unpacking])))
    }
    let request = JSONObject([("project", .string(project.path)), ("calls", .array(calls.map(\.json)))])
    do {
      let answer = try await Helper.call("sass-check", request, runtime: runtime, timeout: .seconds(120))
      guard answer["loaded"] == .bool(true) else { return .failure(Unanswered(reason: L10n.t("main.styleSassMissing"))) }
      return .success((answer["results"]?.arrayValue ?? []).map { result in
        if let css = result["css"]?.stringValue { return .css(css) }
        return .failed(result["error"] ?? .null)
      })
    } catch {
      return .failure(Unanswered(reason: L10n.t("styles.sassCheckBroken", ["reason": String(describing: error)])))
    }
  }

  struct Unanswered: Error { let reason: String }

  /// Sass's error mapped back: the file as a path relative to quartz/styles when it is one of the
  /// project's own, 1-based line and column.
  static func diagnostic(_ project: URL, _ error: JSONValue) -> Diagnostic {
    let message = error["sassMessage"]?.stringValue ?? error["message"]?.stringValue ?? "?"
    var relativePath: String?
    if let url = error["url"]?.stringValue {
      let file = JSText.startsWith(url, "file:") ? (URL(string: url)?.path ?? url) : url
      let relative = NodePath.relative(NodePath.normalize(StyleSheets.stylesDirectory(project).path), file)
      if !relative.isEmpty && !JSText.startsWith(relative, "..") { relativePath = relative }
    }
    return Diagnostic(message: message, relativePath: relativePath,
                      line: error["line"]?.numberValue.map { Int($0) + 1 }, column: error["column"]?.numberValue.map { Int($0) + 1 })
  }

  /// Whether one copy of a block stands inside another (the shape `findBlocks` reads through).
  static func hasNestedCopy(_ content: String, _ id: String) -> Bool {
    let spans = ManagedBlocks.names.flatMap { ManagedBlocks.copies(content, id, $0) }
    return spans.enumerated().contains { index, span in
      spans.enumerated().contains { other, candidate in other != index && candidate.from < span.from && span.to <= candidate.to }
    }
  }

  /// custom.scss with everything it loads, as the build compiles it.
  public static func check(project: URL, runtime: RuntimeLocation = .current) async -> Result {
    let entry = StyleSheets.customScss(project)
    guard FileManager.default.fileExists(atPath: entry.path) else { return .unavailable(L10n.t("main.styleCustomScssMissing")) }
    let styles = NodePath.normalize(StyleSheets.stylesDirectory(project).path)
    switch await compile(project, [.compile(entry.path, loadPaths: [styles])], runtime: runtime) {
    case .failure(let unanswered): return .unavailable(unanswered.reason)
    case .success(let results):
      guard case .failed(let error)? = results.first else { return .ok }
      var found = diagnostic(project, error)
      let content = (try? StyleSheets.readText(entry)) ?? ""
      found.nestedImportBlock = hasNestedCopy(content, "imports")
      found.managedFileMissing = ManagedBlocks.hasManagedUse(content) && !FileManager.default.fileExists(atPath: StyleSheets.managedScss(project).path)
      return .error(found)
    }
  }

  /// One file's *unsaved* content, standing alone: with Sass modules a partial sees nothing of what
  /// included it, so this is no approximation. The url gives a relative `@use` its directory.
  public static func checkSource(_ relativePath: String, _ content: String, project: URL, runtime: RuntimeLocation = .current) async throws -> Result {
    if relativePath != "custom.scss" { try StyleFiles.checkEditable(relativePath) }
    let file = relativePath == "custom.scss" ? StyleSheets.customScss(project).path : StyleSheets.styleFile(project, relativePath).path
    let styles = NodePath.normalize(StyleSheets.stylesDirectory(project).path)
    let call = Call.compileString(content, url: file, syntax: JSText.endsWith(file, ".css") ? "css" : "scss", loadPaths: [styles])
    switch await compile(project, [call], runtime: runtime) {
    case .failure(let unanswered): return .unavailable(unanswered.reason)
    case .success(let results):
      guard case .failed(let error)? = results.first else { return .ok }
      return .error(diagnostic(project, error))
    }
  }

  // MARK: Quartz's frame, as the project measures it

  public struct Grid: Equatable, Sendable {
    public var columns: [String]
    public var rowGap: String
    public var columnGap: String
  }

  public struct Measures: Equatable, Sendable {
    public var grids: [String: Grid]
    public var breakpoints: (mobile: Double, desktop: Double)
    /// `.page`'s max-width; nil when base.scss does not cap it in the form Quartz writes.
    public var pageMaxWidth: String?

    public static func == (a: Measures, b: Measures) -> Bool {
      a.grids == b.grids && a.breakpoints == b.breakpoints && a.pageMaxWidth == b.pageMaxWidth
    }
  }

  public enum MeasuresResult: Equatable, Sendable {
    case ok(Measures)
    case unavailable(String)
  }

  static let grids = [("desktop", "desktopGrid"), ("tablet", "tabletGrid"), ("mobile", "mobileGrid")]

  /// The column sizes and gaps of `$desktopGrid`/`$tabletGrid`/`$mobileGrid`, the two
  /// `$breakpoints` and `.page`'s cap, evaluated by Sass: the values are Sass (`#{$sidePanelWidth}`
  /// in a map, a `calc()` over a map lookup), and a regex would be a second Sass, wrong at the first
  /// expression.
  public static func frameMeasures(project: URL, runtime: RuntimeLocation = .current) async -> MeasuresResult {
    let dir = NodePath.normalize(StyleSheets.stylesDirectory(project).path)
    guard FileManager.default.fileExists(atPath: NodePath.join(dir, "variables.scss")) else {
      return .unavailable(L10n.t("main.quartzMeasuresNoVariables"))
    }
    // `.page`'s own max-width, the declaration before its first nested rule; an interpolation is
    // part of the declaration. Wrapped in `#{…}`, because Sass passes a custom property's value
    // through as text.
    var pageExpression: String?
    if let base = try? StyleSheets.readText(URL(fileURLWithPath: NodePath.join(dir, "base.scss"))),
       let block = JSText.firstMatch(base, #"(?:\A|\n)\.page["# + JSText.space + #"]*\{((?:#\{[^{}]*\}|[^{}])*)"#)?.groups[1],
       let value = JSText.firstMatch(block, #"(?:\A|[;"# + JSText.space + #"])max-width["# + JSText.space + #"]*:["# + JSText.space + #"]*([^;]+);"#)?.groups[1] {
      pageExpression = JS.trim(value)
    }
    var lines: [String] = []
    for (breakpoint, grid) in grids {
      lines += ["--qc-\(breakpoint)-columns: #{map.get($\(grid), templateColumns)};", "--qc-\(breakpoint)-rowgap: #{map.get($\(grid), rowGap)};",
                "--qc-\(breakpoint)-columngap: #{map.get($\(grid), columnGap)};"]
    }
    lines += ["--qc-bp-mobile: #{map.get($breakpoints, mobile)};", "--qc-bp-desktop: #{map.get($breakpoints, desktop)};"]
    func source(_ extra: [String]) -> Call {
      .compileString("@use \"sass:map\";\n@use \"variables\" as *;\n:root {\n\((lines + extra).joined(separator: "\n"))\n}\n",
                     url: NodePath.join(dir, "_quartzcontrol-measures.scss"), syntax: nil, loadPaths: [dir])
    }
    // With the cap first; a cap this cannot evaluate on its own is no reason to lose the grids.
    let calls = (pageExpression.map { [source(["--qc-page: #{\($0)};"])] } ?? []) + [source([])]
    let results: [Compiled]
    switch await compile(project, calls, runtime: runtime) {
    case .failure(let unanswered): return .unavailable(unanswered.reason)
    case .success(let answered): results = answered
    }
    var values: [String: String]
    var pageMaxWidth: String?
    if pageExpression != nil, case .css(let css)? = results.first {
      values = customProperties(css)
      pageMaxWidth = values["page"].map(sumPx)
    } else if case .css(let css)? = results.last {
      values = customProperties(css)
    } else if case .failed(let error)? = results.last {
      return .unavailable(L10n.t("main.quartzMeasuresFailed", ["message": diagnostic(project, error).message]))
    } else {
      return .unavailable(L10n.t("styles.sassCheckBroken", ["reason": "no answer"]))
    }

    func px(_ value: String?) -> Double {
      guard let value, JSText.test(value, #"\A[0-9]+(\.[0-9]+)?px\z"#) else { return .nan }
      return Double(JSText.slice(value, 0, JSText.length(value) - 2)) ?? .nan
    }
    var found: [String: Grid] = [:]
    for (breakpoint, grid) in grids {
      let columns = splitTrackList(values["\(breakpoint)-columns"] ?? "")
      guard !columns.isEmpty, let rowGap = values["\(breakpoint)-rowgap"], !rowGap.isEmpty,
            let columnGap = values["\(breakpoint)-columngap"], !columnGap.isEmpty else {
        return .unavailable(L10n.t("main.quartzMeasuresIncomplete", ["name": "$\(grid)"]))
      }
      found[breakpoint] = Grid(columns: columns, rowGap: rowGap, columnGap: columnGap)
    }
    let mobile = px(values["bp-mobile"]), desktop = px(values["bp-desktop"])
    if mobile.isNaN || desktop.isNaN { return .unavailable(L10n.t("main.quartzMeasuresIncomplete", ["name": "$breakpoints"])) }
    return .ok(Measures(grids: found, breakpoints: (mobile, desktop), pageMaxWidth: pageMaxWidth))
  }

  static func customProperties(_ css: String) -> [String: String] {
    var values: [String: String] = [:]
    for match in JSText.matches(css, "--qc-([a-z-]+):[\(JSText.space)]*([^;]*);") { values[match.groups[1]!] = JS.trim(match.groups[2]!) }
    return values
  }

  /// base.scss interpolates inside `calc()`, which Sass leaves as text: a sum of px is added up,
  /// anything else is shown as Sass wrote it.
  static func sumPx(_ value: String) -> String {
    guard let inner = JSText.firstMatch(value, #"\Acalc\(([^\n\r\x{2028}\x{2029}]*)\)\z"#)?.groups[1],
          JSText.test(inner, #"\A["# + JSText.space + #"]*[0-9]+(\.[0-9]+)?px(["# + JSText.space + #"]*[+-]["# + JSText.space + #"]*[0-9]+(\.[0-9]+)?px)*["# + JSText.space + #"]*\z"#) else { return value }
    let compact = JSText.replaceAll(inner, "[\(JSText.space)]+", with: "")
    let sum = JSText.matches(compact, #"[+-]?[0-9]+(\.[0-9]+)?px"#).reduce(0.0) { $0 + (Double(JSText.slice($1.groups[0]!, 0, JSText.length($1.groups[0]!) - 2)) ?? 0) }
    return "\(JSJSON.numberToString(sum))px"
  }

  /// "320px minmax(0, 1fr) 320px" as three tracks: split on spaces outside parentheses.
  static func splitTrackList(_ value: String) -> [String] {
    var out: [String] = []
    var depth = 0
    var current = ""
    for scalar in JSText.replaceAll(value, #"\A["']|["']\z"#, with: "").unicodeScalars {
      if scalar == "(" { depth += 1 }
      if scalar == ")" { depth -= 1 }
      if JS.isTrimmed(scalar) && depth == 0 {
        if !current.isEmpty { out.append(current) }
        current = ""
      } else {
        current.unicodeScalars.append(scalar)
      }
    }
    if !current.isEmpty { out.append(current) }
    return out
  }
}

extension NodePath {
  /// `path.relative(from, to)` for absolute, normalised paths.
  static func relative(_ from: String, _ to: String) -> String {
    let a = JSText.split(normalize(from), "/").filter { !$0.isEmpty }
    let b = JSText.split(normalize(to), "/").filter { !$0.isEmpty }
    var common = 0
    while common < a.count && common < b.count && a[common] == b[common] { common += 1 }
    return (Array(repeating: "..", count: a.count - common) + b[common...]).joined(separator: "/")
  }
}
