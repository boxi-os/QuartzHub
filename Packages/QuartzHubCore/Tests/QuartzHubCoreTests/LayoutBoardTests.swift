import Foundation
import Testing
@testable import QuartzHubCore

/// `LayoutBoard`, `PageTypeOverride` and the overview's cells against QuartzControl's own code
/// (`scripts/layout-board-golden.mjs`): gui-test's and Example's configs with gui-test's frames,
/// and a made-up board with the edges. The stage's reasons, which QuartzControl computed inside its
/// component, are checked by hand below.
@Suite struct LayoutBoardTests {
  static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/layout-board")
  static let golden: JSONValue? = (try? Data(contentsOf: directory.appendingPathComponent("cases.json"))).flatMap { try? JSJSON.parse($0) }

  struct Board {
    let name: String
    let config: QuartzConfig
    let frames: [FrameView]
    let raw: JSONValue
  }

  static func boards() throws -> [Board] {
    let boards = try #require(golden?["boards"]?.arrayValue)
    return try boards.map { raw in
      Board(name: raw["name"]?.stringValue ?? "", config: try #require(QuartzConfig(jsonValue: raw["config"]!)),
            frames: (raw["frames"]?.arrayValue ?? []).map(FrameView.init), raw: raw)
    }
  }

  static func ints(_ value: JSONValue?) -> [Int] { (value?.arrayValue ?? []).compactMap { $0.numberValue.map { Int($0) } } }
  static func strings(_ value: JSONValue?) -> [String] { (value?.arrayValue ?? []).compactMap(\.stringValue) }
  static func layout(_ entry: PluginEntry) -> JSONValue { entry.object["layout"] ?? .null }
  static func at(_ value: JSONValue?, _ k: Int) -> JSONValue? { value?.arrayValue.flatMap { k < $0.count ? $0[k] : nil } }
  /// The shape's maps with their keys sorted: QuartzControl's Map keeps the order areas came in.
  static func sorted(_ value: JSONValue?) -> JSONValue? {
    guard let object = value?.objectValue else { return value }
    let inner = { (v: JSONValue?) -> JSONValue in
      guard let o = v?.objectValue else { return v ?? .null }
      return .object(JSONObject(o.keys.sorted().map { ($0, o[$0]!) }))
    }
    return .object(JSONObject([("plain", inner(object["plain"])), ("groups", inner(object["groups"]))]))
  }

  @Test func countsTrayAndPageTypesAsQuartzControl() throws {
    let boards = try Self.boards()
    #expect(boards.map(\.name) == ["gui-test", "Example", "made"])
    for board in boards {
      let plugins = board.config.plugins
      #expect(LayoutBoard.pageTypes(board.config) == Self.strings(board.raw["pageTypes"]), "\(board.name)")
      let counts = try #require(board.raw["nameCounts"]?.objectValue)
      #expect(LayoutBoard.nameCounts(plugins).mapValues { JSONValue.number(Double($0)) } == Dictionary(uniqueKeysWithValues: counts.keys.map { ($0, counts[$0]!) }), "\(board.name)")
      #expect(LayoutBoard.trayChips(plugins) == Self.ints(board.raw["trayChips"]), "\(board.name)")
      let parked = LayoutBoard.parked(plugins)
      #expect(parked == Set(Self.ints(board.raw["parked"])), "\(board.name)")
      let positions = LayoutBoard.boardPositions(plugins, parked: parked)
      for position in LayoutEntries.positions {
        #expect(positions[position] == Self.ints(board.raw["boardPositions"]?[position]), "\(board.name) \(position)")
      }
      #expect(LayoutBoard.groupNames(board.config, frames: board.frames) == Self.strings(board.raw["groupNames"]), "\(board.name)")
    }
    // Gegenproben the boards carry: a parked component, a type only the config names.
    let made = try #require(boards.last)
    #expect(!LayoutBoard.parked(made.config.plugins).isEmpty)
    #expect(LayoutBoard.pageTypes(made.config).contains("excalidraw"))
  }

