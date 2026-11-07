/**
 * Code that runs inside the export window, on a page of the user's built site. Every function here
 * is stringified and handed to `executeJavaScript`, so it closes over nothing - not this module,
 * not shared/ - and is written for the site's browser, not for Node (the same pattern as
 * previewHighlight.ts). What it needs from shared/exportModel.ts arrives as function source in its
 * arguments (`slugFromPathname`, `anchorFor`, `outsideUrl`), so the rule for naming a page exists
 * once.
 */

export type NavigationSource = 'explorer' | 'quartz-navigations' | 'links' | 'none'

/**
 * Waits until the page has done what the extraction needs: fonts loaded, every Mermaid block
 * rendered to an SVG, and - when asked - a navigation with links in it (Quartz's Explorer builds
 * its tree in a script after load). Not images: the extraction only takes their addresses, a
 * `loading="lazy"` picture never loads in a window nobody scrolls, and whether every picture
 * arrives is checked once, on the assembled document. Resolves with what was still missing when
 * the time ran out, so the caller can say so rather than print a half-rendered page.
 */
export function settlePage(opts: { navigation: boolean; timeoutMs: number }): Promise<{ unrenderedDiagrams: number; navigation: boolean }> {
  const started = Date.now()
  const navReady = (): boolean => !!document.querySelector('.explorer a[href], nav.quartz-nav a[href]')
  // Mermaid first puts an empty SVG into the block to measure text, and replaces it with the
  // diagram later; only the finished one carries `aria-roledescription`. Taking the first SVG as
  // done printed two diagrams of Example as empty 300×150 boxes and, in one run, lost the sequence
  // diagram altogether. A diagram also counts as finished only once its size has stopped changing.
  const diagrams = (): Element[] => [...document.querySelectorAll('article code.mermaid')]
  const pendingNow = (): number => diagrams().filter((c) => !c.querySelector('svg[aria-roledescription]')).length
  let lastShape = ''
  let stableTicks = 0
  const pendingDiagrams = (): number => {
    if (diagrams().length === 0) return 0
    const shape = diagrams().map((c) => c.querySelector('svg')?.querySelectorAll('*').length ?? -1).join(',')
    stableTicks = shape === lastShape ? stableTicks + 1 : 0
    lastShape = shape
    const pending = pendingNow()
    return pending > 0 || stableTicks < 3 ? Math.max(pending, 1) : 0
  }
  return document.fonts.ready.then(
    () =>
      new Promise((resolve) => {
        const tick = (): void => {
          const done = pendingDiagrams() === 0 && (!opts.navigation || navReady())
          if (done || Date.now() - started > opts.timeoutMs) {
            resolve({
              unrenderedDiagrams: pendingNow(),
              navigation: navReady()
            })
            return
          }
          setTimeout(tick, 50)
        }
        tick()
      })
  )
}

/**
 * The site's own order of pages, read from its navigation as built: Quartz's Explorer, or
 * quartz-navigations' `nav.quartz-nav`. Both sort differently and both can be configured beyond
 * what QuartzControl reads (Explorer's `sortFn` only in quartz.ts, quartz-navigations' `order`
 * map, `navOrder`, number prefixes), so the rendered tree is the one answer that is always right.
 * Neither present: the largest group of same-origin links outside the article, said as 'links'.
 * The first of several (a mobile copy of the same menu) wins. Links in document order, absolute,
 * same origin only; the caller turns them into slugs.
 */
export function readNavigation(): { source: NavigationSource; hrefs: string[] } {
  const own = (el: Element): string[] =>
    [...el.querySelectorAll('a[href]')]
      .map((a) => (a as HTMLAnchorElement).href)
      .filter((h) => {
        try {
          return new URL(h).origin === location.origin
        } catch {
          return false
        }
      })
  const explorer = document.querySelector('.explorer')
  if (explorer && own(explorer).length) return { source: 'explorer', hrefs: own(explorer) }
  const qnav = document.querySelector('nav.quartz-nav')
  if (qnav && own(qnav).length) return { source: 'quartz-navigations', hrefs: own(qnav) }
  let best: Element | null = null
  let bestCount = 0
  for (const el of document.querySelectorAll('nav, aside, .sidebar')) {
    if (el.closest('article')) continue
    const n = own(el).length
    if (n > bestCount) {
      best = el
      bestCount = n
    }
  }
  return best && bestCount >= 2 ? { source: 'links', hrefs: own(best) } : { source: 'none', hrefs: [] }
}

