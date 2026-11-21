import Foundation

/// A selector's specificity (ids, classes/attributes/pseudo-classes, types/pseudo-elements), as
/// Selectors Level 4 counts it: `:is()`, `:not()` and `:has()` take their most specific argument,
/// `:where()` counts nothing. A list counts as its most specific part. Enough to tell which of two
/// rules setting a variable wins; not a validator.
public enum CssSpecificity {
  public typealias Value = (Int, Int, Int)

  public static func greater(_ a: Value, _ b: Value) -> Bool {
    a.0 != b.0 ? a.0 > b.0 : a.1 != b.1 ? a.1 > b.1 : a.2 > b.2
  }

  public static func of(_ selector: String) -> Value {
    let units = Array(selector.utf16)
    var i = 0
    return list(units, &i, until: nil)
  }

  static func add(_ a: Value, _ b: Value) -> Value { (a.0 + b.0, a.1 + b.1, a.2 + b.2) }
  static func max(_ a: Value, _ b: Value) -> Value { greater(b, a) ? b : a }

  static let legacyElements: Set<String> = ["before", "after", "first-line", "first-letter"]

  static func isName(_ u: UInt16) -> Bool {
    (u >= 0x30 && u <= 0x39) || (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) || u == 0x2D || u == 0x5F || u >= 0x80 || u == 0x5C
  }

  static func name(_ units: [UInt16], _ i: inout Int) -> String {
    let start = i
    while i < units.count, isName(units[i]) {
      if units[i] == 0x5C { i += 1 }  // an escape takes the next character with it
      i += 1
    }
    return String(utf16CodeUnits: Array(units[start..<Swift.min(i, units.count)]), count: Swift.min(i, units.count) - start)
  }

  /// A comma-separated list up to `until` (a closing parenthesis) or the end: its most specific part.
  static func list(_ units: [UInt16], _ i: inout Int, until: UInt16?) -> Value {
    var best: Value = (0, 0, 0)
    var current: Value = (0, 0, 0)
    var compoundStart = true
    while i < units.count {
      let u = units[i]
      if let until, u == until { i += 1; break }
      switch u {
      case 0x2C:  // ,
        best = max(best, current); current = (0, 0, 0); compoundStart = true; i += 1
      case 0x20, 0x09, 0x0A, 0x0D, 0x3E, 0x2B, 0x7E:  // whitespace and combinators
        compoundStart = true; i += 1
      case 0x23:  // #id
        i += 1; _ = name(units, &i); current = add(current, (1, 0, 0)); compoundStart = false
      case 0x2E:  // .class
        i += 1; _ = name(units, &i); current = add(current, (0, 1, 0)); compoundStart = false
      case 0x5B:  // [attr], strings inside skipped
        var depth = 0
        while i < units.count {
          let c = units[i]
          if c == 0x22 || c == 0x27 { i += 1; while i < units.count, units[i] != c { i += units[i] == 0x5C ? 2 : 1 }; i += 1; continue }
          if c == 0x5B { depth += 1 } else if c == 0x5D { depth -= 1; if depth == 0 { i += 1; break } }
          i += 1
        }
        current = add(current, (0, 1, 0)); compoundStart = false
      case 0x3A:  // :pseudo-class or ::pseudo-element
        i += 1
        let element = i < units.count && units[i] == 0x3A
        if element { i += 1 }
        let pseudo = name(units, &i).lowercased()
        var argument: Value?
        if i < units.count, units[i] == 0x28 {
          i += 1
          if ["is", "not", "has", "matches", "-webkit-any", "-moz-any"].contains(pseudo) {
            argument = list(units, &i, until: 0x29)
          } else if pseudo == "where" {
            _ = list(units, &i, until: 0x29); argument = (0, 0, 0)
          } else {
            // :nth-child(…), :lang(…) and the like: one pseudo-class, the argument skipped.
            var depth = 1
            while i < units.count, depth > 0 { if units[i] == 0x28 { depth += 1 } else if units[i] == 0x29 { depth -= 1 }; i += 1 }
          }
        }
        if let argument { current = add(current, argument) }
        else if element || legacyElements.contains(pseudo) { current = add(current, (0, 0, 1)) }
        else { current = add(current, (0, 1, 0)) }
        compoundStart = false
      case 0x2A:  // *
        i += 1; compoundStart = false
      default:
        if isName(u) {
          let typeName = name(units, &i)
          if compoundStart, !typeName.isEmpty { current = add(current, (0, 0, 1)) }
          compoundStart = false
        } else {
          i += 1
        }
      }
    }
    return max(best, current)
  }
}

/// Which rules of the project still set a plugin variable after the Variables tab changed it
/// (docs/plan-plugin-variablen.md, B2). The `plugin-vars` block stands at the end of
/// `_quartzcontrol.scss`: after the template's stylesheets (its imports come first), before the
/// rules of custom.scss (which load `_quartzcontrol.scss` with their first line). So a project rule
/// wins when it is more specific, or as specific and in custom.scss.
public enum PluginVariableCascade {
  static let darkPrefix = #":root[saved-theme="dark"] "#
  static let lightOnlyPrefix = #":root:not([saved-theme="dark"]) "#

