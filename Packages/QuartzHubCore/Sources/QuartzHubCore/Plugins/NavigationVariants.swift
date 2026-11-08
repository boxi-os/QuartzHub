import Foundation

/// What QuartzHub knows about quartz-navigations beyond its schema (QuartzControl's
/// `routes/Plugins/navigationVariants.ts`, measured against it in NavigationsTests): the ten
/// variants, where a new one goes, and which option does nothing with which variant, read from
/// the plugin's rendering code.
public enum NavigationVariants {
  /// The plugin's name as the config loader derives it from github:boxi-os/quartz-navigations.
  public static let plugin = "quartz-navigations"
  /// The version whose render.tsx the tables below are read from.
  public static let readAgainst = "0.4.2"
  /// Versions whose src/ is the same as that one's (`git diff v0.4.0 v0.4.3 -- src` is empty).
  public static let sameCode = ["0.4.0", "0.4.1", "0.4.3"]

  public enum Variant: String, CaseIterable, Sendable {
    case tree, accordion, flyout, bar, dropdown, mega, tabs, columns, select, pager

    /// Where a new navigation of this kind goes: where the plugin's README says it belongs.
    public var position: String {
      switch self {
      case .tree, .accordion, .flyout, .select: "left"
      case .bar, .dropdown, .mega, .tabs: "header"
      case .columns: "footer"
      case .pager: "afterBody"
      }
    }

    /// An SF Symbol in place of QuartzControl's lucide icon.
    public var symbol: String {
      switch self {
      case .tree: "list.bullet.indent"
      case .accordion: "list.bullet.rectangle"
      case .flyout: "sidebar.right"
      case .bar: "menubar.rectangle"
      case .dropdown: "chevron.down.square"
      case .mega: "rectangle.topthird.inset.filled"
      case .tabs: "rectangle.split.3x1"
      case .columns: "rectangle.split.3x1.fill"
      case .select: "chevron.up.chevron.down"
      case .pager: "arrow.left.arrow.right"
      }
    }
  }

  /// The names before 0.4 (LEGACY_VARIANTS in the plugin's options.ts): still read.
  private static let legacy: [String: Variant] = ["vertical": .tree, "horizontal": .bar]

  public static func variant(_ options: JSONObject?) -> Variant {
    guard case .string(let value)? = options?["variant"] else { return .tree }
    return legacy[value] ?? Variant(rawValue: value) ?? .tree
  }

  private static let collapsible: Set<Variant> = [.accordion, .flyout, .dropdown, .mega]
  private static let popup: Set<Variant> = [.dropdown, .mega, .flyout]
  private static let row: Set<Variant> = [.bar, .dropdown, .mega, .tabs]
  private static let ownRenderer: Set<Variant> = [.select, .pager]

  /// Whether an option does nothing with this variant and mobile setting. Everything not listed
  /// counts as having an effect.
  public static func hasNoEffect(_ key: String, _ variant: Variant, mobile: JSONValue?) -> Bool {
    let own = ownRenderer.contains(variant)
    let mobileFolds = !own && mobile == .string("accordion")
    switch key {
    case "mobile": return false
    case "chevrons": return !collapsible.contains(variant) && !mobileFolds
    case "folderClick": return !collapsible.contains(variant)
    case "exclusive": return !collapsible.contains(variant) && !mobileFolds
    case "folderDefaultState": return variant != .accordion
    case "expandActive", "persistState": return variant != .accordion && !(mobileFolds && !popup.contains(variant))
    case "select": return variant != .select && (own || mobile != .string("select"))
    case "align": return !row.contains(variant)
    case "trigger": return !popup.contains(variant)
    case "tabs", "flyout", "pager": return variant.rawValue != key
    case "columns": return true
    case "icons", "nodeIcons": return variant == .select
    case "showHome": return variant == .tabs || own
    case "showScopeRoot", "indexEntry": return own
    default: return false
    }
  }

  /// The options that belong to a variant rather than to every navigation: the section under the tiles.
  public static let variantKeys: Set<String> = [
    "align", "trigger", "chevrons", "folderClick", "folderDefaultState", "expandActive", "exclusive",
    "persistState", "tabs", "flyout", "select", "columns", "pager"
  ]

