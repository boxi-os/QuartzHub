import Foundation

/// Where a core 3 theme comes from, as the Community-Themes page offers it: a name of Obsidian's
/// list (or Obsidian's built-in theme), a GitHub repo, an address of a `theme.css`, or a file in the
/// project (docs/plan-themes-core-3.md, step 6). Read and written the way core 3.1.1's
/// `resolveTheme` takes `theme:`, in its order: built-in, path, address, `owner/repo`, name.
public enum ThemeSource {
  public enum Kind: String, CaseIterable, Sendable {
    case catalog, repo, address, file
  }

  /// core's test for a path: `./`, `../`, `/`, `~`, a drive letter, or anything ending in `.css`.
  static let pathPattern = #"\A(\.{1,2}[\\/]|/|~|[A-Za-z]:[\\/])"#
  static let repoPattern = #"\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z"#
  /// What QuartzHub puts behind an address that ends in `.css`: core 3.1.0 and 3.1.1 read such an
  /// address as a path and stop at „theme file not found“; with a query it is an address
  /// (decisions/phase-5-gleichstand.md, „themes-core 3: Messung vor dem Bau“).
  static let addressQuery = "?quartzhub"

  /// Obsidian's built-in theme (`default`, `obsidian`, `Obsidian default`), core's `BUILT_IN`.
  public static func isBuiltIn(_ spec: String) -> Bool {
    ThemeCatalog.builtIn.contains(JS.trim(spec).lowercased())
  }

  /// The kind core sees in a `theme:` value. The built-in theme is the catalog's.
  public static func kind(of spec: String) -> Kind {
    let trimmed = JS.trim(spec)
    if isBuiltIn(trimmed) { return .catalog }
    if JSText.test(trimmed, pathPattern) || trimmed.hasSuffix(".css") { return .file }
    if JSText.test(trimmed, #"\Ahttps?://"#) { return .address }
    if JSText.test(trimmed, repoPattern) { return .repo }
    return .catalog
  }

  public enum Problem: Error, Equatable, Sendable {
    case empty
    /// Not `owner/repo`.
    case notRepo
    /// Not an http(s) address.
    case notAddress
  }

  /// What `theme:` gets for a text typed as `kind`. A name stays a name; a repo is `owner/repo`; an
  /// address on `.css` gets `addressQuery`; a file path relative to the project starts with `./`,
  /// so core reads it as a path whatever its ending.
  public static func value(_ text: String, kind: Kind) -> Result<String, Problem> {
    let trimmed = JS.trim(text)
    guard !trimmed.isEmpty else { return .failure(.empty) }
    switch kind {
    case .catalog:
      return .success(trimmed)
    case .repo:
      let bare = JSText.replaceAll(JSText.replaceAll(trimmed, #"\Ahttps?://github\.com/"#, with: ""), #"(\.git)?/?\z"#, with: "")
      return JSText.test(bare, repoPattern) ? .success(bare) : .failure(.notRepo)
    case .address:
      guard JSText.test(trimmed, #"\Ahttps?://[^\s/]+"#), !trimmed.contains(where: \.isWhitespace) else { return .failure(.notAddress) }
      return .success(trimmed.hasSuffix(".css") ? trimmed + addressQuery : trimmed)
    case .file:
      return .success(JSText.test(trimmed, pathPattern) ? trimmed : "./" + trimmed)
    }
  }

  /// The value as the page's field shows it: an address without the query QuartzHub added.
  public static func display(_ spec: String) -> String {
    let trimmed = JS.trim(spec)
    if kind(of: trimmed) == .address, trimmed.hasSuffix(".css" + addressQuery) { return String(trimmed.dropLast(addressQuery.count)) }
    return trimmed
  }

  /// A picked file as the entry writes it: `./` and the path inside the project, or the absolute
  /// path when it lies outside (it then builds on this Mac only).
  public static func projectPath(_ file: String, project: String) -> String {
    let base = project.hasSuffix("/") ? project : project + "/"
    // By bytes, as every path here (CLAUDE.md, NFD): `hasPrefix` would take „Ü“ and „U◌̈“ as one.
    guard file.utf8.starts(with: base.utf8) else { return file }
    return "./" + String(decoding: file.utf8.dropFirst(base.utf8.count), as: UTF8.self)
  }

  /// Whether `version` means anything for the value: core asks for a release only of a theme from
  /// the list or a repo.
  public static func takesVersion(_ spec: String) -> Bool {
    let trimmed = JS.trim(spec)
    return kind(of: trimmed) == .repo || (kind(of: trimmed) == .catalog && !isBuiltIn(trimmed))
  }
}