export interface ExtractArgs {
  slug: string
  /** The heading level of the page's title in the document. */
  level: number
  /** A folder's start page: its headings are signposts to the pages after it, not sections, and
   *  would sit between the page titles in the outline (the handbook script's rule). */
  signpost: boolean
  /** Every slug in the document. */
  inBook: string[]
  outsideLinks: 'site' | 'text'
  baseUrl?: string
  /** What replaces something a document cannot hold. With an address, `{{url}}` stands for the
   *  page (a form) or the source (a frame, a video); `noUrl` is said when there is none to give. */
  texts: { form: string; frame: string; media: string; canvas: string; noUrl: { form: string; frame: string; media: string; canvas: string } }
}

export interface ExtractedPage {
  slug: string
  title: string
  lang: string
  html: string
  images: string[]
  counts: { outsideLinks: number; textLinks: number; forms: number; frames: number; media: number; canvases: number; unrenderedDiagrams: number }
}

/**
 * The page's article, made to stand in one document with every other page: ids unique, links to
 * pages in the book turned into anchors, links out of it to the published site or to text, and
 * what a document cannot hold (a form, an embedded frame, a video, a button) replaced by a sentence
 * with the address or removed. Generalised from `extractPage` in scripts/build-handbook-pdf.mjs.
 */
