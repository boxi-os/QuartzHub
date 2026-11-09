import Foundation

/// How an edit of one variable becomes an override, or none: the inner functions of QuartzControl's
/// `VariableRow.tsx` (`base`, `draft`, `setMode`, `followLight`), ported by hand because they live
/// inside a React component. Each rule there came out of a review, and its case is a test here.
public struct VariableEditing: Sendable {
  public let key: String
  public let override: VariableResolve.Override?
  /// The value without the user's override; the dark half falls back to the light one.
  public let base: VariableResolve.Override
  /// What the fields show.
  public let draft: VariableResolve.Override
  /// A variable of the user's own, with nothing underneath.
  public let isOwn: Bool
  public let baseDiffers: Bool
  /// The project's blocks are in `_quartzcontrol.scss`: only then is a light edit written for light
  /// mode only (an older QuartzControl drops the third rule in custom.scss).
  public let moved: Bool

  public init(key: String, context ctx: VariableResolve.Context, moved: Bool) {
    self.key = key
    self.moved = moved
    let override = ctx.overrides[key]
    self.override = override
    let baseLight = VariableResolve.baseValue(key, .light, ctx) ?? ""
    let baseDark = VariableResolve.baseValue(key, .dark, ctx) ?? VariableResolve.baseValue(key, .light, ctx) ?? ""
    base = VariableResolve.Override(light: baseLight, dark: baseDark)
    // An override's empty dark half means "no dark declaration", and the field shows what applies
    // in dark mode: the light value, or the theme's for a light-only override. An emptied light
    // field stays empty rather than jumping back to the base under the cursor.
    if let override {
      let dark = !override.dark.isEmpty ? override.dark : (override.lightOnly ? baseDark : override.light)
      draft = VariableResolve.Override(light: override.light, dark: dark.isEmpty ? baseDark : dark)
    } else {
      draft = VariableResolve.Override(light: baseLight, dark: baseDark)
    }
    isOwn = VariableResolve.originOf(key, ctx) == "own"
    baseDiffers = baseDark != baseLight
  }

  public enum Mode: Sendable { case light, dark }

  /// Compared as CSS text: the graph hands `#a1a1a1`, the file holds what was typed, `#A1A1A1`.
  static func sameCss(_ a: String, _ b: String) -> Bool {
    let strip = { (s: String) in JSText.replaceAll(s, "[\(JSText.space)]+", with: "").lowercased() }
    return strip(a) == strip(b)
  }

  /// The override after typing `value` into one field; nil is none at all. The dark half is kept
  /// only where it differs from the light one, a variable whose base differs between the modes keeps
  /// its dark value explicitly (or, in a moved project, leaves dark to the theme with `lightOnly`), and
  /// a dark half that only repeats the base counts as unset.
  public func setting(_ mode: Mode, _ value: String) -> VariableResolve.Override? {
    let lightValue = mode == .light ? value : (override.map(\.light).flatMap { $0.isEmpty ? nil : $0 } ?? base.light)
    let ownDark: String = {
      guard let dark = override?.dark, !dark.isEmpty, !Self.sameCss(dark, base.dark) else { return "" }
      return dark
    }()
    if mode == .light && baseDiffers && ownDark.isEmpty && moved {
      return lightValue == base.light ? nil : VariableResolve.Override(light: lightValue, dark: "", lightOnly: true)
    }
    let darkValue = mode == .dark ? value : (override.map(\.dark).flatMap { $0.isEmpty ? nil : $0 } ?? (baseDiffers ? base.dark : lightValue))
    let next = VariableResolve.Override(light: lightValue, dark: darkValue == lightValue ? "" : darkValue)
    let unchanged = !isOwn && next.light == base.light && (next.dark.isEmpty ? next.light : next.dark) == base.dark
    return unchanged ? nil : next
  }

  /// "Same in both modes": the dark half absent, not set to some value.
  public func followingLight() -> VariableResolve.Override? {
    let light = override.map(\.light).flatMap { $0.isEmpty ? nil : $0 } ?? base.light
    return light == base.light && !isOwn ? nil : VariableResolve.Override(light: light, dark: "")
  }

  /// Two fields from the start only where that is the usual case: a colour, a value that already
  /// differs between the modes, or one the user split.
  public func splitModes(context ctx: VariableResolve.Context, darkOpen: Bool) -> Bool {
    VariableResolve.isColorVariable(key, ctx, shown: false) || baseDiffers || !(override?.dark.isEmpty ?? true) || darkOpen
  }
}