  @Test func changingAComponentWritesWhatQuartzControlWrites() throws {
    var checked = 0
    for board in try Self.boards() {
      let plugins = board.config.plugins
      for item in board.raw["perComponent"]?.arrayValue ?? [] {
        let i = Int(item["index"]!.numberValue!)
        let ref = LayoutEntries.componentRef(plugins, i)
        #expect(ref?.name == item["ref"]?["name"]?.stringValue)
        #expect(ref.map { LayoutBoard.resolve(plugins, name: $0.name, occurrence: $0.occurrence) } == i)
        let group = item["group"]?.arrayValue ?? []
        #expect(Self.layout(LayoutBoard.withGroup(plugins, i, "neu")[i]) == group[0], "\(board.name) \(i) group")
        #expect(Self.layout(LayoutBoard.withGroup(plugins, i, "")[i]) == group[1], "\(board.name) \(i) no group")
        for (k, display) in ["all", "desktop-only", "mobile-only", nil].enumerated() {
          #expect(Self.layout(LayoutBoard.withDisplay(plugins, i, display)[i]) == Self.at(item["display"], k), "\(board.name) \(i) \(display ?? "nil")")
        }
        for (k, condition) in ["  has-tags ", "", "eigene"].enumerated() {
          #expect(Self.layout(LayoutBoard.withCondition(plugins, i, condition)[i]) == Self.at(item["condition"], k), "\(board.name) \(i) \(condition)")
        }
        for (k, enabled) in [false, true].enumerated() {
          let entry = LayoutBoard.withEnabled(plugins, i, enabled)[i]
          #expect("\(entry.object.keys.joined(separator: ","))=\(entry.enabled)" == Self.at(item["enabled"], k)?.stringValue, "\(board.name) \(i)")
        }
        for option in item["groupOption"]?.arrayValue ?? [] {
          let value = option["value"] == .null ? nil : option["value"]
          let mine = LayoutBoard.withGroupOption(plugins, i, option["key"]!.stringValue!, value)
          #expect(Self.layout(mine[i]) == option["entry"], "\(board.name) \(i) \(JSJSON.compact(option))")
          #expect(mine.enumerated().allSatisfy { $0.offset == i || $0.element == plugins[$0.offset] })
          checked += 1
        }
        let options = item["options"]?.arrayValue ?? []
        for (k, given) in [nil, JSONObject([("neu", .number(1))])].enumerated() {
          let entry = LayoutBoard.withOptions(plugins, i, given)[i]
          #expect(entry.object.keys.map(JSONValue.string) == options[k]["keys"]?.arrayValue, "\(board.name) \(i)")
          #expect((entry.object["options"] ?? .null) == options[k]["options"], "\(board.name) \(i)")
        }
      }
    }
    #expect(checked > 500)
  }

  @Test func aChipFromTheTrayLandsWhereQuartzControlPutsIt() throws {
    var count = 0
    for board in try Self.boards() {
      let plugins = board.config.plugins
      for item in board.raw["appends"]?.arrayValue ?? [] {
        let i = Int(item["index"]!.numberValue!)
        let mine = LayoutBoard.appendDuplicate(plugins, i, position: item["position"]!.stringValue!,
                                               insertIndex: item["insertIndex"]?.numberValue.map { Int($0) }, styled: ["nav-zwei-2"])
        #expect(mine.map { JSONValue.array($0.plugins.map(Self.layout)) } == item["layouts"], "\(board.name) \(JSJSON.compact(item["position"]!))")
        #expect(mine.map { JSONValue.object($0.plugins[$0.newIndex].object) } == item["copy"], "\(board.name) \(i)")
        count += 1
      }
    }
    #expect(count == 90)
  }

