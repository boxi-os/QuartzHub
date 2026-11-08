import ApplicationServices
import AppKit

let args = CommandLine.arguments
let pid = pid_t(args[1])!
let app = AXUIElementCreateApplication(pid)
func attr(_ e: AXUIElement, _ n: String) -> AnyObject? { var v: AnyObject?; return AXUIElementCopyAttributeValue(e, n as CFString, &v) == .success ? v : nil }
func all(_ e: AXUIElement, depth: Int = 0, into out: inout [AXUIElement]) {
  out.append(e)
  guard depth < 15, let kids = attr(e, "AXChildren") as? [AXUIElement] else { return }
  for k in kids { all(k, depth: depth + 1, into: &out) }
}
func elements() -> [AXUIElement] { var out: [AXUIElement] = []; all(app, into: &out); return out }
func byId(_ id: String) -> AXUIElement? { elements().first { (attr($0, "AXIdentifier") as? String) == id } }
func actions(_ e: AXUIElement) -> [String] { var a: CFArray?; AXUIElementCopyActionNames(e, &a); return (a as? [String]) ?? [] }
func frame(_ e: AXUIElement) -> CGRect {
  var p = CGPoint.zero, s = CGSize.zero
  AXValueGetValue(attr(e, "AXPosition") as! AXValue, .cgPoint, &p); AXValueGetValue(attr(e, "AXSize") as! AXValue, .cgSize, &s)
  return CGRect(origin: p, size: s)
}

switch args[2] {
case "dump":
  for e in elements() {
    let id = attr(e, "AXIdentifier") as? String ?? ""
    let role = attr(e, "AXRole") as? String ?? ""
    if id.hasPrefix("row.") || role == "AXRow" || role == "AXOutline" || role == "AXTable" || id == "list" {
      print(role, id, "actions:", actions(e).map { $0.split(separator: "\n").first.map(String.init) ?? $0 })
    }
  }
case "perform":  // perform <id> <action-substring>
  guard let e = byId(args[3]) else { print("no", args[3]); exit(1) }
  let candidates = [e] + ((attr(e, "AXParent")).map { [$0 as! AXUIElement] } ?? [])
  for c in candidates { if let a = actions(c).first(where: { $0.contains(args[4]) }) { print("perform", a.debugDescription, AXUIElementPerformAction(c, a as CFString).rawValue); exit(0) } }
  print("action not found")
case "drag":  // drag <fromId> <toId>
  let a = frame(byId(args[3])!), b = frame(byId(args[4])!)
  let from = CGPoint(x: a.midX, y: a.midY), to = CGPoint(x: b.midX, y: b.maxY - 2)
  func post(_ t: CGEventType, _ p: CGPoint) { CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap); usleep(30_000) }
  post(.leftMouseDown, from)
  for i in 1...20 { let f = CGFloat(i) / 20; post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * f, y: from.y + (to.y - from.y) * f)) }
  usleep(300_000); post(.leftMouseUp, to); print("dragged", from, "->", to)
case "listen":  // listen <seconds>
  var obs: AXObserver?
  AXObserverCreateWithInfoCallback(pid, { _, _, note, info, _ in
    print("notification:", note, (info as NSDictionary)["AXAnnouncementKey"] ?? info); fflush(stdout)
  }, &obs)
  print("add:", AXObserverAddNotification(obs!, app, "AXAnnouncementRequested" as CFString, nil).rawValue); fflush(stdout)
  CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs!), .defaultMode)
  CFRunLoopRunInMode(.defaultMode, Double(args[3])!, false)
default: break
}