  /// The plugin's values of `mobile`, in the order of its schema.
  public static let mobileValues = ["same", "accordion", "offcanvas", "select", "hidden"]

  /// Why an option does nothing: the variants it works with (on the desktop) and the mobile
  /// settings with which it would work for this variant. nil: it works.
  public static func noEffectReason(_ key: String, _ variant: Variant, mobile: JSONValue?)
    -> (variants: [Variant], mobile: [String])? {
    guard hasNoEffect(key, variant, mobile: mobile) else { return nil }
    return (Variant.allCases.filter { !hasNoEffect(key, $0, mobile: .string("same")) },
            mobileValues.filter { $0 != "same" && !hasNoEffect(key, variant, mobile: .string($0)) })
  }

  /// The form's extras for a navigation (`navigationRoot` in optionFormExtras.ts): the variant's
  /// own options first under its name, what does nothing greyed with the variants it works with.
  /// `withVariant`: the variant leads the section (where no tiles stand above it).
  public static func root(options: JSONObject, fields: [OptionField], lang: OptionFormText.Language,
                          translate: @escaping OptionFormText.Translate = catalog, withVariant: Bool = false) -> OptionRoot {
    let variant = variant(options)
    let mobile = options["mobile"]
    let mobileField = fields.first { $0.key == "mobile" }
    let name = { (v: Variant) in translate(label(v), nil) }
    let quote = { (s: String) in lang == .en ? "“\(s)”" : "„\(s)“" }
    let byMobile = variantKeys.sorted().contains { hasNoEffect($0, variant, mobile: .string("same")) && !hasNoEffect($0, variant, mobile: mobile) }
    let inactive: (String) -> String? = { key in
      guard let why = noEffectReason(key, variant, mobile: mobile) else { return nil }
      var parts: [String] = []
      let without = Variant.allCases.filter { !why.variants.contains($0) }
      let names = { (list: [Variant]) in list.map { quote(name($0)) }.joined(separator: ", ") }
      if !why.variants.isEmpty {
        parts.append(without.count < why.variants.count
          ? translate(notWith, [("count", String(without.count)), ("variants", names(without))])
          : translate(onlyWith, [("count", String(why.variants.count)), ("variants", names(why.variants))]))
      }
      if !why.mobile.isEmpty {
        let labels = why.mobile.map { quote(OptionFormText.enumLabel(mobileField, .string($0), lang)) }.joined(separator: ", ")
        parts.append(translate(withMobile, [("variant", name(variant)), ("mobile", labels)]))
      }
      return parts.isEmpty ? translate(readNowhere, nil) : parts.joined(separator: " ")
    }
    // `String(options.mobile)`: "undefined" when it is not set.
    let mobileLabel = OptionFormText.enumLabel(mobileField, .string(mobile.map { JS.string($0) } ?? "undefined"), lang)
    return OptionRoot(
      inactiveReason: inactive,
      hideUnlessSet: { variantKeys.contains($0) },
      lead: OptionRoot.Lead(
        has: { variantKeys.contains($0) || (withVariant && $0 == "variant") },
        title: translate(leadTitle, [("variant", name(variant))]),
        empty: translate(leadEmpty, nil),
        note: byMobile ? translate(leadByMobile, [("mobile", quote(mobileLabel))]) : nil))
  }

