import Foundation

/// The SVG sanitizer against what the site makes of its result: the corpus and the questions of
/// QuartzControl's `check:inline-svg`, asked by `qh-check inline-svg` of WebKit (QuartzHub's own
/// web engine) instead of Chrome. Every result is put into a page as HTML, the way a layout box
/// renders it, and, with a project, through quartz-layout-box's Markdown chain in the three places
/// a pasted SVG can stand in a snippet. Then the page is asked: an element outside the SVG, an event
/// attribute, a link with a script scheme, an animation on a link, a `<style>`? Does anything run,
/// on load or after a click on every element of the box? Does anything load from outside?
///
/// Here only the corpus, the page and the JavaScript; the engine is the caller's (WebKit lives in
/// qh-check, not in the core).
public enum InlineSvgCheck {
  public struct Harmful: Sendable {
    public let name: String
    public let input: String
    /// Whether something must be counted as removed: a CDATA or a comment is written as text or left
    /// out, with nothing to count.
    public let counts: Bool
  }

  static let xhtml = "http://www.w3.org/1999/xhtml"
  static let run = "window.__ran=(window.__ran||0)+1"

  public static func svg(_ inner: String, _ attributes: String = "") -> String {
    "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" viewBox=\"0 0 24 24\"\(attributes)>\(inner)</svg>"
  }

  /// What must not get through: every line an input an earlier version let through or the block
  /// list did not name (QuartzControl's forty-second to forty-fourth reviews).
  public static let harmful: [Harmful] = {
    let r = run, x = xhtml
    let svgData = Data("<svg xmlns='http://www.w3.org/2000/svg' id='x'><image href='x' onerror='\(r)'/></svg>".utf8).base64EncodedString()
    let list: [(String, String, Bool)] = [
      ("<script>", svg("<script>\(r)</script><path d=\"M0 0\"/>"), true),
      ("XHTML-<img onerror>", svg("<img xmlns=\"\(x)\" src=\"x\" onerror=\"\(r)\"/>"), true),
      ("Processing Instruction mit <img onerror>", svg("<?x ><img src=x onerror=\"\(r)\">?><path d=\"M0 0\"/>"), true),
      ("Tab im Schema", svg("<a href=\"java&#9;script:\(r)\"><path d=\"M0 0h24v24H0z\"/></a>"), true),
      ("Zeilenumbrüche im Schema", svg("<a href=\"&#10;java&#13;script:\(r)\"><path d=\"M0 0h24v24H0z\"/></a>"), true),
      ("xlink:href mit javascript:", svg("<a xlink:href=\"javascript:\(r)\"><path d=\"M0 0h24v24H0z\"/></a>"), true),
      ("<set> auf href", svg("<a href=\"#\"><set attributeName=\"href\" to=\"javascript:\(r)\"/><path d=\"M0 0h24v24H0z\"/></a>"), true),
      ("<animate> auf HREF", svg("<a href=\"#\"><animate attributeName=\"HREF\" values=\"javascript:\(r)\"/><path d=\"M0 0h24v24H0z\"/></a>"), true),
      ("<set> auf xlink:href", svg("<a href=\"#\"><set attributeName=\"xlink:href\" to=\"javascript:\(r)\"/><path d=\"M0 0h24v24H0z\"/></a>"), true),
      ("XHTML-<meta refresh>", svg("<meta xmlns=\"\(x)\" http-equiv=\"refresh\" content=\"0;url=about:blank\"/>"), true),
      ("<style> für die ganze Seite", svg("<style>body{display:none}</style><path d=\"M0 0\"/>"), true),
      ("XHTML-<iframe>", svg("<iframe xmlns=\"\(x)\" src=\"javascript:\(r)\"/>"), true),
      ("<foreignObject>", svg("<foreignObject><div xmlns=\"\(x)\" onclick=\"\(r)\">x</div></foreignObject>"), true),
      ("CDATA mit Markup", svg("<text><![CDATA[</text><img src=x onerror=\"\(r)\">]]></text>"), false),
      ("Kommentar, den HTML früher beendet", svg("<!--><img src=x onerror=\"\(r)\">--><path d=\"M0 0\"/>"), false),
      ("SVG-<img>, das aus dem SVG ausbricht", svg("<img src=\"x\" onerror=\"\(r)\"/>"), true),
      ("onload an der Wurzel", svg("<path d=\"M0 0\"/>", " onload=\"\(r)\""), true),
      ("data:text/html im Verweis", svg("<a href=\"data:text/html,&lt;script>parent.\(r)&lt;/script>\"><path d=\"M0 0h24v24H0z\"/></a>"), true),
      ("<use> auf eine fremde Datei", svg("<use href=\"https://example.com/sprite.svg#a\"/>"), true),
      ("<image> mit SVG-Daten", svg("<image href=\"data:image/svg+xml,&lt;svg xmlns='http://www.w3.org/2000/svg' onload='\(r)'/>\"/>"), true),
      ("style-Attribut mit fremder url()", svg("<path style=\"fill:url(https://example.com/x)\" d=\"M0 0\"/>"), true),
      ("Element eines fremden Namensraums", svg("<x:script xmlns:x=\"http://www.w3.org/2000/svg\">\(r)</x:script>"), true),
      ("Markdown-Link mit javascript: im Text", svg("<text>[KLICK](javascript:\(r))</text>"), false),
      ("Markdown-Link in CDATA", svg("<text><![CDATA[[KLICK](javascript:\(r))]]></text>"), false),
      ("Markdown-Bild mit fremder Adresse im Text", svg("<text>![x](https://example.com/p.png)</text>"), false),
      ("Autolink im Text", svg("<text>&lt;javascript:\(r)&gt; www.example.com a@example.com</text>"), false),
      ("<use HREF> auf eine fremde Datei", svg("<use HREF=\"https://example.com/sprite.svg#a\"/>"), true),
      ("<feImage HREF> auf eine fremde Datei", svg("<filter id=\"f\"><feImage HREF=\"https://example.com/f.png\"/></filter><rect width=\"9\" height=\"9\" filter=\"url(#f)\"/>"), true),
      ("<image HREF> über http", svg("<image HREF=\"http://example.com/i.png\" width=\"9\" height=\"9\"/>"), true),
      ("<set ATTRIBUTENAME=\"href\"> nach außen", svg("<a href=\"#\"><set ATTRIBUTENAME=\"href\" to=\"https://example.com/phish\"/><rect width=\"24\" height=\"24\"/></a>"), true),
      ("<use HREF> mit SVG-Daten", svg("<use HREF=\"data:image/svg+xml;base64,\(svgData)#x\"/>"), true),
      ("CSS-Escape in url() im style", svg("<rect width=\"9\" height=\"9\" style=\"background-image:u\\72 l(https://example.com/b.png)\"/>"), true),
      ("image-set() im style", svg("<rect width=\"9\" height=\"9\" style=\"mask-image:image-set(&quot;https://example.com/m.png&quot; 1x)\"/>"), true),
      ("CSS-Escape in url() in fill", svg("<rect width=\"9\" height=\"9\" fill=\"u\\72 l(https://example.com/p.svg#p)\"/>"), true),
      ("href und HREF zugleich", svg("<use href=\"#s\" HREF=\"https://example.com/s.svg#a\"/>"), false),
      ("Zeilenanfang mit Markdown in einem Attribut", svg("<path aria-label=\"x&#10;# Titel&#10;- Punkt\" d=\"M0 0&#10;- 1 2\"/>"), false),
      ("Zeilenanfang mit Markdown im Text", svg("<text>x\n# Titel\n- Punkt\n1. Eins</text>"), false),
      ("Markdown-Link über Escapes im Text", svg("<text>\\[KLICK\\](javascript:\(r))</text>"), false)
    ]
    return list.map { Harmful(name: $0.0, input: $0.1, counts: $0.2) }
  }()

