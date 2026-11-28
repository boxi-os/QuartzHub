import Foundation

/// `qh-check quartz-facts`: what QuartzHub reads from a project's Quartz, and where it keeps its
/// own constants instead. In German, like the other reports.
public enum QuartzFactsReport {
  public static func text(_ facts: QuartzFacts) -> String {
    var lines: [String] = []
    switch facts.builtins {
    case .read(let entries):
      lines.append("Eingebaute Verarbeitung (aus quartz/plugins/builtins):")
      for entry in entries {
        let defaults = (entry.defaults ?? JSONObject()).keys.map { "\($0)=\(JSJSON.stringify(entry.defaults![$0]!))" }
        var line = "  \(entry.configKey)"
        if let order = entry.order { line += " (order \(JSJSON.stringify(.number(order))))" }
        line += ": " + (defaults.isEmpty ? "–" : defaults.joined(separator: ", "))
        if !entry.unresolved.isEmpty { line += "; nicht lesbar, QuartzHubs Wert: \(entry.unresolved.joined(separator: ", "))" }
        lines.append(line)
      }
    case .missing: lines.append("Eingebaute Verarbeitung: keine (älteres Quartz), QuartzHubs eigene Werte")
    case .unknown: lines.append("Eingebaute Verarbeitung: nicht lesbar, QuartzHubs eigene Werte")
    }
    switch facts.conditions {
    case .read(let conditions):
      lines.append("Layout-Bedingungen: \(conditions.names.joined(separator: ", "))" + (conditions.negation ? "; not-<name> kehrt jede um" : ""))
    case .missing: lines.append("Layout-Bedingungen: keine Datei, QuartzHubs eigene (\(LayoutBoard.builtinConditions.joined(separator: ", ")))")
    case .unknown: lines.append("Layout-Bedingungen: nicht lesbar, QuartzHubs eigene (\(LayoutBoard.builtinConditions.joined(separator: ", ")))")
    }
    if !facts.problems.isEmpty {
      lines.append("")
      lines.append("Nicht gelesen (Exit 3):")
      lines += facts.problems.map { "  \($0)" }
    }
    return lines.joined(separator: "\n") + "\n"
  }
}
