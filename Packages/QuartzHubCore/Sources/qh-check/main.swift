// qh-check: the checks of QuartzHub, each a subcommand, each loading its logic from QuartzHubCore
// instead of copying it. Successor of QuartzControl's `npm run check:*` scripts.
//
//   swift run --package-path Packages/QuartzHubCore qh-check i18n [--root <repo>] [--unused]
//
// Exit codes: 0 all good, 1 findings, 2 wrong call, 3 could not check everything.
import Foundation
import QuartzHubCore

func usage() -> Never {
  print("""
  Aufruf: qh-check <befehl> [optionen]

    i18n [--root <repo>] [--unused]   Schlüssel der Aufrufe gegen den Katalog, Parität de/en,
                                      Platzhalter; --unused listet ungenutzte Schlüssel
  """)
  exit(2)
}

let allArguments = Array(CommandLine.arguments.dropFirst())
guard let command = allArguments.first else { usage() }
let arguments = Array(allArguments.dropFirst())

func option(_ name: String) -> String? {
  guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
  return arguments[index + 1]
}

/// The repository root: --root, else the nearest parent of the working directory with project.yml.
func repositoryRoot() -> URL {
  if let given = option("--root") { return URL(fileURLWithPath: given).standardizedFileURL }
  var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  while url.path != "/" {
    if FileManager.default.fileExists(atPath: url.appendingPathComponent("project.yml").path) { return url }
    url.deleteLastPathComponent()
  }
  FileHandle.standardError.write(Data("project.yml nicht gefunden; --root <repo> angeben\n".utf8))
  exit(2)
}

switch command {
case "i18n":
  let root = repositoryRoot()
  let catalogURL = root.appendingPathComponent("Packages/QuartzHubCore/Sources/QuartzHubCore/Resources/Localizable.xcstrings")
  let catalog: StringCatalog
  do {
    catalog = try StringCatalog.load(from: catalogURL)
  } catch {
    print("Katalog nicht lesbar (\(catalogURL.path)): \(error)")
    exit(3)
  }
  let sources = I18nCheck.swiftSources(in: [
    root.appendingPathComponent("App"),
    root.appendingPathComponent("Packages/QuartzHubCore/Sources")
  ])
  let report: I18nCheck.Report
  do {
    report = try I18nCheck.run(catalog: catalog, sources: sources, relativeTo: root)
  } catch {
    print("Quelltext nicht lesbar: \(error)")
    exit(3)
  }
  func section(_ title: String, _ lines: [String]) {
    guard !lines.isEmpty else { return }
    print("\n\(title) (\(lines.count)):")
    lines.prefix(200).forEach { print("  \($0)") }
    if lines.count > 200 { print("  … und \(lines.count - 200) weitere") }
  }
  print("\(catalog.entries.count) Schlüssel im Katalog, \(report.scannedFiles) Swift-Dateien, \(report.usedKeyCount) Schlüssel benutzt")
  section("Fehlen im Katalog", report.missingKeys.map { "\($0.key)  (\($0.location))" })
  section("Lücken zwischen de und en", report.languageGaps)
  section("Platzhalter unterscheiden sich", report.placeholderMismatches)
  section("Nicht prüfbar (Schlüssel ist kein Literal)", report.dynamicCalls)
  if arguments.contains("--unused") {
    section("Ungenutzt", report.unusedKeys)
  } else {
    print("\(report.unusedKeys.count) Schlüssel ungenutzt (--unused listet sie)")
  }
  if report.hasErrors { exit(1) }
  // Dynamic keys are not an error, but they are not "checked" either.
  if !report.dynamicCalls.isEmpty {
    print("\nNicht alles geprüft: \(report.dynamicCalls.count) Aufrufe mit berechnetem Schlüssel")
    exit(3)
  }
  print("\nAlles geprüft, keine Befunde.")
default:
  usage()
}