  /// The places a pasted SVG can stand in a snippet: as HTML in a box, and in Markdown as a block
  /// of its own, in a line with text, right under a line of text (where "Bild einfügen…" puts it).
  public static let markdownLayers: [(name: String, wrap: @Sendable (String) -> String)] = [
    ("Markdown, eigener Block", { "Text davor\n\n\($0)\n\nText danach\n" }),
    ("Markdown, in einer Zeile", { "Text davor \($0) danach\n" }),
    ("Markdown, unter einer Textzeile", { "Text davor\n\($0)\n" })
  ]

  public static func page(_ markup: String) -> String {
    "<!doctype html><title>s</title><body><div class=\"layout-box-content\">\(markup)</div></body>"
  }

  /// What stands in the box after the HTML parser: elements outside the SVG, event attributes,
  /// links that leave (http, https and mailto on an `<a>` are allowed, remark-gfm makes those out of
  /// "www.…" in any snippet), `url()` in a style, an animation on a link, anything outside the box.
  public static let findingsScript = """
    const box = document.querySelector('.layout-box-content')
    const out = []
    const svgNs = 'http://www.w3.org/2000/svg'
    for (const el of box ? box.querySelectorAll('*') : []) {
      const paragraph = el.localName === 'p' && el.parentElement === box
      if (el.namespaceURI !== svgNs && !paragraph) out.push(`<${el.localName}> außerhalb des SVG`)
      if (el.localName === 'style' || el.localName === 'script' || el.localName === 'foreignObject') out.push(`<${el.localName}>`)
      for (const a of el.attributes) {
        if (/^on/i.test(a.localName)) out.push(`${a.name} an <${el.localName}>`)
        if (a.localName === 'href' && !/^#/.test(a.value) && !/^data:image\\/(png|jpe?g|gif|webp|avif);/i.test(a.value) && !(el.localName === 'image' && /^https:/i.test(a.value)) && !(el.localName === 'a' && /^(https?|mailto):/i.test(a.value)))
          out.push(`${a.name}=${JSON.stringify(a.value.slice(0, 30))} an <${el.localName}>`)
        if (a.localName === 'style' && /url\\(\\s*['"]?(?!#)/i.test(a.value)) out.push(`style mit url() an <${el.localName}>`)
      }
      if (/^(set|animate|animateTransform|animateMotion)$/.test(el.localName) && /href/i.test(el.getAttribute('attributeName') ?? ''))
        out.push(`<${el.localName}> auf ${el.getAttribute('attributeName')}`)
    }
    if (document.querySelector('body > :not(.layout-box-content), head > meta, head > style')) out.push('Element außerhalb der Box')
    return out
    """