  @Test func aDropPlacesWithTheBoardsLists() throws {
    var count = 0
    for board in try Self.boards() {
      let plugins = board.config.plugins
      let positions = LayoutBoard.boardPositions(plugins, parked: LayoutBoard.parked(plugins))
      for item in board.raw["places"]?.arrayValue ?? [] {
        let group: String?? = switch item["group"] { case .string("keep")?: nil; case .string(let g)?: .some(g); default: .some(nil) }
        let mine = LayoutEntries.place(plugins, index: Int(item["index"]!.numberValue!), position: item["position"]!.stringValue!,
                                       insertIndex: item["insertIndex"]?.numberValue.map { Int($0) }, group: group, positions: positions)
        #expect(JSONValue.array(mine.map(Self.layout)) == item["layouts"], "\(board.name) \(JSJSON.compact(item["index"]!)) \(item["position"]!.stringValue!)")
        count += 1
      }
    }
    #expect(count == 96)
  }

  @Test func pageTypeOverridesAsQuartzControl() throws {
    var cases = 0
    for board in try Self.boards() {
      let config = board.config
      let plugins = config.plugins
      let items = LayoutEntries.components(plugins).map(\.index)
      let pluginFrames = (Self.golden?["pluginFrames"]?.objectValue).map { o in Dictionary(uniqueKeysWithValues: o.keys.map { ($0, o[$0]!.stringValue!) }) } ?? [:]
      for item in board.raw["typeCases"]?.arrayValue ?? [] {
        let type = item["pageType"]!.stringValue!
        let override = PageTypeOverride.of(config, type)
        #expect(JSONValue.object(override) == item["override"], "\(board.name) \(type)")
        let stored = GridFrameCss.member(config.layout?["byPageType"], type)
        #expect(PageTypeOverride.customizes(stored?.objectValue) == item["customizes"]?.boolValue, "\(board.name) \(type)")
        #expect(PageTypeOverride.deadExcludes(config, override) == Self.strings(item["dead"]), "\(board.name) \(type)")
        #expect(items.map { JSONValue.bool(PageTypeOverride.isExcluded(override, plugins[$0])) } == item["excluded"]?.arrayValue, "\(board.name) \(type)")
        #expect(LayoutEntries.positions.map { JSONValue.bool(PageTypeOverride.isCleared(override, $0)) } == item["cleared"]?.arrayValue, "\(board.name) \(type)")
        func slice(_ next: QuartzConfig) -> JSONValue {
          let byPageType = LayoutBoxes.spread(next.layout?["byPageType"])
          return .object(JSONObject([("keys", .array(byPageType.keys.map(JSONValue.string))), ("value", byPageType[type] ?? .null)]))
        }
        func expected(_ c: JSONValue) -> JSONValue { .object(JSONObject([("keys", c["keys"]!), ("value", c["value"]!)])) }
        for c in item["withExcluded"]?.arrayValue ?? [] {
          let i = Int(c["index"]!.numberValue!)
          #expect(slice(PageTypeOverride.withExcluded(config, type, plugins[i], c["excluded"]!.boolValue!)) == expected(c), "\(board.name) \(type) \(i)")
          cases += 1
        }
        for c in item["withCleared"]?.arrayValue ?? [] {
          #expect(slice(PageTypeOverride.withCleared(config, type, c["position"]!.stringValue!, c["cleared"]!.boolValue!)) == expected(c), "\(board.name) \(type)")
        }
        for c in item["withTemplate"]?.arrayValue ?? [] {
          #expect(slice(PageTypeOverride.withTemplate(config, type, c["template"]?.stringValue)) == expected(c), "\(board.name) \(type)")
        }
        #expect(slice(PageTypeOverride.without(config, type)) == expected(item["without"]!), "\(board.name) \(type)")
        let resolved = PageTypeOverride.resolvedFrame(config, type, pluginFrames: pluginFrames)
        #expect(resolved.name == item["resolved"]?["name"]?.stringValue && resolved.from.rawValue == item["resolved"]?["from"]?.stringValue, "\(board.name) \(type)")
      }
    }
    #expect(cases > 300)
  }

