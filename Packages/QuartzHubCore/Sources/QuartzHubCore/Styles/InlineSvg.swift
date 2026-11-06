import Foundation

/// An SVG file as markup to paste into a layout box's snippet, the one way to put a picture on the
/// site that CSS can style inside: a port of `src/utils/inlineSvg.ts` (QuartzControl ran it in the
/// renderer, on Chrome's DOMParser).
///
/// Pasted inline, the SVG is part of the page and runs in it. The file is read as XML, but the site
/// reads the result as HTML (quartz-layout-box through `dangerouslySetInnerHTML`, a Markdown snippet
/// through rehype-raw), and between the two parsers a block list leaks. So nothing is passed
/// through: the markup is written anew from an allow list. SVG elements only, none that HTML lets
/// break out of the SVG; attributes without a namespace, named the way HTML names them; values
/// checked the way CSS reads them, escapes included; text escaped for HTML and Markdown; no
/// comments, no processing instructions, no `<style>`. A link may go to `#…`, `https:` or
/// `mailto:`, a picture to `#…`, `https:` or a raster `data:` URL. Every id gets a prefix from the
/// file's name and content, and every reference to one follows, so two icons with Figma's
/// `clip0_1_2` do not share a clip path. `qh-check inline-svg` renders the result in WebKit.
///
/// Parsed with libxml2 (`SvgTree`), the library Chrome's XML parser is built on, never loading an
/// external entity. `scripts/inline-svg-golden.mjs` holds the output against
/// QuartzControl's own function in Chrome.
public enum InlineSvg {
  public struct Result: Equatable, Sendable {
    public var markup: String
    /// How many things were taken out (editor leftovers go without counting).
    public var removed: Int
    /// One of them was a `<style>`: Illustrator's "internal CSS" keeps every colour there, so
    /// without it the icon turns black, which the count alone does not say.
    public var styled: Bool
  }

  static let svgNS = "http://www.w3.org/2000/svg"
  static let xlinkNS = "http://www.w3.org/1999/xlink"

  static let elements: Set<String> = [
    "svg", "g", "defs", "symbol", "use", "title", "desc", "switch", "view", "a", "image",
    "path", "circle", "ellipse", "line", "polyline", "polygon", "rect", "text", "tspan", "textPath",
    "linearGradient", "radialGradient", "stop", "clipPath", "mask", "pattern", "marker",
    "filter", "feBlend", "feColorMatrix", "feComponentTransfer", "feComposite", "feConvolveMatrix",
    "feDiffuseLighting", "feDisplacementMap", "feDistantLight", "feDropShadow", "feFlood", "feFuncA",
    "feFuncB", "feFuncG", "feFuncR", "feGaussianBlur", "feImage", "feMerge", "feMergeNode",
    "feMorphology", "feOffset", "fePointLight", "feSpecularLighting", "feSpotLight", "feTile",
    "feTurbulence", "animate", "animateMotion", "animateTransform", "set", "mpath"
  ]
  static let animations: Set<String> = ["animate", "animateMotion", "animateTransform", "set"]

  /// ASCII lower case, as JavaScript's `i` flag compares ASCII letters.
  static func asciiLower(_ text: String) -> String {
    String(String.UnicodeScalarView(text.unicodeScalars.map { (0x41...0x5A).contains($0.value) ? Unicode.Scalar($0.value + 32)! : $0 }))
  }

