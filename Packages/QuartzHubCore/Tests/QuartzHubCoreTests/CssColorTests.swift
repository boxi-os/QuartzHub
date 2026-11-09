import Foundation
import Testing
@testable import QuartzHubCore

/// CssColor against Chrome's canvas (`scripts/css-color-golden.mjs`): what canvas makes of each
/// value, QuartzControl's `cssColorToHexAlpha` and `isDisplayableColor`, and the pixel Chrome paints.
struct CssColorTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/css-color")

  /// What CssColor does not read (see its comment), each with Chrome's answer in the golden.
  static let notRead: Set<String> = ["Canvas", "CanvasText", "ButtonText", "rgb(from red r g b)"]

  struct Case {
    var value: String
    var canvas: String?
    var hexAlpha: (hex: String, alpha: Double)?
    var displayable: Bool
    var overWhite: [Int]?
    var overBlack: [Int]?
  }

  static func cases() throws -> [Case] {
    let list = try JSJSON.parse(Data(contentsOf: fixtures.appendingPathComponent("colors.json"))).arrayValue ?? []
    return list.map { entry in
      var hexAlpha: (String, Double)?
      if case .object(let pair)? = entry["hexAlpha"], case .string(let hex)? = pair["hex"], case .number(let alpha)? = pair["alpha"] {
        hexAlpha = (hex, alpha)
      }
      func pixel(_ key: String) -> [Int]? { entry[key]?.arrayValue?.compactMap { $0.numberValue.map(Int.init) } }
      return Case(value: entry["value"]?.stringValue ?? "", canvas: entry["canvas"]?.stringValue, hexAlpha: hexAlpha,
                  displayable: entry["displayable"] == .bool(true), overWhite: pixel("overWhite"), overBlack: pixel("overBlack"))
    }
  }

  @Test func theGoldenIsBigEnough() throws {
    let all = try Self.cases()
    #expect(all.count > 1000)
    #expect(all.filter(\.displayable).count > 350)
    #expect(all.contains { $0.canvas?.hasPrefix("oklch(") == true })
    #expect(all.contains { $0.canvas?.hasPrefix("color(srgb ") == true })
  }

  @Test func canvasFormHexAndDisplayable() throws {
    var mismatches: [String] = []
    for c in try Self.cases() where !Self.notRead.contains(c.value) {
      let probe = CssColor.probe(c.value)
      if (probe == nil) != (c.canvas == nil) {
        mismatches.append("\(c.value): canvas \(c.canvas ?? "nil"), here \(String(describing: probe))")
        continue
      }
      switch probe {
      case .legacy(let r, let g, let b, let a)?:
        let text = a == 255 ? CssColor.hex(r, g, b) : "rgba(\(r), \(g), \(b), \(CssColor.legacyAlpha(a)))"
        if text != c.canvas { mismatches.append("\(c.value): canvas \(c.canvas ?? ""), here \(text)") }
      case .srgbFunction(let text)?:
        if text != c.canvas { mismatches.append("\(c.value): canvas \(c.canvas ?? ""), here \(text)") }
      case .other(let color)?:
        // Canvas writes the colour in its own space; read back, it has to be the same colour.
        guard let canvas = c.canvas, let theirs = CssColor.parse(canvas) else {
          mismatches.append("\(c.value): canvas \(c.canvas ?? "") is not read here"); continue
        }
        if theirs.space != color.space { mismatches.append("\(c.value): space \(theirs.space), here \(color.space)"); continue }
        for (index, (a, b)) in zip(color.components, theirs.components).enumerated() {
          guard let a, let b else { continue }
          let tolerance = color.space.hueIndex == index ? 0.05 : max(1e-4, abs(b) * 5e-4)
          if abs(a - b) > tolerance { mismatches.append("\(c.value): component \(index) \(b), here \(a)") }
        }
        if abs((color.alpha ?? 1) - (theirs.alpha ?? 1)) > 1e-4 { mismatches.append("\(c.value): alpha \(theirs.alpha ?? 1), here \(color.alpha ?? 1)") }
      case nil:
        break
      }
      let mine = CssColor.hexAlpha(c.value)
      if mine?.hex != c.hexAlpha?.hex || mine?.alpha != c.hexAlpha?.alpha {
        mismatches.append("\(c.value): hexAlpha \(String(describing: c.hexAlpha)), here \(String(describing: mine))")
      }
      if CssColor.isDisplayable(c.value) != c.displayable {
        mismatches.append("\(c.value): displayable \(c.displayable), here \(!c.displayable)")
      }
    }
    #expect(mismatches.isEmpty, "\(mismatches.count) mismatches:\n\(mismatches.prefix(40).joined(separator: "\n"))")
  }

  /// The swatch: the colour clipped into sRGB, laid over white and over black in eight bits.
  @Test func paintsWhatChromePaints() throws {
    var mismatches: [String] = []
    for c in try Self.cases() where !Self.notRead.contains(c.value) {
      guard let white = c.overWhite, let black = c.overBlack, c.displayable else { continue }
      guard let color = CssColor.srgb(c.value) else { mismatches.append("\(c.value): no colour here"); continue }
      let alpha = Double(CssColor.byte(color.a)) / 255
      for (ground, expected) in [(1.0, white), (0.0, black)] {
        let got = [color.r, color.g, color.b].map { channel in
          Int(((max(0, min(1, channel)) * alpha + ground * (1 - alpha)) * 255).rounded())
        }
        if zip(got, expected).contains(where: { abs($0 - $1) > 2 }) {
          mismatches.append("\(c.value) over \(ground == 1 ? "white" : "black"): Chrome \(expected), here \(got)")
        }
      }
    }
    #expect(mismatches.isEmpty, "\(mismatches.count) mismatches:\n\(mismatches.prefix(40).joined(separator: "\n"))")
  }

  @Test func whatIsNotReadIsSaidSo() throws {
    // Chrome reads these; CssColor does not, and the golden says what Chrome answers.
    for c in try Self.cases() where Self.notRead.contains(c.value) {
      #expect(c.canvas != nil)
      #expect(CssColor.probe(c.value) == nil)
    }
  }
}
