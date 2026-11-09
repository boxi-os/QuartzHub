import Foundation

/// The layout stage as a page in miniature: a frame's columns, gaps and paddings, reduced to the
/// width the stage has and never wider. A port of QuartzControl's
/// `routes/LayoutEditor/stageGeometry.ts`, measured with `scripts/stage-geometry-golden.mjs`.
///
/// Reduced through the proportions: every track is resolved to pixels at a reference width and
/// becomes a share of the stage, every gap and padding a share of the stage's width. A grid built
/// that way cannot be wider than its stage. Row heights are not reduced: a row size describes the
/// built page's content, and the stage's cells hold chips instead.
public enum StageGeometry {
  /// The window width each view stands for: a laptop, a tablet held upright, a phone. Reference
  /// points for the proportions, not breakpoints; those belong to the project.
  public static let referenceWidth: [String: Double] = ["desktop": 1456, "tablet": 1000, "mobile": 390]

  static let rootFontSize = 16.0

  /// JavaScript's `\s`.
  static func isSpace(_ c: Unicode.Scalar) -> Bool {
    switch c.value {
    case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: true
    default: false
    }
  }

  /// `lengthToPx`: a CSS length in px, or nil when it cannot be known without a page (`auto`,
  /// `min-content`, an `em`, a `var()`). px, rem, %, vw and `calc()`/`min()`/`max()`/`clamp()` over
  /// them, which is what frames hold (`calc((300px - 8rem) / 3)`).
  public static func lengthToPx(_ value: String, percentBase: Double, viewport: Double) -> Double? {
    var parser = LengthParser(source: Array(JS.trim(value).unicodeScalars), percentBase: percentBase, viewport: viewport)
    guard let result = parser.sum() else { return nil }
    parser.skip()
    guard parser.pos == parser.source.count else { return nil }
    // A bare 0 is a length in CSS; any other plain number is not.
    if !result.length && result.n != 0 { return nil }
    return result.n
  }

  struct LengthParser {
    let source: [Unicode.Scalar]
    let percentBase: Double
    let viewport: Double
    var pos = 0

    struct Val {
      var n: Double
      var length: Bool
    }

    func at(_ i: Int) -> Unicode.Scalar? { i >= 0 && i < source.count ? source[i] : nil }

    mutating func skip() {
      while let c = at(pos), StageGeometry.isSpace(c) { pos += 1 }
    }

    mutating func primary() -> Val? {
      skip()
      if at(pos) == "(" {
        pos += 1
        let v = sum()
        skip()
        guard at(pos) == ")" else { return nil }
        pos += 1
        return v
      }
      for name in ["calc", "min", "max", "clamp"] where matches(name + "(") {
        pos += name.count + 1
        var args: [Val] = []
        while true {
          guard let v = sum() else { return nil }
          args.append(v)
          skip()
          if at(pos) == "," {
            pos += 1
            continue
          }
          if at(pos) == ")" {
            pos += 1
            break
          }
          return nil
        }
        let ns = args.map(\.n)
        let length = args.contains(where: \.length)
        switch name {
        case "calc": return args.count == 1 ? args[0] : nil
        case "min": return Val(n: ns.min()!, length: length)
        case "max": return Val(n: ns.max()!, length: length)
        default: return args.count == 3 ? Val(n: min(max(ns[0], ns[1]), ns[2]), length: length) : nil
        }
      }
      return number()
    }

    /// Case-insensitive, as the `/i` regex.
    func matches(_ text: String) -> Bool {
      let scalars = Array(text.unicodeScalars)
      guard pos + scalars.count <= source.count else { return false }
      for (k, s) in scalars.enumerated() where String(source[pos + k]).lowercased() != String(s) { return false }
      return true
    }