  /// What vector editors leave behind; dropped without counting.
  static func isEditorNamespace(_ uri: String?) -> Bool {
    JSText.test(asciiLower(uri ?? ""), #"inkscape|sodipodi|adobe|sketch|figma|purl\.org/dc|creativecommons|rdf-syntax"#)
  }

  /// The URL parser drops tabs and newlines anywhere, and controls and spaces at the ends:
  /// dropping every such character sees at least what the browser will.
  static func compact(_ value: String) -> String { JSText.replaceAll(value, #"[\x{0}-\x{20}]"#, with: "") }

  static func safeHref(_ element: String, _ value: String) -> Bool {
    let v = compact(value)
    if JSText.startsWith(v, "#") { return true }
    let lower = asciiLower(v)
    if element == "a" { return JSText.test(lower, #"\A(https|mailto):"#) }
    if element == "image" { return JSText.test(lower, #"\Ahttps:"#) || JSText.test(lower, #"\Adata:image/(png|jpe?g|gif|webp|avif)[;,]"#) }
    return false
  }

  /// CSS reads `u\72 l(` as `url(`: a backslash and one to six hex digits with one optional space
  /// after them, or a backslash and any other character.
  static func cssUnescape(_ value: String) -> String {
    var out = ""
    var last = 0
    for match in JSText.matches(value, #"\\(?:([0-9a-fA-F]{1,6})[ \t\n\r\f]?|([^\n\r\f0-9a-fA-F]))"#) {
      out += JSText.slice(value, last, match.index)
      if let hex = match.groups[1] {
        let code = Int(hex, radix: 16) ?? 0
        out.unicodeScalars.append(Unicode.Scalar(UInt32(min(code == 0 ? 0xFFFD : code, 0x10FFFF))) ?? "\u{FFFD}")
      } else {
        out += match.groups[2] ?? ""
      }
      last = match.end
    }
    return out + JSText.slice(value, last)
  }

  /// Anything in a value that leaves the file: `url(https://…)`, an `@import`, `image-set("…")`.
  static func leavesFile(_ raw: String) -> Bool {
    let value = asciiLower(cssUnescape(raw))
    return JSText.test(value, #"url\(["# + JSText.space + #"]*(?!['"]?["# + JSText.space + #"]*#)"#)
      || JSText.test(value, #"image-set\(|image\(|cross-fade\(|(?<![A-Za-z0-9_])src\("#)
      || JSText.test(compact(value), #"@import|expression["# + JSText.space + #"]*\(|javascript:"#)
  }

  /// HTML writes attribute names in lower case and gives these SVG names their capitals back.
  static let camel: [String: String] = Dictionary(uniqueKeysWithValues: [
    "attributeName", "attributeType", "baseFrequency", "baseProfile", "calcMode", "clipPathUnits",
    "diffuseConstant", "edgeMode", "filterUnits", "glyphRef", "gradientTransform", "gradientUnits",
    "kernelMatrix", "kernelUnitLength", "keyPoints", "keySplines", "keyTimes", "lengthAdjust",
    "limitingConeAngle", "markerHeight", "markerUnits", "markerWidth", "maskContentUnits", "maskUnits",
    "numOctaves", "pathLength", "patternContentUnits", "patternTransform", "patternUnits", "pointsAtX",
    "pointsAtY", "pointsAtZ", "preserveAlpha", "preserveAspectRatio", "primitiveUnits", "refX", "refY",
    "repeatCount", "repeatDur", "requiredExtensions", "requiredFeatures", "specularConstant",
    "specularExponent", "spreadMethod", "startOffset", "stdDeviation", "stitchTiles", "surfaceScale",
    "systemLanguage", "tableValues", "targetX", "targetY", "textLength", "viewBox", "viewTarget",
    "xChannelSelector", "yChannelSelector", "zoomAndPan"
  ].map { ($0.lowercased(), $0) })

  static func htmlName(_ name: String) -> String {
    let lower = asciiLower(name)
    return camel[lower] ?? lower
  }

  /// FNV-1a over the text's UTF-16 units, as base 36, five characters.
  static func hash(_ text: String) -> String {
    var h: UInt32 = 0x811C9DC5
    for unit in text.utf16 { h = (h ^ UInt32(unit)) &* 0x0100_0193 }
    return String(String(h, radix: 36).prefix(5))
  }

  static let idLists: Set<String> = [
    "aria-labelledby", "aria-describedby", "aria-controls", "aria-owns", "aria-flowto", "aria-details",
    "aria-activedescendant", "aria-errormessage"
  ]

  static let urlReference = #"[uU][rR][lL]\(["# + JSText.space + #"]*(['"]?)((?:\\[0-9a-fA-F]{1,6}[ \t\n\r\f]?|\\[^\n\r\f0-9a-fA-F]|[^'")"# + JSText.space + #"\\])+)"#

  /// A reference read the way its reader reads it (`href` like the URL parser, `url()` like CSS,
  /// `anim.1.end` with the dot belonging to the id where the file defines one with it), rewritten
  /// only when it names one of the file's ids and, in CSS, only an id that needs no escaping.
  static func rewriteIds(_ attribute: String, _ value: String, _ ids: Set<String>, _ prefix: String) -> String {
    func own(_ id: String) -> String { ids.contains(id) ? prefix + id : id }
    if attribute == "id" { return own(value) }
    if attribute == "href" {
      let v = compact(value)
      return JSText.startsWith(v, "#") && ids.contains(JSText.slice(v, 1)) ? "#\(own(JSText.slice(v, 1)))" : value
    }
    if idLists.contains(attribute) {
      var out = "", last = 0
      for match in JSText.matches(value, "[\(JSText.space)]+") {
        out += own(JSText.slice(value, last, match.index)) + match.groups[0]!
        last = match.end
      }
      return out + own(JSText.slice(value, last))
    }
    if attribute == "begin" || attribute == "end" {
      var out = "", last = 0
      for match in JSText.matches(value, "(\\A|;)([\(JSText.space)]*)([^;\(JSText.space)]+)") {
        out += JSText.slice(value, last, match.index)
        let separator = match.groups[1] ?? "", space = match.groups[2] ?? "", token = match.groups[3]!
        let parts = JSText.split(token, ".")
        var replaced: String?
        for k in stride(from: parts.count - 1, through: 1, by: -1) {
          let id = parts[0..<k].joined(separator: ".")
          if ids.contains(id) { replaced = "\(separator)\(space)\(own(id)).\(parts[k...].joined(separator: "."))"; break }
        }
        out += replaced ?? match.groups[0]!
        last = match.end
      }
      return out + JSText.slice(value, last)
    }
    var out = "", last = 0
    for match in JSText.matches(value, urlReference) {
      out += JSText.slice(value, last, match.index)
      let quote = match.groups[1] ?? "", reference = cssUnescape(match.groups[2]!)
      if JSText.startsWith(reference, "#") {
        let id = JSText.slice(reference, 1)
        out += ids.contains(id) && JSText.test(id, #"\A[A-Za-z0-9_.:-]+\z"#) ? "url(\(quote)#\(own(id))" : match.groups[0]!
      } else {
        out += match.groups[0]!
      }
      last = match.end
    }
    return out + JSText.slice(value, last)
  }

  static func escape(_ text: String, _ pattern: String) -> String {
    var out = ""
    for unit in text.unicodeScalars {
      if unit.isASCII, JSText.test(String(unit), pattern) { out += "&#\(unit.value);" } else { out.unicodeScalars.append(unit) }
    }
    return out
  }

  /// Text with every character Markdown builds structure from as a numeric reference.
  static func escapeText(_ text: String) -> String { escape(text, #"[&<>\[\]()!*_`~\\|:#+=.@-]"#) }

  /// A value stays on the line of its tag.
  static func escapeAttribute(_ text: String) -> String { escape(text, "[&<>\"\\n\\r]") }

  public static func clean(_ text: String, fileName: String) -> Result? {
    guard let root = SvgTree.parse(text), root.localName == "svg", root.uri == svgNS else { return nil }
    let every = root.all
    if every.contains(where: { $0.qualifiedName == "parsererror" }) { return nil }

    let slug = JSText.replaceAll(JSText.replaceAll(JSText.replaceAll(fileName, #"\.[sS][vV][gG]\z"#, with: "").lowercased(), "[^a-z0-9]+", with: "-"), #"\A-+|-+\z"#, with: "")
    var removed = 0
    var styled = false
    var ids: Set<String> = []
    for element in every {
      if let id = element.attributes.first(where: { $0.localName == "id" && $0.uri == nil })?.value, !id.isEmpty { ids.insert(id) }
    }
    let prefix = "\(slug.isEmpty ? "svg" : slug)-\(hash(text))-"

    func write(_ node: SvgTree.Node) -> String {
      let element: SvgTree.Element
      switch node {
      case .text(let value): return escapeText(value)
      case .processingInstruction:
        removed += 1
        return ""
      case .comment: return ""
      case .element(let found): element = found
      }
      let name = element.localName
      if element.uri != svgNS || !elements.contains(name) {
        if name == "style" && element.uri == svgNS && !JS.trim(element.textContent).isEmpty { styled = true }
        if !(name == "metadata" && element.uri == svgNS) && !isEditorNamespace(element.uri) { removed += 1 }
        return ""
      }
      // The attributes as the site will see them: names the HTML way, the first of two that end up
      // with the same name. An own `href` wins over `xlink:href`, which is written as `href`.
      var seen: [(String, String)] = []
      var xlinkHref: String?
      for attribute in element.attributes {
        let namespace = attribute.uri
        let local = attribute.localName
        if namespace == xlinkNS && local == "href" {
          if xlinkHref == nil { xlinkHref = attribute.value }
          continue
        }
        if let namespace {
          if namespace != "http://www.w3.org/2000/xmlns/" && namespace != "http://www.w3.org/XML/1998/namespace" && !isEditorNamespace(namespace) { removed += 1 }
          continue
        }
        if !JSText.test(local, #"\A[A-Za-z][A-Za-z0-9_.-]*\z"#) {
          removed += 1
          continue
        }
        let html = htmlName(local)
        if seen.contains(where: { $0.0 == html }) {
          removed += 1
          continue
        }
        seen.append((html, attribute.value))
      }
      if let xlinkHref, !seen.contains(where: { $0.0 == "href" }) { seen.append(("href", xlinkHref)) }

      if animations.contains(name) {
        let target = asciiLower(JSText.replaceAll(compact(seen.first { $0.0 == "attributeName" }?.1 ?? ""), #"\A[^\n\r\x{2028}\x{2029}]*:"#, with: ""))
        if target == "href" || JSText.startsWith(target, "on") {
          removed += 1
          return ""
        }
      }

      var attributes: [String] = []
      var ownClass: String?
      for (attribute, value) in seen {
        if JSText.startsWith(attribute, "on") { removed += 1; continue }
        if attribute == "href" ? !safeHref(name, value) : leavesFile(value) { removed += 1; continue }
        if element === root && attribute == "class" { ownClass = value; continue }
        attributes.append("\(attribute)=\"\(escapeAttribute(rewriteIds(attribute, value, ids, prefix)))\"")
      }
      if element === root {
        let own = JS.trim(ownClass ?? "")
        let generated = slug.isEmpty ? "" : "svg-\(slug)"
        let ownParts = JSText.matches(own, "[^\(JSText.space)]+").map { $0.groups[0]! }
        let classes = [own, !generated.isEmpty && !ownParts.contains(generated) ? generated : ""].filter { !$0.isEmpty }.joined(separator: " ")
        attributes.insert(contentsOf: ["xmlns=\"\(svgNS)\""] + (classes.isEmpty ? [] : ["class=\"\(escapeAttribute(classes))\""]), at: 0)
      }
      let inner = element.children.map(write).joined()
      return "<\(name)\(attributes.isEmpty ? "" : " " + attributes.joined(separator: " "))>\(inner)</\(name)>"
    }

    let markup = JS.trim(JSText.replaceAll(write(.element(root)), "\\n[\(JSText.space)]*\\n", with: "\n"))
    return Result(markup: markup, removed: removed, styled: styled)
  }
}