  @Test func overviewCellsAsQuartzControl() throws {
    let pluginFrames: [String: String] = ["canvas-page": "canvas"]
    var states: Set<String> = []
    for board in try Self.boards() {
      let shapes = try #require(board.raw["shapes"]?.objectValue)
      for name in shapes.keys {
        let mine = LayoutStage.shape(name, frames: board.frames, pluginFrames: Set(pluginFrames.values))
        #expect(Self.json(mine) == Self.sorted(shapes[name]), "\(board.name) \(name)")
      }
      let types = LayoutBoard.pageTypes(board.config)
      let typeShapes = types.map { LayoutStage.shape(PageTypeOverride.resolvedFrame(board.config, $0, pluginFrames: pluginFrames).name,
                                                     frames: board.frames, pluginFrames: Set(pluginFrames.values)) }
      for row in board.raw["cells"]?.arrayValue ?? [] {
        let i = Int(row["index"]!.numberValue!)
        for (k, type) in types.enumerated() {
          let cell = LayoutStage.cell(board.config, i, pageType: type, shape: typeShapes[k])
          let want = Self.at(row["states"], k)
          #expect(Self.json(cell) == want, "\(board.name) \(i) \(type)")
          states.insert(want?["state"]?.stringValue ?? "")
        }
      }
    }
    // The boards reach these states; a check that only ever saw "shown" would prove little.
    #expect(states.isSuperset(of: ["shown", "excluded", "cleared", "noArea", "unknown"]))
  }

  @Test func rangeLabels() throws {
    for item in Self.golden?["ranges"]?.arrayValue ?? [] {
      let label = LayoutBoard.rangeLabel(item["bp"]!.stringValue!, widths: (item["tablet"]!.numberValue!, item["mobile"]!.numberValue!))
      #expect(label == item["label"]?.stringValue)
    }
  }

  static func json(_ placed: LayoutStage.Placed) -> JSONValue {
    switch placed {
    case .all: .string("all")
    case .on(let list): .array(list.map(JSONValue.string))
    }
  }

  static func json(_ shape: LayoutStage.Shape?) -> JSONValue {
    guard let shape else { return .null }
    let object = { (map: [String: LayoutStage.Placed]) in JSONValue.object(JSONObject(map.keys.sorted().map { ($0, json(map[$0]!)) })) }
    return .object(JSONObject([("plain", object(shape.plain)), ("groups", object(shape.groups))]))
  }

  static func json(_ cell: LayoutStage.Cell) -> JSONValue {
    let state: String
    switch cell {
    case .someWidths(let on): return .object(JSONObject([("state", .string("someWidths")), ("on", .array(on.map(JSONValue.string)))]))
    case .shown: state = "shown"
    case .excluded: state = "excluded"
    case .cleared: state = "cleared"
    case .noArea: state = "noArea"
    case .hiddenArea: state = "hiddenArea"
    case .noWidth: state = "noWidth"
    case .unknown: state = "unknown"
    }
    return .object(JSONObject([("state", .string(state))]))
  }

  // MARK: the stage, by hand

  static func entry(_ name: String, _ layout: JSONObject?, enabled: Bool = true) -> PluginEntry {
    var object = JSONObject([("source", .string("github:x/\(name)"))])
    if let layout { object["layout"] = .object(layout) }
    object["name"] = .string(name)
    object["enabled"] = .bool(enabled)
    return PluginEntry(object: object)
  }

