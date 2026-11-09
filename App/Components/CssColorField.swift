import AppKit
import QuartzHubCore
import SwiftUI

/// A CSS colour value as a field: the system's colour well, and the text beside it, which is the
/// value itself. The well shows what `CssColor` reads (a colour outside sRGB as near as the screen
/// gets); picking writes `#rrggbb`, or `rgba()` when the colour has an alpha. A value the well
/// cannot hold (a `var()`, `oklch()` once picked over) is edited in the text.
struct CssColorField: View {
  let name: String
  @Binding var value: String
  var identifier: String?

  var body: some View {
    HStack(spacing: 8) {
      ColorPicker(selection: Binding(get: { Self.color(value) }, set: { value = Self.css($0) }), supportsOpacity: true) {
        Text(name)
      }
      .labelsHidden()
      .help(CssColor.isDisplayable(value) ? value : L10n.t("styles.variables.swatchNone"))
      TextField(name, text: $value)
        .labelsHidden()
        .font(.system(.body, design: .monospaced))
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier(identifier ?? "")
    }
  }

  /// The colour the well shows: clear for what is no colour.
  static func color(_ value: String) -> Color {
    guard let c = CssColor.srgb(value) else { return .clear }
    return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
  }

  /// What the well writes back: eight bits per channel, the alpha as Chrome writes it.
  static func css(_ color: Color) -> String {
    guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return "#000000" }
    let byte = { (v: CGFloat) in max(0, min(255, Int((v * 255).rounded()))) }
    let r = byte(srgb.redComponent), g = byte(srgb.greenComponent), b = byte(srgb.blueComponent), a = byte(srgb.alphaComponent)
    if a == 255 { return String(format: "#%02x%02x%02x", r, g, b) }
    return "rgba(\(r), \(g), \(b), \(alpha(a)))"
  }

  /// Two decimals when they name the same eight bits, else three (`rgba()` as canvas writes it).
  static func alpha(_ a: Int) -> String {
    let value = Double(a) / 255
    let two = (value * 100).rounded() / 100
    let chosen = Int((two * 255).rounded()) == a ? two : (value * 1000).rounded() / 1000
    var text = String(format: "%.3f", chosen)
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text
  }
}
