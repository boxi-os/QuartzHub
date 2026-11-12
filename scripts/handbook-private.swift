// Prüft das Handbuch auf Persönliches: Text der Seiten und, per Texterkennung, die Aufnahmen
// (docs/plan.md, Handbuch; Vorgabe des Nutzers vom 2026-11-12).
//
//   swift scripts/handbook-private.swift <vault> [<datei oder ordner> …]
//
// Gesucht wird nach dem Kurz- und dem vollen Namen des angemeldeten Kontos, dem Home-Ordner, jedem
// /Users/…-Pfad außer /Users/Shared, Mail-Adressen und den Wörtern aus <vault>/private/privat.txt
// (eine Zeile je Wort; der Ordner private wird nicht gebaut, die Liste bleibt also privat).
// Ohne weitere Angaben: alle .md und alle Bilder unter assets/ des Vaults. Exit 0: nichts gefunden,
// 1: Funde (je Fund Datei, Wort, Zeile), 2: Aufruf falsch.
import AppKit
import Foundation
import Vision

let args = Array(CommandLine.arguments.dropFirst())
guard let vault = args.first else {
  FileHandle.standardError.write("Aufruf: swift scripts/handbook-private.swift <vault> [<datei oder ordner> …]\n".data(using: .utf8)!)
  exit(2)
}

var words: [String] = [NSUserName(), NSHomeDirectory()]
words += NSFullUserName().split(separator: " ").map(String.init).filter { $0.count > 2 }
if let extra = try? String(contentsOfFile: "\(vault)/private/privat.txt", encoding: .utf8) {
  words += extra.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
}
// The project's public GitHub name may stand (the account's short name is often a part of it),
// and the placeholder of the folder fields ("/Users/du/Dokumente", "/Users/you/Documents").
let allowed = ["boxi-os", "/Users/du/", "/Users/you/"]
let patterns = [#"/Users/(?!Share)[^/\s]+"#, #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#]

func findings(in text: String) -> [String] {
  var out: [String] = []
  var cleaned = text
  for a in allowed { cleaned = cleaned.replacingOccurrences(of: a, with: "", options: .caseInsensitive) }
  for line in cleaned.split(separator: "\n", omittingEmptySubsequences: false) {
    let l = String(line)
    for w in words where l.range(of: w, options: .caseInsensitive) != nil { out.append("\(w): \(l.trimmingCharacters(in: .whitespaces))") }
    for p in patterns where l.range(of: p, options: .regularExpression) != nil {
      // A placeholder address the handbook may show on purpose.
      if l.contains("example.invalid") || l.contains("example.com") || l.contains("example.org") { continue }
      out.append("Muster: \(l.trimmingCharacters(in: .whitespaces))")
    }
  }
  return out
}

func recognized(_ path: String) -> String {
  guard let image = NSImage(contentsOfFile: path), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
  let request = VNRecognizeTextRequest()
  request.recognitionLevel = .accurate
  request.recognitionLanguages = ["de-DE", "en-US"]
  request.usesLanguageCorrection = false
  try? VNImageRequestHandler(cgImage: cg).perform([request])
  return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
}

let fm = FileManager.default
var files: [String] = []
let roots = args.count > 1 ? Array(args.dropFirst()) : [vault]
for root in roots {
  var isDir: ObjCBool = false
  guard fm.fileExists(atPath: root, isDirectory: &isDir) else { continue }
  if !isDir.boolValue { files.append(root); continue }
  guard let walk = fm.enumerator(atPath: root) else { continue }
  for case let rel as String in walk {
    if rel.hasPrefix(".git") || rel.hasPrefix("private") || rel.contains("/.") { continue }
    let ext = (rel as NSString).pathExtension.lowercased()
    if ["md", "png", "jpg", "jpeg", "webp", "html", "json", "yaml", "yml"].contains(ext) { files.append("\(root)/\(rel)") }
  }
}

var found = 0
for file in files.sorted() {
  let ext = (file as NSString).pathExtension.lowercased()
  let text = ["png", "jpg", "jpeg", "webp"].contains(ext) ? recognized(file) : ((try? String(contentsOfFile: file, encoding: .utf8)) ?? "")
  for f in findings(in: text) {
    print("\(file): \(f)")
    found += 1
  }
}
print(found == 0 ? "Nichts Persönliches gefunden (\(files.count) Dateien)." : "\(found) Funde in \(files.count) Dateien.")
exit(found == 0 ? 0 : 1)
