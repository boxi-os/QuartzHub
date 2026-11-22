import Foundation

/// What Quartz asks Google Fonts for, reproduced from its `formatFontSpecification` and
/// `googleFontHref` (`quartz/util/theme.ts`): a port of `shared/googleFontRequest.ts`. The defaults
/// are per role: body is the only one with italic, header the only one with 700.
public enum GoogleFontRequest {
  public struct Request: Equatable, Sendable {
    public var slot: String
    public var family: String
    public var weights: [Double]
    public var italic: Bool
    /// Quartz's `<Head>` writes `wght@` only for more than one weight, so a single one is dropped
    /// and Google serves the family's default. QuartzHub's own fetch keeps it (`familyParameter`).
    public var singleWeightDropped: Bool

    public var json: JSONValue {
      .object(JSONObject([("slot", .string(slot)), ("family", .string(family)), ("weights", .array(weights.map { .number($0) })),
                          ("italic", .bool(italic)), ("singleWeightDropped", .bool(singleWeightDropped))]))
    }
  }

  public static let roles = ["header", "body", "code", "title"]
  /// Quartz 5.2's own font fields (`configuration.fonts`): 5.2.0 sets their variables but asks
  /// Google for none of them, 5.2.1 asks for them like the others (`QuartzFeatures.fontsLoadsAll`).
  /// QuartzHub asks for them when it holds the fonts, with the defaults Quartz checks them against
  /// (`validate`: a heading level as the header); the interface font as the body, without italic.
  public static let builtinRoles = ["interface", "h1", "h2", "h3", "h4", "h5", "h6"]
  /// What QuartzHub fetches into a project: Quartz's roles, then the built-in's.
  public static let fetchedRoles = roles + builtinRoles
  static let defaults: [String: (weights: [Double], italic: Bool)] = [
    "title": ([400, 600], false), "header": ([400, 700], false), "body": ([400, 600], true), "code": ([400, 600], false),
    "interface": ([400, 600], false),
    "h1": ([400, 700], false), "h2": ([400, 700], false), "h3": ([400, 700], false),
    "h4": ([400, 700], false), "h5": ([400, 700], false), "h6": ([400, 700], false)
  ]

  /// A typography entry is a bare family name or `{ name, weights?, includeItalic? }`.
  public static func request(_ role: String, _ spec: JSONValue?) -> Request? {
    guard let defaults = defaults[role] else { return nil }
    switch spec {
    case .string(let family)?:
      return family.isEmpty ? nil : Request(slot: role, family: family, weights: defaults.weights, italic: defaults.italic, singleWeightDropped: false)
    case .object(let object)?:
      guard case .string(let name)? = object["name"], !name.isEmpty else { return nil }
      var weights = defaults.weights
      if case .array(let items)? = object["weights"] { weights = items.compactMap(\.numberValue) }
      var italic = defaults.italic
      if case .bool(let given)? = object["includeItalic"] { italic = given }
      return Request(slot: role, family: name, weights: weights, italic: italic, singleWeightDropped: weights.count <= 1)
    default:
      return nil
    }
  }

  /// One `family=` value in the spelling of Quartz 5.2.1's built-in (`formatMerged` in
  /// `quartz/plugins/builtins/fonts.ts`): the weights sorted as numbers, a single weight named
  /// unless it is 400, italic as `ital@0;1` or with a pair per weight. QuartzControl and Quartz's
  /// `<Head>` (`quartz/util/theme.ts`) drop a single weight, so `weights: [700]` fetched 400, and
  /// write a single-weight italic as `Name:ital`, which Google answers with HTTP 400 (measured
  /// 2026-11-22, decisions/phase-5-gleichstand.md, „Quartz 5.2.1“). With no usable weight the
  /// family's default.
  static func familyParameter(_ request: Request) -> String {
    let weights = Array(Set(request.weights)).sorted()
    let name = JSURI.encodeComponent(JS.trim(request.family)).replacingOccurrences(of: "%20", with: "+")
    let defaultWeight = weights.isEmpty || weights == [400]
    if request.italic {
      if defaultWeight { return "\(name):ital@0;1" }
      let tuples = weights.map { "0,\(JSJSON.numberToString($0))" } + weights.map { "1,\(JSJSON.numberToString($0))" }
      return "\(name):ital,wght@\(tuples.joined(separator: ";"))"
    }
    return defaultWeight ? name : "\(name):wght@\(weights.map(JSJSON.numberToString).joined(separator: ";"))"
  }

  /// The CSS2 request for every role that names a family, header, body and code in Quartz's order,
  /// then the title whole (Quartz asks only for its characters; a project holding its fonts would
  /// have to fetch again whenever the title changes), then the built-in's fields when the
  /// typography carries them (`FontDelivery.fetchedTypography`). nil when no role names one.
  public static func css2Url(_ typography: JSONObject) -> String? {
    let families = fetchedRoles.compactMap { request($0, typography[$0]) }.map(familyParameter)
    guard !families.isEmpty else { return nil }
    return "https://fonts.googleapis.com/css2?" + families.map { "family=\($0)" }.joined(separator: "&") + "&display=swap"
  }
}
