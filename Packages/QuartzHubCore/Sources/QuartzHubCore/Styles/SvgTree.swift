import Darwin
import Foundation
import libxml2

/// A small read-only tree of an XML document as Chrome's DOMParser builds it for `image/svg+xml`,
/// read with libxml2 (the library Blink's XML parser is built on): text nodes as they stand,
/// whitespace included; attributes in source order with their namespace; CDATA as text; comments
/// and processing instructions as such.
///
/// Entities: an internal one is put in, as Chrome does (`&farbe;` → `red`); an external one is
/// never loaded and reads as nothing, as in Chrome. That is why the document is parsed without
/// `XML_PARSE_NOENT` (with it, libxml2 would read `SYSTEM "file:///…"` from disk) and the internal
/// entities are expanded here, from the declarations libxml2 parsed; the expansion has a ceiling,
/// so a "billion laughs" file ends at nil rather than at memory.
enum SvgTree {
  final class Element {
    let localName: String
    let qualifiedName: String
    let uri: String?
    let attributes: [(localName: String, uri: String?, value: String)]
    var children: [Node] = []

    init(localName: String, qualifiedName: String, uri: String?, attributes: [(localName: String, uri: String?, value: String)]) {
      self.localName = localName
      self.qualifiedName = qualifiedName
      self.uri = uri
      self.attributes = attributes
    }

    var textContent: String {
      children.map { node in
        switch node {
        case .text(let text): text
        case .element(let element): element.textContent
        default: ""
        }
      }.joined()
    }

    /// This element and every element below it, in document order.
    var all: [Element] {
      [self] + children.flatMap { node -> [Element] in
        if case .element(let element) = node { return element.all }
        return []
      }
    }
  }

  enum Node {
    case element(Element)
    case text(String)
    case processingInstruction
    case comment
  }

  /// Nodes made by expanding internal entities, at most; past it the file is refused.
  static let expansionCeiling = 200_000

  struct TooLarge: Error {}

  /// The root element, or nil when the text is not well-formed XML (Chrome's `<parsererror>`).
  static func parse(_ text: String) -> Element? {
    let options = Int32(XML_PARSE_NONET.rawValue | XML_PARSE_NOERROR.rawValue | XML_PARSE_NOWARNING.rawValue | XML_PARSE_NOCDATA.rawValue)
    let bytes = Array(text.utf8)
    guard let document = bytes.withUnsafeBufferPointer({ buffer in
      buffer.baseAddress.map { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: buffer.count) { xmlReadMemory($0, Int32(buffer.count), nil, "UTF-8", options) }
      } ?? nil
    }) else { return nil }
    defer { xmlFreeDoc(document) }
    guard let root = xmlDocGetRootElement(document) else { return nil }
    var budget = expansionCeiling
    return try? element(root, document, &budget)
  }

  static func string(_ pointer: UnsafePointer<xmlChar>?) -> String {
    pointer.map { String(cString: $0) } ?? ""
  }

  static func element(_ node: xmlNodePtr, _ document: xmlDocPtr, _ budget: inout Int) throws -> Element {
    let local = string(node.pointee.name)
    let prefix = node.pointee.ns.map { string($0.pointee.prefix) } ?? ""
    let uri = node.pointee.ns.map { string($0.pointee.href) }
    var attributes: [(String, String?, String)] = []
    var attribute = node.pointee.properties
    while let current = attribute {
      let value = xmlNodeListGetString(document, current.pointee.children, 1)
      attributes.append((string(current.pointee.name), current.pointee.ns.map { string($0.pointee.href) }, string(value)))
      // libxml2's xmlFree is plain free() on Apple's build; the variable itself is not
      // concurrency-safe to reference.
      free(value)
      attribute = current.pointee.next
    }
    let result = Element(localName: local, qualifiedName: prefix.isEmpty ? local : "\(prefix):\(local)", uri: uri, attributes: attributes)
    result.children = try nodes(node.pointee.children, document, &budget)
    return result
  }

  static func nodes(_ first: xmlNodePtr?, _ document: xmlDocPtr, _ budget: inout Int) throws -> [Node] {
    var out: [Node] = []
    var current = first
    while let node = current {
      switch node.pointee.type {
      case XML_ELEMENT_NODE: out.append(.element(try element(node, document, &budget)))
      case XML_TEXT_NODE, XML_CDATA_SECTION_NODE: out.append(.text(string(node.pointee.content)))
      case XML_PI_NODE: out.append(.processingInstruction)
      case XML_COMMENT_NODE: out.append(.comment)
      case XML_ENTITY_REF_NODE:
        // The reference's child is the declaration; an internal one carries its parsed content.
        if let entity = UnsafeMutableRawPointer(node.pointee.children)?.assumingMemoryBound(to: xmlEntity.self),
           entity.pointee.etype == XML_INTERNAL_GENERAL_ENTITY {
          budget -= 1
          if budget < 0 { throw TooLarge() }
          let expanded = try nodes(entity.pointee.children, document, &budget)
          budget -= expanded.count
          if budget < 0 { throw TooLarge() }
          out += expanded
        }
      default: break
      }
      current = node.pointee.next
    }
    return out
  }
}