    /// `/^([+-]?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?)(px|rem|%|vw)?/i`.
    mutating func number() -> Val? {
      var i = pos
      let digit = { (c: Unicode.Scalar?) in c.map { $0.value >= 48 && $0.value <= 57 } ?? false }
      if at(i) == "+" || at(i) == "-" { i += 1 }
      if digit(at(i)) {
        while digit(at(i)) { i += 1 }
        if at(i) == "." {
          i += 1
          while digit(at(i)) { i += 1 }
        }
      } else if at(i) == ".", digit(at(i + 1)) {
        i += 1
        while digit(at(i)) { i += 1 }
      } else {
        return nil
      }
      if at(i) == "e" || at(i) == "E" {
        var j = i + 1
        if at(j) == "+" || at(j) == "-" { j += 1 }
        if digit(at(j)) {
          while digit(at(j)) { j += 1 }
          i = j
        }
      }
      var text = String(String.UnicodeScalarView(source[pos..<i]))
      // "1." and "1.e5" are numbers to JavaScript, not to Swift.
      text = text.replacingOccurrences(of: ".e", with: ".0e").replacingOccurrences(of: ".E", with: ".0E")
      if text.hasSuffix(".") { text += "0" }
      if text.hasPrefix(".") || text.hasPrefix("+.") || text.hasPrefix("-.") { text = text.replacingOccurrences(of: ".", with: "0.") }
      guard let n = Double(text) else { return nil }
      pos = i
      for unit in ["px", "rem", "%", "vw"] where matches(unit) {
        pos += unit.count
        switch unit {
        case "px": return Val(n: n, length: true)
        case "rem": return Val(n: n * rootFontSize, length: true)
        case "%": return Val(n: n / 100 * percentBase, length: true)
        default: return Val(n: n / 100 * viewport, length: true)
        }
      }
      return Val(n: n, length: false)
    }

    mutating func product() -> Val? {
      guard var left = primary() else { return nil }
      while true {
        skip()
        let op = at(pos)
        guard op == "*" || op == "/" else { return left }
        pos += 1
        guard let right = primary() else { return nil }
        if op == "*" {
          if left.length && right.length { return nil }
          left = Val(n: left.n * right.n, length: left.length || right.length)
        } else {
          if right.length || right.n == 0 { return nil }
          left = Val(n: left.n / right.n, length: left.length)
        }
      }
    }

    mutating func sum() -> Val? {
      guard var left = product() else { return nil }
      while true {
        skip()
        let op = at(pos)
        // calc() wants whitespace around + and -; a sign glued to a number belongs to the number.
        guard op == "+" || op == "-", at(pos - 1).map { StageGeometry.isSpace($0) } ?? true else { return left }
        pos += 1
        guard let right = product() else { return nil }
        left = Val(n: op == "+" ? left.n + right.n : left.n - right.n, length: left.length || right.length)
      }
    }
  }

  enum Track {
    case px(Double)
    case fr(Double)
  }

  nonisolated(unsafe) static let frPattern = #/^(\d*\.?\d+)fr$/#.asciiOnlyDigits()
  nonisolated(unsafe) static let minmaxPattern = #/^minmax\((.+),\s*(\d*\.?\d+)fr\s*\)$/#.ignoresCase().asciiOnlyDigits()

  /// One track as CSS would read it here: a share of the free space, or a length. `minmax(a, nfr)`
  /// is the frame builder's own floor and counts as the fr; anything else (`auto`, `min-content`,
  /// a `var()`) is taken as `1fr` and reported, except `auto`, which takes what is left exactly as
  /// 1fr does when no other track is flexible.
  static func readTrack(_ size: String, percentBase: Double, viewport: Double) -> (track: Track, exact: Bool) {
    let s = JS.trim(size)
    if let m = s.wholeMatch(of: frPattern), let n = Double(m.1.hasPrefix(".") ? "0" + m.1 : String(m.1)) { return (.fr(n), true) }
    if let m = s.wholeMatch(of: minmaxPattern), let n = Double(m.2.hasPrefix(".") ? "0" + m.2 : String(m.2)) { return (.fr(n), true) }
    if let px = lengthToPx(s, percentBase: percentBase, viewport: viewport) { return (.px(max(0, px)), true) }
    return (.fr(1), s == "auto")
  }

  /// `Math.round(n * 1000) / 1000`.
  static func round(_ n: Double) -> Double { (n * 1000 + 0.5).rounded(.down) / 1000 }

