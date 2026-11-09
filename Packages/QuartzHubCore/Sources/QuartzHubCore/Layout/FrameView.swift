import Foundation

/// A frame definition as the Layout page reads it, typed: `GridFrameDefinition` of QuartzControl's
/// `ipc-contract.ts`. Read leniently, the way the renderer's property accesses read a frame.json
/// that never went through `FrameDefinitionCheck`: a missing string is "", a missing number 0, and
/// `hidden` counts when it is truthy. The editor itself writes the JSON (`FrameEditing`), so key
/// order and unknown keys of the file stay where they were; this view is only for drawing and
/// for the rules that look at a frame.
public struct FrameView: Equatable, Sendable, Identifiable {
  public struct Area: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// One of the six positions or `pageBody`; nil for a spacer.
    public var slot: String?
    public var group: String?
  }

  public struct Placement: Equatable, Sendable {
    public var row: Int
    public var col: Int
    public var rowSpan: Int
    public var colSpan: Int
    public var hidden: Bool

    public init(row: Int, col: Int, rowSpan: Int, colSpan: Int, hidden: Bool = false) {
      self.row = row
      self.col = col
      self.rowSpan = rowSpan
      self.colSpan = colSpan
      self.hidden = hidden
    }

    /// `p && !p.hidden`.
    public var shown: Bool { !hidden }
  }

  public struct Layout: Equatable, Sendable {
    public var rows: Int
    public var cols: Int
    public var columnSizes: [String]?
    public var rowSizes: [String]?
    public var rowGap: String
    public var columnGap: String
    public var maxWidth: String?
    public var align: String?
    public var paddingBlock: String?
    public var paddingInline: String?
    public var placements: [String: Placement]
  }

  public var json: JSONValue
  public var id: String
  public var frameName: String
  public var areas: [Area]
  public var breakpoints: [String: Layout]

  public init(_ json: JSONValue) {
    self.json = json
    id = Self.text(json["id"]) ?? ""
    frameName = Self.text(json["frameName"]) ?? ""
    areas = (json["areas"]?.arrayValue ?? []).map { area in
      Area(id: Self.text(area["id"]) ?? "", name: Self.text(area["name"]) ?? "",
           slot: Self.text(area["slot"]).flatMap { $0.isEmpty ? nil : $0 },
           group: Self.text(area["group"]).flatMap { $0.isEmpty ? nil : $0 })
    }
    var layouts: [String: Layout] = [:]
    for bp in GridFrameCss.breakpoints {
      layouts[bp] = Self.readLayout(json["breakpoints"]?[bp])
    }
    breakpoints = layouts
  }

  /// The layout of a breakpoint; an empty one where the file has none.
  public func layout(_ bp: String) -> Layout {
    breakpoints[bp] ?? Self.readLayout(nil)
  }

  /// The placement of an area on a breakpoint, hidden or not.
  public func placement(_ bp: String, _ areaId: String) -> Placement? {
    breakpoints[bp]?.placements[areaId]
  }

  /// Placed and not hidden on this breakpoint.
  public func isShown(_ area: Area, on bp: String) -> Bool {
    placement(bp, area.id)?.shown ?? false
  }

  static func text(_ value: JSONValue?) -> String? {
    switch value {
    case .string(let text)?: text
    case .number(let number)?: JS.string(.number(number))
    default: nil
    }
  }

  static func int(_ value: JSONValue?) -> Int {
    let number = JS.toNumber(value)
    return number.isFinite ? Int(number) : 0
  }

  static func strings(_ value: JSONValue?) -> [String]? {
    value?.arrayValue.map { $0.map { text($0) ?? "" } }
  }

  static func readLayout(_ value: JSONValue?) -> Layout {
    var placements: [String: Placement] = [:]
    for (key, raw) in (value?["placements"]?.objectValue).map({ object in object.keys.map { ($0, object[$0]!) } }) ?? []
    where JS.truthy(raw) {
      placements[key] = Placement(row: int(raw["row"]), col: int(raw["col"]), rowSpan: int(raw["rowSpan"]),
                                  colSpan: int(raw["colSpan"]), hidden: raw["hidden"].map(JS.truthy) ?? false)
    }
    return Layout(rows: int(value?["rows"]), cols: int(value?["cols"]),
                  columnSizes: strings(value?["columnSizes"]), rowSizes: strings(value?["rowSizes"]),
                  rowGap: text(value?["rowGap"]) ?? "", columnGap: text(value?["columnGap"]) ?? "",
                  maxWidth: text(value?["maxWidth"]), align: text(value?["align"]),
                  paddingBlock: text(value?["paddingBlock"]), paddingInline: text(value?["paddingInline"]),
                  placements: placements)
  }
}
