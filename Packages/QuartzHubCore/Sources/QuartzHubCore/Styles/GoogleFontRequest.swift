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
    /// Quartz writes `wght@` only for more than one weight, so a single one is dropped and Google
    /// serves the family's default.
    public var singleWeightDropped: Bool

    public var json: JSONValue {
      .object(JSONObject([("slot", .string(slot)), ("family", .string(family)), ("weights", .array(weights.map { .number($0) })),
                          ("italic", .bool(italic)), ("singleWeightDropped", .bool(singleWeightDropped))]))
    }
  }

  public static let roles = ["header", "body", "code", "title"]
  static let defaults: [String: (weights: [Double], italic: Bool)] = [
    "title": ([400, 600], false), "header": ([400, 700], false), "body": ([400, 600], true), "code": ([400, 600], false)
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

  /// One `family=` value in Quartz's spelling: `ital` before `wght`, the italic pairs sorted as
  /// strings (Quartz calls a bare `.sort()`), no `wght@` for a single weight.
  static func familyParameter(_ request: Request) -> String {
    var features: [String] = []
    if request.italic { features.append("ital") }
    if request.weights.count > 1 {
      let spec: String
      if request.italic {
        var pairs = request.weights.flatMap { ["0,\(JSJSON.numberToString($0))", "1,\(JSJSON.numberToString($0))"] }
        pairs.sort { $0.utf16.lexicographicallyPrecedes($1.utf16) }
        spec = pairs.joined(separator: ";")
      } else {
        spec = request.weights.map(JSJSON.numberToString).joined(separator: ";")
      }
      features.append("wght@\(spec)")
    }
    let name = JSURI.encodeComponent(JS.trim(request.family)).replacingOccurrences(of: "%20", with: "+")
    return features.isEmpty ? name : "\(name):\(features.joined(separator: ","))"
  }

  /// The CSS2 request for every role that names a family, header, body and code in Quartz's order,
  /// then the title whole (Quartz asks only for its characters; a project holding its fonts would
  /// have to fetch again whenever the title changes). nil when no role names one.
  public static func css2Url(_ typography: JSONObject) -> String? {
    let families = roles.compactMap { request($0, typography[$0]) }.map(familyParameter)
    guard !families.isEmpty else { return nil }
    return "https://fonts.googleapis.com/css2?" + families.map { "family=\($0)" }.joined(separator: "&") + "&display=swap"
  }
}