  /// The http(s) resources the page loaded on its own.
  public static let loadedScript = """
    return performance.getEntriesByType('resource').map((e) => e.name).filter((u) => /^https?:/.test(u))
    """

  /// The animations started; a link that now points elsewhere than its attribute says.
  public static let animatedScript = """
    for (const el of document.querySelectorAll('svg')) el.setCurrentTime?.(1)
    // A timer, not two animation frames: a WKWebView without a window draws no frames.
    await new Promise((r) => setTimeout(r, 50))
    for (const a of document.querySelectorAll('.layout-box-content a')) {
      const h = a.href
      if (h && typeof h === 'object' && h.animVal !== h.baseVal) return h.animVal
    }
    return null
    """

  /// A click on every element of the box. Links that leave are stopped by the navigation delegate.
  public static let clickScript = """
    for (const el of document.querySelectorAll('.layout-box-content *')) {
      try { el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true })) } catch {}
    }
    for (const a of document.querySelectorAll('.layout-box-content a')) { try { a.click?.() } catch {} }
    return true
    """

  public static let ranScript = "return window.__ran ?? 0"

  /// What a page said about one rendering of a result.
  public struct Rendering: Sendable {
    public var findings: [String]
    public var ranOnLoad: Int
    public var ranOnClick: Int
    public var navigated: Bool
    public var loaded: [String]
    public var animatedTo: String?

    public init(findings: [String], ranOnLoad: Int, ranOnClick: Int, navigated: Bool, loaded: [String], animatedTo: String?) {
      self.findings = findings
      self.ranOnLoad = ranOnLoad
      self.ranOnClick = ranOnClick
      self.navigated = navigated
      self.loaded = loaded
      self.animatedTo = animatedTo
    }

    /// The problems of this rendering, as sentences; empty is good.
    public var problems: [String] {
      var out = findings
      if ranOnLoad > 0 { out.append("Skript lief beim Laden") }
      if ranOnClick > 0 { out.append("Skript lief beim Klick") }
      if navigated { out.append("die Seite navigierte") }
      if let first = loaded.first { out.append("lädt von außen (\(first))") }
      if let animatedTo { out.append("ein Link führt nach \(animatedTo)") }
      return out
    }
  }

  // MARK: what must get through

  public static let ordinaryIcon = svg(
    "<defs><linearGradient id=\"g\"><stop offset=\"0\" stop-color=\"red\"/></linearGradient><symbol id=\"s\"><circle cx=\"5\" cy=\"5\" r=\"4\"/></symbol></defs>"
      + "<title>Logo &amp; Name</title><g class=\"a\" fill=\"url(#g)\" style=\"fill:url(#g);stroke:currentColor\"><path d=\"M0 0h24\"/><use href=\"#s\"/><use xlink:href=\"#s\"/></g>"
      + "<animate attributeName=\"opacity\" values=\"0;1\" dur=\"1s\"/><a href=\"https://example.com/\"><rect width=\"1\" height=\"1\"/></a>",
    " class=\"eigen\" width=\"24\" height=\"24\"")

  /// The page's answer about the ordinary icon: its class, viewBox, the uses' targets, text, the
  /// gradient, the animation, the link, no blank line.
  public static let ordinaryScript = """
    const root = document.querySelector('.layout-box-content > svg')
    return {
      cls: root?.getAttribute('class'),
      viewBox: root?.viewBox?.baseVal?.width,
      uses: [...document.querySelectorAll('use')].map((u) => document.getElementById((u.getAttribute('href') ?? '').slice(1))?.localName ?? 'nichts'),
      title: document.querySelectorAll('title')[1]?.textContent,
      gradient: document.getElementById((document.querySelector('g.a')?.getAttribute('fill') ?? '').replace(/^url\\(#|\\)$/g, ''))?.localName === 'linearGradient',
      style: document.querySelector('g.a')?.getAttribute('style'),
      animate: document.querySelector('animate')?.getAttribute('attributeName'),
      link: document.querySelector('.layout-box-content a')?.getAttribute('href'),
      blank: /\\n\\s*\\n/.test(document.querySelector('.layout-box-content').innerHTML)
    }
    """

