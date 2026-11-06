import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowLayer as String] as? Int) == 0 { print(w[kCGWindowOwnerName as String] ?? "-", w[kCGWindowNumber as String] ?? "-") }
