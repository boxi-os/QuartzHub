import ApplicationServices
import Foundation

let pid = pid_t(CommandLine.arguments[1])!
let app = AXUIElementCreateApplication(pid)

func attr(_ e: AXUIElement, _ n: String) -> AnyObject? {
  var v: AnyObject?; return AXUIElementCopyAttributeValue(e, n as CFString, &v) == .success ? v : nil
}
func find(_ e: AXUIElement, depth: Int = 0) -> AXUIElement? {
  if (attr(e, "AXIdentifier") as? String) == "editor" { return e }
  guard depth < 12, let kids = attr(e, "AXChildren") as? [AXUIElement] else { return nil }
  for k in kids { if let f = find(k, depth: depth + 1) { return f } }
  return nil
}
guard let ed = find(app) else { print("no editor element"); exit(1) }
var names: CFArray?; AXUIElementCopyAttributeNames(ed, &names)
var pnames: CFArray?; AXUIElementCopyParameterizedAttributeNames(ed, &pnames)
print("role:", attr(ed, "AXRole") ?? "nil", "/ roleDescription:", attr(ed, "AXRoleDescription") ?? "nil")
print("value length:", (attr(ed, "AXValue") as? String)?.count ?? -1, "numberOfCharacters:", attr(ed, "AXNumberOfCharacters") ?? "nil")
print("insertionPointLine:", attr(ed, "AXInsertionPointLineNumber") ?? "nil", "selectedRange:", attr(ed, "AXSelectedTextRange") ?? "nil")
print("visibleRange:", attr(ed, "AXVisibleCharacterRange") ?? "nil")
print("attributes:", (names as? [String])?.sorted().joined(separator: ",") ?? "")
print("parameterized:", (pnames as? [String])?.sorted().joined(separator: ",") ?? "")
var line: AnyObject?
let idx = 500 as CFNumber
print("AXLineForIndex(500):", AXUIElementCopyParameterizedAttributeValue(ed, "AXLineForIndex" as CFString, idx, &line) == .success ? line! : "fails" as AnyObject)
var r = CFRange(location: 0, length: 40); let rv = AXValueCreate(.cfRange, &r)!
var s: AnyObject?
print("AXStringForRange(0,40):", AXUIElementCopyParameterizedAttributeValue(ed, "AXStringForRange" as CFString, rv, &s) == .success ? (s as! String).debugDescription : "fails")
var settable: DarwinBoolean = false; AXUIElementIsAttributeSettable(ed, "AXValue" as CFString, &settable)
print("AXValue settable:", settable.boolValue)