  /// The catalog for these sentences and the variants' names, one literal key per case so
  /// `qh-check i18n` can read them.
  public static let catalog: OptionFormText.Translate = { key, args in
    let a = Dictionary(args ?? [], uniquingKeysWith: { _, last in last })
    let count = a["count"].flatMap { Int($0) }
    switch key {
    case "navigationsEditor.notWith": return L10n.t("navigationsEditor.notWith", a, count: count)
    case "navigationsEditor.onlyWith": return L10n.t("navigationsEditor.onlyWith", a, count: count)
    case "navigationsEditor.withMobile": return L10n.t("navigationsEditor.withMobile", a)
    case "navigationsEditor.readNowhere": return L10n.t("navigationsEditor.readNowhere")
    case "navigationsEditor.leadTitle": return L10n.t("navigationsEditor.leadTitle", a)
    case "navigationsEditor.leadEmpty": return L10n.t("navigationsEditor.leadEmpty")
    case "navigationsEditor.leadByMobile": return L10n.t("navigationsEditor.leadByMobile", a)
    case "navigationsEditor.variants.tree.label": return L10n.t("navigationsEditor.variants.tree.label")
    case "navigationsEditor.variants.accordion.label": return L10n.t("navigationsEditor.variants.accordion.label")
    case "navigationsEditor.variants.flyout.label": return L10n.t("navigationsEditor.variants.flyout.label")
    case "navigationsEditor.variants.bar.label": return L10n.t("navigationsEditor.variants.bar.label")
    case "navigationsEditor.variants.dropdown.label": return L10n.t("navigationsEditor.variants.dropdown.label")
    case "navigationsEditor.variants.mega.label": return L10n.t("navigationsEditor.variants.mega.label")
    case "navigationsEditor.variants.tabs.label": return L10n.t("navigationsEditor.variants.tabs.label")
    case "navigationsEditor.variants.columns.label": return L10n.t("navigationsEditor.variants.columns.label")
    case "navigationsEditor.variants.select.label": return L10n.t("navigationsEditor.variants.select.label")
    case "navigationsEditor.variants.pager.label": return L10n.t("navigationsEditor.variants.pager.label")
    case "navigationsEditor.variants.tree.text": return L10n.t("navigationsEditor.variants.tree.text")
    case "navigationsEditor.variants.accordion.text": return L10n.t("navigationsEditor.variants.accordion.text")
    case "navigationsEditor.variants.flyout.text": return L10n.t("navigationsEditor.variants.flyout.text")
    case "navigationsEditor.variants.bar.text": return L10n.t("navigationsEditor.variants.bar.text")
    case "navigationsEditor.variants.dropdown.text": return L10n.t("navigationsEditor.variants.dropdown.text")
    case "navigationsEditor.variants.mega.text": return L10n.t("navigationsEditor.variants.mega.text")
    case "navigationsEditor.variants.tabs.text": return L10n.t("navigationsEditor.variants.tabs.text")
    case "navigationsEditor.variants.columns.text": return L10n.t("navigationsEditor.variants.columns.text")
    case "navigationsEditor.variants.select.text": return L10n.t("navigationsEditor.variants.select.text")
    case "navigationsEditor.variants.pager.text": return L10n.t("navigationsEditor.variants.pager.text")
    default: return key
    }
  }

  // The keys the sentences come from.
  static let notWith = "navigationsEditor.notWith"
  static let onlyWith = "navigationsEditor.onlyWith"
  static let withMobile = "navigationsEditor.withMobile"
  static let readNowhere = "navigationsEditor.readNowhere"
  static let leadTitle = "navigationsEditor.leadTitle"
  static let leadEmpty = "navigationsEditor.leadEmpty"
  static let leadByMobile = "navigationsEditor.leadByMobile"

  public static func label(_ variant: Variant) -> String {
    switch variant {
    case .tree: "navigationsEditor.variants.tree.label"
    case .accordion: "navigationsEditor.variants.accordion.label"
    case .flyout: "navigationsEditor.variants.flyout.label"
    case .bar: "navigationsEditor.variants.bar.label"
    case .dropdown: "navigationsEditor.variants.dropdown.label"
    case .mega: "navigationsEditor.variants.mega.label"
    case .tabs: "navigationsEditor.variants.tabs.label"
    case .columns: "navigationsEditor.variants.columns.label"
    case .select: "navigationsEditor.variants.select.label"
    case .pager: "navigationsEditor.variants.pager.label"
    }
  }

  public static func text(_ variant: Variant) -> String {
    switch variant {
    case .tree: "navigationsEditor.variants.tree.text"
    case .accordion: "navigationsEditor.variants.accordion.text"
    case .flyout: "navigationsEditor.variants.flyout.text"
    case .bar: "navigationsEditor.variants.bar.text"
    case .dropdown: "navigationsEditor.variants.dropdown.text"
    case .mega: "navigationsEditor.variants.mega.text"
    case .tabs: "navigationsEditor.variants.tabs.text"
    case .columns: "navigationsEditor.variants.columns.text"
    case .select: "navigationsEditor.variants.select.text"
    case .pager: "navigationsEditor.variants.pager.text"
    }
  }
}