export function extractArticle(
  args: ExtractArgs,
  slugFromPathname: (p: string) => string,
  anchorFor: (slug: string, id?: string) => string,
  outsideUrl: (baseUrl: string | undefined, slug: string, hash: string) => string | null
): ExtractedPage {
  // A .base page of bases-page has no <article>; its views are the page.
  const source = document.querySelector('article') ?? document.querySelector('.bases-page')
  if (!source) throw new Error(`no <article> on ${args.slug}`)
  const title = document.querySelector('h1.article-title')?.textContent?.trim() || document.title || args.slug
  const art = source.cloneNode(true) as HTMLElement
  const inBook = new Set(args.inBook)
  const counts = { outsideLinks: 0, textLinks: 0, forms: 0, frames: 0, media: 0, canvases: 0, unrenderedDiagrams: 0 }
  const say = (kind: 'form' | 'frame' | 'media' | 'canvas', url: string): string => (url ? args.texts[kind].replace('{{url}}', url) : args.texts.noUrl[kind])
  const note = (text: string, url: string): HTMLElement => {
    const p = document.createElement('p')
    p.className = 'qc-replaced'
    const at = text.indexOf(url)
    if (at === -1 || !/^https?:/.test(url)) {
      p.textContent = text
      return p
    }
    p.append(text.slice(0, at))
    const a = document.createElement('a')
    a.href = url
    a.textContent = url
    p.append(a, text.slice(at + url.length))
    return p
  }
  const pageUrl = outsideUrl(args.baseUrl, args.slug, '') ?? ''
  // An address a reader of the document can open: a file of the site itself on the published site
  // (the export window's own origin is a port on this machine that is gone after the run), anything
  // else as it is, and nothing for what is neither http(s).
  const publicUrl = (src: string): string => {
    if (!src) return ''
    let u: URL
    try {
      u = new URL(src, location.href)
    } catch {
      return ''
    }
    if (u.origin === location.origin) return outsideUrl(args.baseUrl, slugFromPathname(u.pathname), u.hash) ?? ''
    return /^https?:$/.test(u.protocol) ? u.href : ''
  }

  // Rendered diagrams become a figure with their SVG; the buttons Quartz puts around them go below.
  // Mermaid measured its labels in the font of the code block it sat in; in the document the SVG
  // inherits another one, and the labels were cut off ("Alle zwölf" of "Alle zwölf Bausteine?").
  // So the font each text element had while it was measured is written onto it.
  const liveCodes = source.querySelectorAll('code.mermaid')
  art.querySelectorAll('code.mermaid').forEach((code, i) => {
    const live = liveCodes[i]?.querySelector('svg[aria-roledescription]')
    const copy = code.querySelector('svg[aria-roledescription]')
    if (!live || !copy) return
    const liveEls = [live, ...live.querySelectorAll('*')]
    const copyEls = [copy, ...copy.querySelectorAll('*')]
    liveEls.forEach((el, k) => {
      const target = copyEls[k] as HTMLElement | SVGElement | undefined
      if (!target || !('style' in target)) return
      const cs = getComputedStyle(el)
      for (const prop of ['font-family', 'font-size', 'font-weight', 'font-style', 'line-height', 'letter-spacing']) {
        target.style.setProperty(prop, cs.getPropertyValue(prop))
      }
    })
  })
  art.querySelectorAll('code.mermaid').forEach((code) => {
    const svg = code.querySelector('svg[aria-roledescription]')
    const holder = code.closest('pre') ?? code
    if (!svg) {
      counts.unrenderedDiagrams++
      return
    }
    const fig = document.createElement('figure')
    fig.className = 'qc-diagram'
    fig.append(svg.cloneNode(true))
    holder.replaceWith(fig)
  })
  // Views of other plugins, measured on Example (2026-11-05): an Excalidraw drawing is an SVG and
  // stays one; a canvas is a pannable board of positioned cards that has no layout on paper, so it
  // becomes a sentence with its address; of a base's views, the one the page opens with is kept and
  // the tabs to the others go.
  art.querySelectorAll('.excalidraw-container').forEach((box) => {
    const svg = box.querySelector('svg')
    if (!svg) return
    const fig = document.createElement('figure')
    fig.className = 'qc-diagram'
    fig.append(svg.cloneNode(true))
    box.replaceWith(fig)
  })
  art.querySelectorAll('.excalidraw-controls, .excalidraw-overlays, .bases-view-tabs, .bases-view:not(.is-active), .canvas-controls').forEach((e) => e.remove())
  art.querySelectorAll('.canvas-container').forEach((c) => {
    counts.canvases++
    c.replaceWith(note(say('canvas', pageUrl), pageUrl))
  })
  // Not the <style> inside an SVG: Mermaid styles its diagram there, and without it every shape
  // printed as a black area (measured on Example's flowchart, 2026-11-05).
  // link, meta and base as well: raw HTML in a note may carry them, and a stylesheet from elsewhere
  // made the offline HTML load from the network (review of 2026-11-06, N1).
  art.querySelectorAll('[hidden], a[role="anchor"], .multilanguage-notice, script, style, noscript, template, dialog, button, link, meta, base').forEach((e) => {
    if (e.tagName.toLowerCase() === 'style' && e.closest('svg')) return
    e.remove()
  })
  art.querySelectorAll('form').forEach((f) => {
    counts.forms++
    f.replaceWith(note(say('form', pageUrl), pageUrl))
  })
  art.querySelectorAll('iframe, embed, object').forEach((f) => {
    counts.frames++
    const src = f.getAttribute('src') ?? f.getAttribute('data') ?? ''
    const url = publicUrl(src)
    f.replaceWith(note(say('frame', url), url))
  })
  art.querySelectorAll('video, audio').forEach((m) => {
    counts.media++
    const src = m.getAttribute('src') ?? m.querySelector('source')?.getAttribute('src') ?? ''
    const url = publicUrl(src)
    m.replaceWith(note(say('media', url), url))
  })

  // The page's headings hang below its title (h<level>), counted from the page's own top level:
  // a note that starts with "##" - Obsidian's usual, the title being the h1 - got h<level+2> and a
  // gap under every title, in the tagged PDF, the ePub and the HTML (review of 2026-11-06, N4:
  // 119 jumps in Example, 47 in the handbook; the handbook script had the same formula).
  const headings = [...art.querySelectorAll('h1,h2,h3,h4,h5,h6')]
  const top = Math.min(6, ...headings.map((h) => Number(h.tagName[1])))
  headings.forEach((h) => {
    const n = document.createElement(args.signpost ? 'p' : 'h' + Math.min(6, args.level + 1 + Number(h.tagName[1]) - top))
    if (args.signpost) n.className = 'index-heading'
    n.innerHTML = h.innerHTML
    if (h.id) n.id = anchorFor(args.slug, h.id)
    h.replaceWith(n)
  })
  // An SVG refers to its own ids - Mermaid's <style> by `#mermaid-0 .node`, markers and gradients
  // by `url(#…)`, `href="#…"`. Its ids are renamed together with every reference to them, per SVG,
  // so two diagrams that both call their root `mermaid-0` stay apart in one document.
  art.querySelectorAll('svg').forEach((svg, n) => {
    if (svg.parentElement?.closest('svg')) return
    const renamed = new Map<string, string>()
    for (const el of [svg, ...svg.querySelectorAll('[id]')]) {
      if (!el.id) continue
      const id = anchorFor(args.slug, `svg${n}-${el.id}`)
      renamed.set(el.id, id)
      el.id = id
    }
    if (!renamed.size) return
    // Without `.` in the name: in CSS it starts a class (`#mermaid-0.flowchart` is the id plus a class).
    const rewrite = (text: string): string => text.replace(/#([A-Za-z_][\w-]*)/g, (whole, id: string) => (renamed.has(id) ? '#' + renamed.get(id) : whole))
    for (const el of [svg, ...svg.querySelectorAll('*')]) {
      for (const attr of [...el.attributes]) {
        if (attr.name === 'aria-labelledby' || attr.name === 'aria-describedby') attr.value = attr.value.split(/\s+/).map((t) => renamed.get(t) ?? t).join(' ')
        else if (attr.name !== 'id' && attr.value.includes('#')) attr.value = rewrite(attr.value)
      }
    }
    svg.querySelectorAll('style').forEach((st) => (st.textContent = rewrite(st.textContent ?? '')))
  })
  art.querySelectorAll('[id]:not(h1,h2,h3,h4,h5,h6,p.index-heading)').forEach((e) => {
    if (!e.closest('svg')) e.id = anchorFor(args.slug, e.id)
  })

  const images: string[] = []
  art.querySelectorAll('img').forEach((img) => {
    img.setAttribute('src', img.src)
    img.removeAttribute('srcset')
    img.removeAttribute('loading')
    images.push(img.src)
  })

  art.querySelectorAll('a[href]').forEach((a) => {
    const raw = a.getAttribute('href') ?? ''
    let url: URL
    try {
      url = new URL(raw, location.href)
    } catch {
      return
    }
    if (url.origin !== location.origin) {
      if (/^(https?|mailto|tel):$/.test(url.protocol)) return void a.setAttribute('href', url.href)
      // javascript:, data:, file: and the like lead nowhere a reader should go; a javascript: link
      // in the offline HTML ran its script on a click (N1). The words stay.
      const span = document.createElement('span')
      span.append(...a.childNodes)
      a.replaceWith(span)
      return
    }
    const target = slugFromPathname(url.pathname)
    let hash = url.hash.slice(1)
    try {
      hash = decodeURIComponent(hash)
    } catch {
      // keep it encoded
    }
    if (inBook.has(target)) {
      a.setAttribute('href', '#' + anchorFor(target, hash || undefined))
      return
    }
    const out = args.outsideLinks === 'site' ? outsideUrl(args.baseUrl, target, url.hash) : null
    if (out) {
      counts.outsideLinks++
      a.setAttribute('href', out)
      a.classList.add('qc-outside')
      return
    }
    counts.textLinks++
    const span = document.createElement('span')
    span.className = 'qc-unlinked'
    span.append(...a.childNodes)
    a.replaceWith(span)
  })

  return { slug: args.slug, title, lang: document.documentElement.lang, html: art.innerHTML, images, counts }
}

export interface DocumentProblems {
  /** `<page title>: <tag> <px> px` for content that runs past the printable width. */
  overflow: string[]
  /** In-document links whose anchor does not exist. */
  deadLinks: string[]
  /** Pictures that did not load. */
  brokenImages: string[]
  counted: { links: number; images: number }
}

/**
 * Checks the assembled document at print width for what one cannot see in a finished PDF any
 * more: content past the right edge, links without a target, pictures that did not load. From the
 * handbook script's `findProblems`, with one difference measured on Example (2026-11-05): an
 * element is only a problem where it is *visible* past the edge. KaTeX draws stretchy symbols as
 * 400em-wide SVG paths inside a box with `overflow: hidden`; the old check reported them at
 * 6500 px. A clipping ancestor (`hidden`/`clip`) now limits what counts, and of an overflowing
 * subtree only the outermost element is named.
 */
export function findDocumentProblems(): DocumentProblems {
  const width = document.body.clientWidth
  const where = (el: Element): string =>
    el.closest('.doc-page')?.querySelector('.page-title')?.textContent ?? (el.closest('.qc-toc') ? 'toc' : '?')
  const visibleRight = (el: Element, right: number): number => {
    for (let a = el.parentElement; a && a !== document.body; a = a.parentElement) {
      const o = getComputedStyle(a)
      if (/(hidden|clip)/.test(o.overflowX) || /(hidden|clip)/.test(o.overflow)) right = Math.min(right, a.getBoundingClientRect().right)
    }
    return right
  }
  const over = new Set<Element>()
  const overflow: string[] = []
  // An inline element counts with what it holds, not with its padding: Quartz pads links
  // (0.1rem each side) to give them a background, and a line may end in that padding. gui-test's
  // footnote back-link "↩³" reached 1.16 px past the edge with its padding and ended 0.4 px inside
  // it without (review of 2026-11-06, M4); every export of that site stopped at it.
  // Pictures, SVG, formulas and form fields hold nothing a range could measure; they count whole.
  const range = document.createRange()
  const replaced = /^(IMG|VIDEO|AUDIO|CANVAS|IFRAME|OBJECT|EMBED|INPUT|SELECT|TEXTAREA)$/
  const box = (el: Element): DOMRect => {
    if (!(el instanceof HTMLElement) || replaced.test(el.tagName) || getComputedStyle(el).display !== 'inline') return el.getBoundingClientRect()
    range.selectNodeContents(el)
    return range.getBoundingClientRect()
  }
  for (const el of document.querySelectorAll('body *')) {
    if (el.closest('.cover')) continue
    const r = box(el)
    if (!r.width) continue
    const right = visibleRight(el, r.right)
    if (right <= width + 1) continue
    over.add(el)
    if (el.parentElement && over.has(el.parentElement)) continue
    overflow.push(`${where(el)}: <${el.tagName.toLowerCase()}> ${Math.round(right - width)} px`)
  }
  const ids = new Set([...document.querySelectorAll('[id]')].map((e) => e.id))
  const internal = [...document.querySelectorAll('a[href^="#"]')]
  const deadLinks = internal.filter((a) => !ids.has(a.getAttribute('href')!.slice(1))).map((a) => `${where(a)}: ${a.getAttribute('href')}`)
  const brokenImages = [...document.images].filter((i) => !i.complete || i.naturalWidth === 0).map((i) => `${where(i)}: ${i.getAttribute('src')}`)
  return { overflow, deadLinks, brokenImages, counted: { links: internal.length, images: document.images.length } }
}

/** Waits until every picture of the assembled document has loaded or failed. */
export function imagesSettled(timeoutMs: number): Promise<number> {
  const pending = [...document.images].filter((i) => !i.complete)
  return Promise.race([
    Promise.all(pending.map((i) => new Promise((r) => { i.addEventListener('load', r, { once: true }); i.addEventListener('error', r, { once: true }) }))).then(() => 0),
    new Promise<number>((r) => setTimeout(() => r(pending.filter((i) => !i.complete).length), timeoutMs))
  ]).then(() => document.fonts.ready).then(() => [...document.images].filter((i) => !i.complete).length)
}

/** Writes the page numbers the first pass found into the table of contents. */
export function fillPageNumbers(numbers: Record<string, number>): number {
  let filled = 0
  // The contents and the register alike.
  for (const n of document.querySelectorAll<HTMLElement>('.n[data-anchor]')) {
    const page = numbers[n.dataset.anchor!]
    if (page === undefined) continue
    n.textContent = String(page)
    filled++
  }
  return filled
}

export interface EpubChapterInput {
  file: string
  /** The page anchor and title heading; absent for an interposed heading. */
  slug?: string
  anchor: string
  level: number
  title: string
  html: string
}

export interface EpubChapterOutput {
  file: string
  /** The body, serialised as XHTML (well-formed XML in the XHTML namespace). */
  body: string
  hasMath: boolean
  hasSvg: boolean
  /** Pictures of the site, by address, and the name they get in the book. */
  images: { url: string; name: string }[]
  /** Not well-formed after serialisation (DOMParser's own message). */
  parseError: string | null
}

export interface EpubChaptersResult {
  chapters: EpubChapterOutput[]
  /**
   * What the caller draws as pictures, with the picture's name: formulas without MathML (their
   * KaTeX HTML) and diagrams (their SVG).
   */
  drawings: Drawing[]
  counts: { externalImages: number; unsupportedImages: number; unresolvedLinks: number; footnotes: number; formulas: number; diagrams: number }
}

export interface Drawing {
  name: string
  html: string
  kind: 'formula' | 'diagram'
  /** A formula set as its own block; a diagram is always one. */
  display: boolean
}

/**
 * The collected pages as ePub chapters, one XHTML file each. Runs in the export window, so the
 * browser's own parser and XMLSerializer do the HTML → XHTML step - no second HTML parser in the
 * main process that could read a page differently.
 *
 *  - Formulas: KaTeX writes MathML next to its HTML rendering; ePub 3 reads MathML, and the HTML
 *    half needs KaTeX's stylesheet, which a reader does not have. The MathML stays, the rest goes.
 *  - Pictures of the site get a name in the book; a picture from elsewhere cannot travel in an
 *    ePub (remote resources are allowed for audio, video and fonts only) and becomes a link.
 *  - In-document links point at the file that holds their anchor.
 *  - Footnotes become what readers show as pop-ups: `epub:type="noteref"` on the reference and
 *    each note an `<aside epub:type="footnote">`.
 *  - Diagrams become pictures (see below).
 */
export function epubChapters(input: {
  chapters: EpubChapterInput[]
  imageNames: Record<string, string>
  imageExtensions: string[]
  formulaAlt: string
  diagramAlt: string
}): EpubChaptersResult {
  const XHTML = 'http://www.w3.org/1999/xhtml'
  const counts = { externalImages: 0, unsupportedImages: 0, unresolvedLinks: 0, footnotes: 0, formulas: 0, diagrams: 0 }
  const imageNames = new Map(Object.entries(input.imageNames))
  const drawings: Drawing[] = []
  const picture = (name: string, alt: string, className: string): HTMLImageElement => {
    const img = document.createElement('img')
    img.setAttribute('src', `../${name}`)
    img.setAttribute('alt', alt)
    img.setAttribute('class', className)
    img.setAttribute('data-qc-drawing', name)
    return img
  }
  let nextImage = imageNames.size
  const containers = input.chapters.map((c) => {
    const div = document.createElement('div')
    if (c.slug) {
      const h = document.createElement(`h${Math.min(6, Math.max(1, c.level))}`)
      h.id = c.anchor
      h.textContent = c.title
      div.append(h)
      const rest = document.createElement('div')
      rest.innerHTML = c.html
      div.append(...rest.childNodes)
    } else {
      const h = document.createElement('h1')
      h.id = c.anchor
      h.textContent = c.title
      div.append(h)
    }
    return div
  })
  // Which file holds which id - after the containers exist, before any link is rewritten.
  const fileOf = new Map<string, string>()
  containers.forEach((div, i) => div.querySelectorAll('[id]').forEach((e) => fileOf.set(e.id, input.chapters[i].file)))

  const chapters = containers.map((div, i): EpubChapterOutput => {
    const file = input.chapters[i].file
    const images: { url: string; name: string }[] = []

    div.querySelectorAll('.katex-display, .katex').forEach((k) => {
      // A .katex inside a .katex-display went with its parent. Not isConnected: the container
      // is never in the document, so that is false for every element in it.
      if (!div.contains(k)) return
      const math = k.querySelector('math')
      counts.formulas++
      if (!math) {
        // Quartz 5 renders KaTeX as HTML only (measured on Example: katex-html, no katex-mathml),
        // and that HTML needs KaTeX's stylesheet and fonts, which a reader does not have. The
        // formula is drawn as a picture by the caller; its TeX source is not in the build, so the
        // alternative text can only say what it is.
        const display = k.classList.contains('katex-display')
        const name = `images/f${String(counts.formulas).padStart(4, '0')}.png`
        drawings.push({ name, html: k.outerHTML, kind: 'formula', display })
        const img = picture(name, input.formulaAlt, display ? 'qc-formula qc-formula-display' : 'qc-formula')
        if (display) {
          const p = document.createElement('p')
          p.className = 'qc-formula-block'
          p.append(img)
          k.replaceWith(p)
        } else k.replaceWith(img)
        return
      }
      const copy = math.cloneNode(true) as Element
      if (k.classList.contains('katex-display')) copy.setAttribute('display', 'block')
      k.replaceWith(copy)
    })

    // Diagrams (Mermaid, Excalidraw) are drawn as pictures as well. Measured in Apple Books
    // (2026-11-05): the reader sets its own font on the HTML labels inside a Mermaid SVG, which
    // Mermaid had sized for the site's font, so "Rechteck" and "Datenbank" were cut off; its dark
    // theme coloured the labels white on Mermaid's white boxes, and Excalidraw's black arrows
    // vanished on the black page. Safari showed the same chapter correctly - it is the reader's
    // styling, which reaches into an SVG in the page but not into a picture.
    div.querySelectorAll('figure.qc-diagram > svg').forEach((svg) => {
      counts.diagrams++
      const name = `images/d${String(counts.diagrams).padStart(4, '0')}.png`
      drawings.push({ name, html: svg.outerHTML, kind: 'diagram', display: true })
      const title = svg.querySelector(':scope > title')?.textContent?.trim()
      svg.replaceWith(picture(name, title || input.diagramAlt, 'qc-diagram-picture'))
    })

    // The arrow Quartz puts after an external link is decoration (aria-hidden), sized by the
    // site's stylesheet. Apple Books ignored its max-width and gave it half a page of height after
    // every external link (measured on the handbook, 2026-11-05).
    div.querySelectorAll('svg.external-icon').forEach((svg) => svg.remove())

    // Addresses from raw HTML that the ePub cannot carry and the offline HTML would fetch (N1): an
    // url() in a style attribute and an SVG <image> from elsewhere. Only data: and #ids stay.
    div.querySelectorAll('[style]').forEach((el) => {
      const st = (el as HTMLElement).style
      for (let k = st.length - 1; k >= 0; k--) {
        if (/url\(\s*["']?(?!data:|#)/i.test(st.getPropertyValue(st[k]))) st.removeProperty(st[k])
      }
      if (!st.length) el.removeAttribute('style')
    })
    div.querySelectorAll('svg image').forEach((image) => {
      const href = image.getAttribute('href') ?? image.getAttributeNS('http://www.w3.org/1999/xlink', 'href') ?? ''
      if (!href.startsWith('data:')) image.remove()
    })

    div.querySelectorAll('img:not([data-qc-drawing])').forEach((img) => {
      let url: URL
      try {
        url = new URL(img.getAttribute('src') ?? '', location.href)
      } catch {
        img.remove()
        return
      }
      // A picture written into the page (data:) travels as a file of the book like the site's own;
      // as a link it was a reference epubcheck refuses (RSC-029) and a picture nobody sees (N1).
      if (url.protocol === 'data:') {
        const mime = /^data:([^;,]+)/.exec(url.href)?.[1]?.toLowerCase() ?? ''
        const ext = ({ 'image/png': 'png', 'image/jpeg': 'jpg', 'image/gif': 'gif', 'image/svg+xml': 'svg', 'image/webp': 'webp' } as Record<string, string>)[mime]
        if (!ext || !input.imageExtensions.includes(ext)) {
          counts.unsupportedImages++
          const span = document.createElement('span')
          span.className = 'qc-replaced'
          span.textContent = img.getAttribute('alt') || ''
          img.replaceWith(span)
          return
        }
        let name = imageNames.get(url.href)
        if (!name) {
          name = `images/i${String(++nextImage).padStart(4, '0')}.${ext}`
          imageNames.set(url.href, name)
        }
        images.push({ url: url.href, name })
        img.setAttribute('src', `../${name}`)
        if (!img.hasAttribute('alt')) img.setAttribute('alt', '')
        return
      }
      if (url.origin !== location.origin) {
        counts.externalImages++
        const a = document.createElement('a')
        a.href = url.href
        a.textContent = img.getAttribute('alt') || url.href
        img.replaceWith(a)
        return
      }
      const key = url.origin + url.pathname
      const ext = (url.pathname.match(/\.([A-Za-z0-9]+)$/)?.[1] ?? '').toLowerCase()
      // A format the ePub standard does not list (AVIF, BMP, TIFF) would not show in a reader.
      if (!input.imageExtensions.includes(ext)) {
        counts.unsupportedImages++
        const span = document.createElement('span')
        span.className = 'qc-replaced'
        span.textContent = img.getAttribute('alt') || decodeURIComponent(url.pathname.split('/').pop() ?? '')
        img.replaceWith(span)
        return
      }
      let name = imageNames.get(key)
      if (!name) {
        name = `images/i${String(++nextImage).padStart(4, '0')}.${ext}`
        imageNames.set(key, name)
      }
      images.push({ url: key, name })
      img.setAttribute('src', `../${name}`)
      if (!img.hasAttribute('alt')) img.setAttribute('alt', '')
      for (const attr of ['loading', 'decoding', 'srcset', 'sizes', 'fetchpriority']) img.removeAttribute(attr)
    })

    div.querySelectorAll('a[href^="#"]').forEach((a) => {
      const id = a.getAttribute('href')!.slice(1)
      const target = fileOf.get(id)
      if (!target) {
        counts.unresolvedLinks++
        const span = document.createElement('span')
        span.append(...a.childNodes)
        a.replaceWith(span)
        return
      }
      a.setAttribute('href', target === file ? `#${id}` : `${target.split('/').pop()}#${id}`)
    })

    div.querySelectorAll('a[data-footnote-ref]').forEach((a) => a.setAttribute('epub:type', 'noteref'))
    div.querySelectorAll('section.footnotes, section[data-footnotes]').forEach((section) => {
      const notes = [...section.querySelectorAll('li[id]')]
      const out = document.createElement('section')
      out.className = 'footnotes'
      for (const li of notes) {
        counts.footnotes++
        const aside = document.createElement('aside')
        aside.setAttribute('epub:type', 'footnote')
        aside.id = li.id
        aside.append(...li.childNodes)
        out.append(aside)
      }
      section.replaceWith(out)
    })

    // What epubcheck 5.4.0 refused in the handbook and Example (2026-11-05), one rule each:
    //  - an <img> width/height that is not an integer ("auto", "100%") moves into the style;
    div.querySelectorAll('img').forEach((img) => {
      for (const dim of ['width', 'height']) {
        const v = img.getAttribute(dim)
        if (v !== null && !/^\d+$/.test(v)) {
          img.removeAttribute(dim)
          if (v !== 'auto') (img as HTMLElement).style.setProperty(dim, v)
        }
      }
    })
    //  - a <p> inside phrasing content (Mermaid's labels: <span class="nodeLabel"><p>…) is
    //    allowed by the HTML parser, not by XHTML; it becomes a block span;
    div.querySelectorAll('p').forEach((p) => {
      if (!p.parentElement || !/^(span|a|em|strong|b|i|label|code|small|sub|sup|u|s|q|cite|mark)$/i.test(p.parentElement.tagName)) return
      const span = document.createElement('span')
      span.style.display = 'block'
      for (const attr of [...p.attributes]) span.setAttribute(attr.name, attr.value)
      span.append(...p.childNodes)
      p.replaceWith(span)
    })
    //  - an id twice in one file (Mermaid's timeline names nodes `node-undefined`) keeps its first
    //    holder; the others get a counter;
    const seenIds = new Set<string>()
    div.querySelectorAll('[id]').forEach((el) => {
      if (!seenIds.has(el.id)) return void seenIds.add(el.id)
      let k = 2
      while (seenIds.has(`${el.id}-${k}`)) k++
      el.id = `${el.id}-${k}`
      seenIds.add(el.id)
    })
    //  - aria-labelledby/-describedby naming an element that is not there (Mermaid points at a
    //    description it did not write) loses that name, and the attribute when none is left;
    div.querySelectorAll('[aria-describedby], [aria-labelledby]').forEach((el) => {
      for (const attr of ['aria-describedby', 'aria-labelledby']) {
        const v = el.getAttribute(attr)
        if (v === null) continue
        const kept = v.split(/\s+/).filter((id) => id && seenIds.has(id))
        if (kept.length) el.setAttribute(attr, kept.join(' '))
        else el.removeAttribute(attr)
      }
    })
    //  - a font an SVG loads from elsewhere (Excalidraw's Virgil from unpkg) is a remote resource,
    //    which a reader offline cannot fetch either; the rule goes and the drawing falls back.
    div.querySelectorAll('svg style').forEach((st) => {
      st.textContent = (st.textContent ?? '').replace(/@font-face\s*\{[^}]*url\(\s*["']?https?:[^}]*\}/g, '')
    })
    //  - an element HTML does not know is a word in angle brackets the author meant as text
    //    ("the of <selector> syntax", "SVG <use> and the Shadow DOM" in gui-test, review of
    //    2026-11-06, M3): the browser makes an element of it and shows what it holds, the schema
    //    refuses it. It becomes a span with what it holds, like the site shows it. The names are
    //    the ones epubcheck 5.4.0 lists as allowed in flow and phrasing content.
    const KNOWN = new Set(
      ('a abbr address area article aside audio b bdi bdo blockquote br canvas caption cite code col colgroup data ' +
        'datalist dd del details dfn dialog div dl dt em embed fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 ' +
        'header hgroup hr i iframe img input ins kbd label legend li main map mark menu meter nav object ol optgroup ' +
        'option output p picture pre progress q rp rt ruby s samp search section select small source span strong sub ' +
        'summary sup table tbody td template textarea tfoot th thead time tr track u ul var video wbr').split(' ')
    )
    div.querySelectorAll('*').forEach((el) => {
      if (el.namespaceURI !== XHTML || KNOWN.has(el.localName)) return
      const span = document.createElement('span')
      for (const name of ['id', 'class', 'lang', 'title']) {
        const v = el.getAttribute(name)
        if (v !== null) span.setAttribute(name, v)
      }
      span.append(...el.childNodes)
      el.replaceWith(span)
    })
    // The register's page numbers are the PDF's; a reader has no pages.
    div.querySelectorAll('.qc-pageno').forEach((e) => e.remove())
    // What XHTML or the ePub schema does not take, and nothing in a document needs.
    div.querySelectorAll('*').forEach((el) => {
      for (const attr of [...el.attributes]) {
        const n = attr.name
        if (n === 'tabindex' || n === 'contenteditable' || n === 'draggable' || n.startsWith('on')) el.removeAttribute(n)
      }
    })
    div.querySelectorAll('input').forEach((input) => {
      if (input.type !== 'checkbox') input.remove()
    })

    const serializer = new XMLSerializer()
    const body = [...div.childNodes].map((n) => serializer.serializeToString(n)).join('')
    const probe = new DOMParser().parseFromString(`<body xmlns="${XHTML}" xmlns:epub="http://www.idpf.org/2007/ops">${body}</body>`, 'application/xhtml+xml')
    const err = probe.querySelector('parsererror')
    return {
      file,
      body,
      hasMath: !!div.querySelector('math'),
      hasSvg: !!div.querySelector('svg'),
      images,
      parseError: err ? (err.textContent ?? 'parse error').slice(0, 300) : null
    }
  })
  return { chapters, drawings, counts }
}