  @Test func theStageSaysWhyAComponentIsMissing() throws {
    let search = Self.entry("search", JSONObject([("position", .string("left")), ("priority", .number(10)), ("display", .string("desktop-only"))]))
    let graph = Self.entry("graph", JSONObject([("position", .string("right")), ("priority", .number(10))]))
    let config = QuartzConfig(plugins: [search, graph], layout: JSONObject([("byPageType", .object(JSONObject([
      ("tag", .object(JSONObject([("exclude", .array([.string("search")]))]))),
      ("folder", .object(JSONObject([("positions", .object(JSONObject([("right", .array([]))])))]))),
    ])))]))
    #expect(LayoutStage.hidden(search, override: PageTypeOverride.of(config, "tag"), bp: "desktop") == .excluded)
    #expect(LayoutStage.hidden(graph, override: PageTypeOverride.of(config, "folder"), bp: "desktop") == .cleared)
    #expect(LayoutStage.hidden(search, override: nil, bp: "mobile") == .notInView)
    #expect(LayoutStage.hidden(search, override: nil, bp: "tablet") == nil)
    // The page type's answer comes before the view's.
    #expect(LayoutStage.hidden(search, override: PageTypeOverride.of(config, "tag"), bp: "mobile") == .excluded)
    #expect(LayoutStage.hiddenOnTypes(config, search, pageTypes: ["content", "tag", "folder"]) == ["tag"])
    #expect(LayoutStage.hiddenOnTypes(config, graph, pageTypes: ["content", "tag", "folder"]) == ["folder"])
  }

  @Test func anAreaHoldsItsGroupAndThePlainAreaTheRest() throws {
    let frame = FrameView(.object(JSONObject([
      ("id", .string("frame-1")), ("frameName", .string("f")),
      ("areas", .array([
        .object(JSONObject([("id", .string("a")), ("name", .string("left")), ("slot", .string("left"))])),
        .object(JSONObject([("id", .string("b")), ("name", .string("tools")), ("slot", .string("left")), ("group", .string("tools"))])),
      ])),
      ("breakpoints", .object(JSONObject([
        ("desktop", .object(JSONObject([("rows", .number(1)), ("cols", .number(2)), ("placements", .object(JSONObject([
          ("a", .object(JSONObject([("row", .number(1)), ("col", .number(1)), ("rowSpan", .number(1)), ("colSpan", .number(1))]))),
        ])))]))),
      ]))),
    ])))
    let plugins = [
      Self.entry("explorer", JSONObject([("position", .string("left")), ("priority", .number(10))])),
      Self.entry("darkmode", JSONObject([("position", .string("left")), ("priority", .number(20)), ("group", .string("tools"))])),
      Self.entry("reader", JSONObject([("position", .string("left")), ("priority", .number(30)), ("group", .string("other"))])),
    ]
    let positions = LayoutEntries.positionMap(plugins)
    #expect(LayoutStage.indices(for: frame.areas[0], in: frame, positions: positions, plugins: plugins) == [0, 2])
    #expect(LayoutStage.indices(for: frame.areas[1], in: frame, positions: positions, plugins: plugins) == [1])
    // The group area is not placed on desktop: its group is still claimed by it, not by the plain area.
    #expect(LayoutStage.shownAreas(frame, "desktop").map(\.id) == ["a"])
    #expect(LayoutStage.missingPositions(.own(frame), "desktop") == ["header", "right", "beforeBody", "afterBody", "footer"])
    #expect(LayoutStage.missingPositions(.builtin(name: "minimal", slots: ["footer"]), "desktop").count == 5)
    #expect(LayoutStage.missingPositions(.standard, "desktop").isEmpty)
    #expect(LayoutStage.frame(named: "f", frames: [frame], pluginFrames: [:]) == .own(frame))
    #expect(LayoutStage.frame(named: "canvas", frames: [], pluginFrames: ["canvas-page": "canvas"]) == .plugin(name: "canvas"))
    #expect(LayoutStage.frame(named: "gibtsnicht", frames: [], pluginFrames: [:]) == .unknown(name: "gibtsnicht"))
  }

  @Test func removingADuplicateKeepsTheSelectionOnItsEntry() {
    let plugins = (0..<4).map { Self.entry("n\($0)", JSONObject([("position", .string("left")), ("priority", .number(Double($0)))])) }
    #expect(LayoutBoard.removing(plugins, 1, selected: 3).selected == 2)
    #expect(LayoutBoard.removing(plugins, 1, selected: 0).selected == 0)
    #expect(LayoutBoard.removing(plugins, 1, selected: 1).selected == nil)
    #expect(LayoutBoard.removing(plugins, 1, selected: nil).plugins.map(\.name) == ["n0", "n2", "n3"])
  }
}
