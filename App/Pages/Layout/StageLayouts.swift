import SwiftUI

/// Where a box of the stage sits: 1-based like CSS grid lines.
struct GridCell: LayoutValueKey {
  static let defaultValue = (row: 1, col: 1, rowSpan: 1, colSpan: 1)
}

extension View {
  func gridCell(row: Int, col: Int, rowSpan: Int = 1, colSpan: Int = 1) -> some View {
    layoutValue(key: GridCell.self, value: (row, col, rowSpan, colSpan))
  }
}

/// The stage's grid: a frame in miniature (`StageGeometry`). Columns share the width by weight,
/// gaps and paddings are fractions of the stage's width, every row is as high as what it holds:
/// a row size describes the built page, the stage's cells hold chips. Spans across rows give the
/// height they still need to their last row. The frame's own box (cap, alignment, paddings) is
/// drawn as on the page.
struct StageGridLayout: Layout {
  var weights: [Double]
  var rows: Int
  /// Fractions of the stage's width (QuartzControl's `cqw` / 100), or points where `points` is set.
  var columnGap: Double
  var rowGap: Double
  var points = false
  /// The frame's width as a fraction of the stage, and where it sits.
  var width = 1.0
  var align = "left"
  var paddingInline = 0.0
  var paddingBlock = 0.0
  /// The board of the frame editor: columns no narrower than this (WCAG's target size).
  var minColumn = 0.0

  struct Geometry {
    var columns: [CGFloat]
    var x0: CGFloat
    var rowHeights: [CGFloat]
    var colGap: CGFloat
    var rowGap: CGFloat
    var padBlock: CGFloat
    var total: CGSize
  }

  func geometry(_ proposal: ProposedViewSize, _ subviews: Subviews) -> Geometry {
    let stage = max(proposal.width ?? 600, 1)
    let scale = { (v: Double) in CGFloat(points ? v : v * stage) }
    let frame = stage * CGFloat(min(max(width, 0), 1))
    let padInline = scale(paddingInline)
    let padBlock = scale(paddingBlock)
    let colGap = scale(columnGap)
    let rowGap = scale(self.rowGap)
    let n = max(weights.count, 1)
    let inner = max(0, frame - 2 * padInline - colGap * CGFloat(n - 1))
    let total = weights.reduce(0, +)
    var columns = weights.isEmpty ? [inner] : weights.map { CGFloat(total > 0 ? $0 / total : 1 / Double(n)) * inner }
    if minColumn > 0 { columns = columns.map { max($0, CGFloat(minColumn)) } }
    let used = columns.reduce(0, +) + colGap * CGFloat(n - 1) + 2 * padInline
    let x0: CGFloat = switch align {
    case "center": max(0, (stage - used) / 2)
    case "right": max(0, stage - used)
    default: 0
    }
    var heights = Array(repeating: CGFloat(0), count: max(rows, 1))
    let cells = subviews.map { $0[GridCell.self] }
    let spanWidth = { (col: Int, span: Int) -> CGFloat in
      let lo = max(col - 1, 0), hi = min(col - 1 + span, columns.count)
      guard lo < hi else { return 0 }
      return columns[lo..<hi].reduce(0, +) + colGap * CGFloat(hi - lo - 1)
    }
    // Single rows first, then spans give their last row what is still missing.
    for pass in 0..<2 {
      for (k, subview) in subviews.enumerated() {
        let c = cells[k]
        guard c.row >= 1, c.row <= heights.count, (c.rowSpan <= 1) == (pass == 0) else { continue }
        let h = subview.sizeThatFits(ProposedViewSize(width: spanWidth(c.col, c.colSpan), height: nil)).height
        let last = min(c.row - 1 + max(c.rowSpan, 1), heights.count) - 1
        let have = heights[(c.row - 1)...last].reduce(0, +) + rowGap * CGFloat(last - c.row + 1)
        if h > have { heights[last] += h - have }
      }
    }
    let height = heights.reduce(0, +) + rowGap * CGFloat(max(heights.count - 1, 0)) + 2 * padBlock
    return Geometry(columns: columns, x0: x0 + padInline, rowHeights: heights, colGap: colGap, rowGap: rowGap, padBlock: padBlock,
                    total: CGSize(width: max(stage, used), height: height))
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    geometry(proposal, subviews).total
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let g = geometry(ProposedViewSize(width: bounds.width, height: bounds.height), subviews)
    let colX = { (col: Int) -> CGFloat in
      g.x0 + g.columns.prefix(max(col - 1, 0)).reduce(0, +) + g.colGap * CGFloat(max(col - 1, 0))
    }
    let rowY = { (row: Int) -> CGFloat in
      g.padBlock + g.rowHeights.prefix(max(row - 1, 0)).reduce(0, +) + g.rowGap * CGFloat(max(row - 1, 0))
    }
    for subview in subviews {
      let c = subview[GridCell.self]
      guard c.row >= 1, c.row <= g.rowHeights.count, c.col >= 1, c.col <= g.columns.count else {
        subview.place(at: .zero, proposal: .zero)
        continue
      }
      let colEnd = min(c.col - 1 + c.colSpan, g.columns.count)
      let rowEnd = min(c.row - 1 + c.rowSpan, g.rowHeights.count)
      let w = g.columns[(c.col - 1)..<colEnd].reduce(0, +) + g.colGap * CGFloat(colEnd - c.col)
      let h = g.rowHeights[(c.row - 1)..<rowEnd].reduce(0, +) + g.rowGap * CGFloat(rowEnd - c.row)
      subview.place(at: CGPoint(x: bounds.minX + colX(c.col), y: bounds.minY + rowY(c.row)), anchor: .topLeading,
                    proposal: ProposedViewSize(width: w, height: h))
    }
  }

