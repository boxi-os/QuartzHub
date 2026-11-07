// qh-check: the checks of QuartzHub, each a subcommand, each loading its logic from QuartzHubCore
// instead of copying it. Successor of QuartzControl's `npm run check:*` scripts.
//
//   swift run --package-path Packages/QuartzHubCore qh-check i18n [--root <repo>] [--unused]
//   swift run --package-path Packages/QuartzHubCore qh-check option-schema <projekt> [--plugin <name>] [--dump]
//   swift run --package-path Packages/QuartzHubCore qh-check inline-svg [projekt]
//   swift run --package-path Packages/QuartzHubCore qh-check export-window
//
// Exit codes: 0 all good, 1 findings, 2 wrong call, 3 could not check everything.
import Foundation
import QuartzHubCore

func usage() -> Never {
  print("""
  Aufruf: qh-check <befehl> [optionen]

    i18n [--root <repo>] [--unused]   Schlüssel der Aufrufe gegen den Katalog, Parität de/en,
                                      Platzhalter; --unused listet ungenutzte Schlüssel
    option-schema <projekt> [--plugin <name>] [--dump]
                                      wie viele Optionen je Plugin QuartzHub darstellen kann
                                      (Feld, nur Text, unsichtbar); --dump das Schema als JSON
    export-window                     das Exportfenster gegen QuartzControls Regel in WebKit:
                                      was ein zweiter Server erreicht, was gezählt wird, Frist,
                                      Abbruch, Seitenskripte (braucht Helpers/dist/page-scripts.js)
    export-pages <build> <chrome.json> [--out <webkit.json>]
                                      die Seitenskripte des Exports in WebKit gegen ihre Aufnahme
                                      in Chrome (scripts/export-pages-golden.mjs), ohne Netz
    inline-svg [projekt]              der SVG-Bereiniger gegen WebKit: jedes Ergebnis als HTML
                                      und, mit einem Projekt mit quartz-layout-box, durch dessen
                                      Markdown-Kette; Exit 3, wenn Lagen ausgelassen wurden
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
func repositoryRoot() -> String {
  if let given = option("--root") {
    let absolute = NodePath.normalize(given.hasPrefix("/") ? given : FileManager.default.currentDirectoryPath + "/" + given)
    return absolute.count > 1 && absolute.hasSuffix("/") ? String(absolute.dropLast()) : absolute
  }
  var dir = FileManager.default.currentDirectoryPath
  while dir != "/" {
    if FileManager.default.fileExists(atPath: "\(dir)/project.yml") { return dir }
    dir = NodePath.dirname(dir)
  }
  FileHandle.standardError.write(Data("project.yml nicht gefunden; --root <repo> angeben\n".utf8))
  exit(2)
}

/// The top level stays synchronous, so the main run loop can turn while an async command runs:
/// WebKit needs it (`inline-svg`), and an async top level neither turns it nor lets it be turned
/// (measured 2026-11-06: with `await` at the top, the first page never finished loading, and with a
/// loop turned inside, the main actor's work never ran).
func runAndExit(_ body: @escaping @MainActor () async -> Int32) -> Never {
  Task { @MainActor in exit(await body()) }
  RunLoop.main.run()
  exit(0)
}

switch command {
case "i18n":
  let root = repositoryRoot()
  let catalogURL = "\(root)/Packages/QuartzHubCore/Sources/QuartzHubCore/Resources/Localizable.xcstrings"
  let catalog: StringCatalog
  do {
    catalog = try StringCatalog.load(from: catalogURL)
  } catch {
    print("Katalog nicht lesbar (\(catalogURL)): \(error)")
    exit(3)
  }
  let sources = I18nCheck.swiftSources(in: [
    "\(root)/App",
    "\(root)/Packages/QuartzHubCore/Sources"
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
case "option-schema":
  // Report only, as QuartzControl's check:option-schema: an invisible option is a number in the
  // table, not an exit code. What could not be read is (3).
  let project = arguments.first { !$0.hasPrefix("--") && $0 != option("--plugin") }
  guard let project else { usage() }
  runAndExit {
    do {
      let report = try await OptionSchemaCheck.run(project: project, only: option("--plugin"), dump: arguments.contains("--dump"))
      print(report.text, terminator: "")
      return report.unreadable > 0 ? 3 : 0
    } catch {
      print(String(describing: error))
      return 2
    }
  }
case "export-window":
  // WebKit wants the main run loop turning (see runAndExit).
  setvbuf(stdout, nil, _IOLBF, 0)
  let root = repositoryRoot()
  runAndExit { await runExportWindowCheck(root: root) }
case "export-pages":
  setvbuf(stdout, nil, _IOLBF, 0)
  let positional = arguments.filter { !$0.hasPrefix("--") && $0 != option("--root") && $0 != option("--out") }
  guard positional.count == 2 else { usage() }
  let root = repositoryRoot()
  runAndExit { await runExportPagesCheck(root: root, build: positional[0], golden: positional[1], out: option("--out")) }
case "inline-svg":
  // WebKit wants the main run loop turning (see runAndExit).
  setvbuf(stdout, nil, _IOLBF, 0)
  let project = arguments.first { !$0.hasPrefix("--") && $0 != option("--root") }
  let root = repositoryRoot()
  runAndExit { await runInlineSvgCheck(project: project, root: root) }
default:
  usage()
}