  public static let illustrator = "<svg xmlns=\"http://www.w3.org/2000/svg\" id=\"Ebene_1\" viewBox=\"0 0 24 24\"><defs><style>.st0{fill:#E30613}.st1{fill:none;stroke:#1D1D1B;stroke-width:2}</style></defs><circle class=\"st0\" cx=\"12\" cy=\"12\" r=\"8\"/><line class=\"st1\" x1=\"0\" y1=\"0\" x2=\"24\" y2=\"24\"/></svg>"

  /// Two files with Figma's and Illustrator's ids on one page.
  public static func sameIds(_ colour: String) -> String {
    "<svg xmlns=\"http://www.w3.org/2000/svg\" id=\"Ebene_1\" viewBox=\"0 0 24 24\" aria-labelledby=\"t\"><title id=\"t\">\(colour)</title><defs><linearGradient id=\"g\"><stop stop-color=\"\(colour)\"/></linearGradient><clipPath id=\"clip0_1_2\"><rect width=\"24\" height=\"24\"/></clipPath><path id=\"p\" d=\"M0 0h9\"/></defs><g clip-path=\"url(#clip0_1_2)\" style=\"fill:url(#g)\"><rect width=\"24\" height=\"24\" fill=\"url(&quot;#g&quot;)\"/><use href=\"#p\"/><animate attributeName=\"opacity\" begin=\"p.click\" values=\"0;1\"/></g></svg>"
  }

  public static let idsScript = """
    const all = [...document.querySelectorAll('.layout-box-content [id]')].map((e) => e.id)
    const twice = all.filter((id, i) => all.indexOf(id) !== i)
    const foreign = []
    for (const svg of document.querySelectorAll('.layout-box-content > svg')) {
      for (const el of svg.querySelectorAll('*')) {
        for (const a of el.attributes) {
          const refs = [...a.value.matchAll(/url\\(\\s*['"]?#([^'")\\s]+)/g)].map((m) => m[1])
          if (a.localName === 'href' && a.value.startsWith('#')) refs.push(a.value.slice(1))
          if (a.localName === 'begin') refs.push(a.value.split('.')[0])
          if (a.localName === 'aria-labelledby') refs.push(...a.value.split(/\\s+/))
          for (const r of refs) if (!svg.contains(document.getElementById(r))) foreign.push(`${a.localName}→${r}`)
        }
      }
      for (const r of (svg.getAttribute('aria-labelledby') ?? '').split(/\\s+/).filter(Boolean)) if (!svg.contains(document.getElementById(r))) foreign.push(`aria-labelledby→${r}`)
    }
    return { twice, foreign }
    """

  /// Four spellings of a reference that once kept the old id.
  public static let spellings = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\"><defs><linearGradient id=\"g1\"><stop stop-color=\"red\"/></linearGradient><path id=\"s\" d=\"M0 0h9\"/></defs><g id=\"liste\" aria-activedescendant=\"eins\" aria-errormessage=\"fehler\"><title id=\"eins\">a</title><desc id=\"fehler\">b</desc></g><rect id=\"r\" width=\"9\" height=\"9\" style=\"fill:url(#g\\31)\"/><use id=\"u\" href=\" #s\"/><animate id=\"anim.1\" attributeName=\"opacity\" values=\"0;1\" dur=\"1s\"/><animate id=\"b\" attributeName=\"opacity\" begin=\"anim.1.end\" values=\"1;0\"/></svg>"

  public static let spellingsScript = """
    const svg = document.querySelector('svg')
    const by = (suffix) => [...svg.querySelectorAll('[id]')].find((e) => e.id.endsWith(`-${suffix}`))
    const there = (id) => !!id && svg.contains(document.getElementById(id))
    const g = by('liste')
    const fill = getComputedStyle(by('r')).fill.match(/url\\("?[^#"]*#([^")]+)"?\\)/)?.[1]
    const href = by('u').getAttribute('href').replace(/^[\\u0000- ]+/, '').slice(1)
    const begin = by('b').getAttribute('begin')
    return {
      'aria-activedescendant': there(g.getAttribute('aria-activedescendant')),
      'aria-errormessage': there(g.getAttribute('aria-errormessage')),
      'href mit Leerzeichen': there(href),
      'url() mit Escape': there(fill),
      'begin mit Punkt in der Id': there(begin.slice(0, begin.lastIndexOf('.')))
    }
    """
}