  /// The frame's grid lines in the layout's own coordinates, for dragging an edge in the editor.
  func lines(width: CGFloat, subviews: Subviews) -> (columns: [(CGFloat, CGFloat)], rows: [(CGFloat, CGFloat)]) {
    let g = geometry(ProposedViewSize(width: width, height: nil), subviews)
    var x = g.x0, cols: [(CGFloat, CGFloat)] = []
    for w in g.columns { cols.append((x, x + w)); x += w + g.colGap }
    var y = g.padBlock, rows: [(CGFloat, CGFloat)] = []
    for h in g.rowHeights { rows.append((y, y + h)); y += h + g.rowGap }
    return (cols, rows)
  }
}

/// Chips side by side, wrapping: a sidebar that is a row on a narrow view (base.scss).
struct FlowLayout: Layout {
  var spacing: CGFloat = 6
  /// No chip narrower than this.
  var minItem: CGFloat = 96
  /// Each one grows to share its line (the stage's sidebars); otherwise each keeps its own width.
  var stretch = true

  func lines(_ width: CGFloat, _ subviews: Subviews) -> [[Int]] {
    var lines: [[Int]] = [[]]
    var x: CGFloat = 0
    for (k, subview) in subviews.enumerated() {
      let w = min(max(subview.sizeThatFits(.unspecified).width, minItem), width)
      if x > 0, x + w > width {
        lines.append([])
        x = 0
      }
      lines[lines.count - 1].append(k)
      x += w + spacing
    }
    return lines
  }

  func itemWidth(_ k: Int, _ line: [Int], _ width: CGFloat, _ subviews: Subviews) -> CGFloat {
    if stretch { return (width - spacing * CGFloat(line.count - 1)) / CGFloat(line.count) }
    return min(max(subviews[k].sizeThatFits(.unspecified).width, minItem), width)
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? 400
    var height: CGFloat = 0
    for line in lines(width, subviews) where !line.isEmpty {
      height += line.map { subviews[$0].sizeThatFits(ProposedViewSize(width: itemWidth($0, line, width, subviews), height: nil)).height }.max() ?? 0
      height += spacing
    }
    return CGSize(width: width, height: max(0, height - spacing))
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var y = bounds.minY
    for line in lines(bounds.width, subviews) where !line.isEmpty {
      var x = bounds.minX
      var height: CGFloat = 0
      for k in line {
        let each = itemWidth(k, line, bounds.width, subviews)
        let size = subviews[k].sizeThatFits(ProposedViewSize(width: each, height: nil))
        subviews[k].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: each, height: size.height))
        x += each + spacing
        height = max(height, size.height)
      }
      y += height + spacing
    }
  }
}