  /// The selector of the page's rule in a mode, nil when the page sets nothing there.
  public static func ownRule(_ o: PluginVariableOverride, mode: String) -> String? {
    let hasDark = o.dark.map { !JS.trim($0).isEmpty } ?? false
    let hasLight = !JS.trim(o.light).isEmpty
    if mode == "dark" {
      if hasDark { return darkPrefix + o.selector }
      return hasLight && !o.lightOnly ? o.selector : nil
    }
    guard hasLight else { return nil }
    return o.lightOnly && !hasDark ? lightOnlyPrefix + o.selector : o.selector
  }

  /// The value the page's rule gives in a mode.
  static func ownValue(_ o: PluginVariableOverride, mode: String) -> String {
    let hasDark = o.dark.map { !JS.trim($0).isEmpty } ?? false
    return mode == "dark" && hasDark ? (o.dark ?? "") : o.light
  }

  /// Whether a rule applies in a mode: a dark one only in dark, a light-only one only in light, any
  /// other in both.
  static func applies(_ setter: PluginVariables.Setter, mode: String) -> Bool {
    if setter.mode == "dark" { return mode == "dark" }
    if JSText.test(setter.rule, #":not\(\[saved-theme=["']?dark"#) { return mode == "light" }
    return true
  }

  /// The project's rules that beat the page's value in `mode`. `inCustom` says whether a rule comes
  /// from custom.scss (outside the managed blocks), which loads after the block. A rule with the
  /// page's own value at the page's own specificity is taken for the page's rule (the build of a
  /// saved change) and left out.
  public static func stronger(_ o: PluginVariableOverride, setBy: [PluginVariables.Setter], mode: String,
                              inCustom: (PluginVariables.Setter) -> Bool) -> [PluginVariables.Setter] {
    guard let own = ownRule(o, mode: mode) else { return [] }
    let ownSpecificity = CssSpecificity.of(own)
    let ownValue = JS.trim(ownValue(o, mode: mode))
    return setBy.filter { setter in
      guard applies(setter, mode: mode) else { return false }
      let specificity = CssSpecificity.of(setter.rule)
      if specificity == ownSpecificity && JS.trim(setter.value) == ownValue { return false }
      if CssSpecificity.greater(specificity, ownSpecificity) { return true }
      return specificity == ownSpecificity && inCustom(setter)
    }
  }

  /// Whether a rule of the build is the page's own, from the saved block: the same selector (as the
  /// build spells it) and the same value in its mode. The build shows the block like any other rule.
  public static func isOwn(_ setter: PluginVariables.Setter, saved: PluginVariableOverride?) -> Bool {
    guard let saved, let own = ownRule(saved, mode: setter.mode) else { return false }
    return normalized(own) == normalized(setter.rule) && JS.trim(ownValue(saved, mode: setter.mode)) == JS.trim(setter.value)
  }

  /// A selector as minified CSS spells it, so a rule in custom.scss can be found again in the build:
  /// no space around combinators, attribute values without quotes, one space between compounds.
  public static func normalized(_ selector: String) -> String {
    var s = JSText.replaceAll(JS.trim(selector), "[\(JSText.space)]+", with: " ")
    s = JSText.replaceAll(s, #" ?([>+~,]) ?"#, template: "$1")
    s = JSText.replaceAll(s, #"=["']([A-Za-z0-9_-]+)["']\]"#, template: "=$1]")
    return s
  }

  /// The selectors of custom.scss's rules (the moved blocks and comments out) that declare each
  /// variable, normalized. Top-level rules only: a rule nested in SCSS is not found and counts as
  /// the template's.
  public static func customSelectors(project: String) -> [String: Set<String>] {
    guard let text = try? StyleSheets.readText(StyleSheets.customScss(project)) else { return [:] }
    // `imported-styles` stays: a template's body under `projectWins`, in custom.scss after the `@use`.
    var own = ManagedBlocks.movedMarkers.reduce(text) { ManagedBlocks.strip($0, $1) }
    own = JSText.replaceAll(own, #"/\*[\s\S]*?\*/"#, with: "")
    own = JSText.replaceAll(own, "(\\A|[\(JSText.space);{}])//[^\\n]*", template: "$1")
    // Sass statements: the rule walker would take the text before the first rule for its selector.
    own = JSText.replaceAll(own, #"@(use|forward|import)[^;{}]*;"#, with: "")
    var out: [String: Set<String>] = [:]
    VariableGraph.eachRule(own) { selector, body, context in
      guard !context.conditional else { return }
      for (name, _) in VariableGraph.declarations(body) { out[name, default: []].insert(normalized(selector)) }
    }
    return out
  }
}