  public struct Tracks: Equatable, Sendable {
    /// The share of each column, already rounded as QuartzControl writes it (`minmax(0, <w>fr)`).
    public var weights: [Double]
    /// Track sizes that could only be guessed.
    public var approximate: [String]

    public var css: String { weights.map { "minmax(0, \(JS.string(.number($0)))fr)" }.joined(separator: " ") }
  }

  /// `stageTracks`: tracks resolved at a width, as shares of it. `inner` is the width the tracks
  /// and the gaps between them share; `gap` is in px at the same width.
  public static func tracks(_ sizes: [String], inner: Double, gap: Double, viewport: Double) -> Tracks {
    let read = sizes.map { (size: $0, read: readTrack($0, percentBase: inner, viewport: viewport)) }
    let fixed = read.reduce(0.0) { if case .px(let px) = $1.read.track { $0 + px } else { $0 } }
    let frTotal = read.reduce(0.0) { if case .fr(let fr) = $1.read.track { $0 + fr } else { $0 } }
    // CSS gives fr tracks what the fixed ones and the gaps leave, and nothing when they leave nothing.
    let free = max(0, inner - fixed - gap * Double(max(0, sizes.count - 1)))
    let widths = read.map { item -> Double in
      switch item.read.track {
      case .px(let px): px
      case .fr(let fr): frTotal > 0 ? free * fr / frTotal : 0
      }
    }
    let total = widths.reduce(0, +)
    return Tracks(weights: widths.map { total > 0 ? round($0) : 1 }, approximate: read.filter { !$0.read.exact }.map(\.size))
  }

  public struct Frame: Equatable, Sendable {
    public var tracks: Tracks
    /// Gaps, width and paddings in percent of the stage's width (QuartzControl's `cqw` and `%`).
    public var columnGap: Double
    public var rowGap: Double
    public var width: Double
    public var align: String
    public var paddingBlock: Double
    public var paddingInline: Double

    /// The CSS QuartzControl put on the stage, for the golden.
    public var css: [String: String] {
      let cqw = { (percent: Double) in "\(JS.string(.number(percent)))cqw" }
      return ["gridTemplateColumns": tracks.css, "columnGap": cqw(columnGap), "rowGap": cqw(rowGap),
              "width": "\(JS.string(.number(width)))%",
              "marginInline": align == "center" ? "auto" : align == "right" ? "0 0 0 auto" : "0",
              "paddingBlock": cqw(paddingBlock), "paddingInline": cqw(paddingInline)]
    }
  }

  /// `stageFrame`: an own frame's breakpoint layout, reduced to the stage of `bp`'s reference width.
  public static func frame(_ layout: FrameView.Layout, _ bp: String) -> Frame {
    let viewport = referenceWidth[bp] ?? 1456
    let length = { (value: String?, base: Double) -> Double? in
      guard let value, !JS.trim(value).isEmpty else { return nil }
      return lengthToPx(value, percentBase: base, viewport: viewport)
    }
    let width = min(viewport, length(layout.maxWidth, viewport) ?? viewport)
    // Padding percentages refer to the page around the frame.
    let padInline = length(layout.paddingInline, viewport) ?? 0
    let padBlock = length(layout.paddingBlock, viewport) ?? 0
    let inner = max(0, width - 2 * padInline)
    let columnGap = lengthToPx(layout.columnGap, percentBase: inner, viewport: viewport) ?? 0
    let rowGap = lengthToPx(layout.rowGap, percentBase: inner, viewport: viewport) ?? 0
    let sizes = (0..<max(0, layout.cols)).map { i -> String in
      let size = (layout.columnSizes ?? []).indices.contains(i) ? JS.trim(layout.columnSizes![i]) : ""
      return size.isEmpty ? "1fr" : size
    }
    let share = { (px: Double) in round(px / viewport * 100) }
    return Frame(tracks: tracks(sizes, inner: inner, gap: columnGap, viewport: viewport),
                 columnGap: share(columnGap), rowGap: share(rowGap), width: round(width / viewport * 100),
                 align: layout.align ?? "left", paddingBlock: share(padBlock), paddingInline: share(padInline))
  }
}
