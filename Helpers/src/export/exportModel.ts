import type { BookDefinition, BookEntry } from './ipc-contract'

/**
 * The pure half of the document export: how a page of the built site is named, where it sits in
 * the document, and what the book's order resolves to. No DOM, no Node - the main process uses it,
 * the check scripts load a .mts copy, and two of the functions are handed to the export window as
 * source (`slugFromPathname`, `anchorFor`), which is why those two close over nothing and use no
 * helper from this file.
 */

/**
 * A URL path of the built site as Quartz's slug: no leading slash, no `.html`, a folder as its
 * `index`. `/1-einstieg/` and `/1-einstieg/index.html` are both `1-einstieg/index`; the root is
 * `index`. Percent-escapes are decoded, since slugs are stored decoded (contentIndex.json).
 * Runs in the export window too - see the note at the top.
 */
export function slugFromPathname(pathname: string): string {
  let p = pathname
  try {
    p = decodeURIComponent(p)
  } catch {
    // A malformed escape stays as it is; the slug simply will not match a page.
  }
  p = p.replace(/^\/+/, '')
  if (p === '' || p.endsWith('/')) p += 'index'
  if (p.endsWith('.html')) p = p.slice(0, -'.html'.length)
  return p
}

/**
 * The id a page (or a heading on it) gets in the combined document. Injective, unlike the
 * handbook script's `replace(/[^a-z0-9]+/gi, '-')`, which made `a-b` and `a/b` the same anchor:
 * every character outside [A-Za-z0-9-] - the underscore included, so the escape cannot be forged -
 * becomes `_<hex>_`. Runs in the export window too - see the note at the top.
 */
export function anchorFor(slug: string, id?: string): string {
  const esc = (s: string): string => s.replace(/[^A-Za-z0-9-]/g, (c) => '_' + c.codePointAt(0)!.toString(16) + '_')
  return 'p-' + esc(slug) + (id ? '--' + esc(id) : '')
}

/** The folder a slug sits in, '' for the top level. `a/b/index` is the folder `a/b` itself. */
export function folderOf(slug: string): string {
  const parts = slug.split('/')
  parts.pop()
  return parts.join('/')
}

/** Whether a slug lies in the book's root folder ('' = the whole site). */
export function insideRoot(slug: string, root: string): boolean {
  return root === '' || slug === `${root}/index` || slug.startsWith(`${root}/`)
}

/**
 * How deep a page sits below the book's root: the root's own index is 0, a page or a subfolder's
 * index directly in it is 1, and so on. The document heading of the page is `max(1, depth)`, plus
 * one inside a section opened by a heading entry - which reproduces the handbook script's levels
 * without knowing about chapters: start page h1, chapter start pages h1, their pages h2, and the
 * appendix pages h2 under the interposed h1 „Anhang“.
 */
export function pageDepth(slug: string, root: string): number {
  const rel = root === '' ? slug : slug.slice(root.length + 1)
  const parts = rel.split('/')
  if (parts[parts.length - 1] === 'index') parts.pop()
  return parts.length
}

export function isFolderIndex(slug: string): boolean {
  return slug === 'index' || slug.endsWith('/index')
}

/**
 * The order Quartz's Explorer shows with its default options, from the pages in contentIndex.json
 * order: the ersatz when the start page has no navigation to read (the book held only the start
 * page before). Recomputed from `@quartz-community/explorer` as built (its `FileTrieNode` and
 * the default `sortFn`/`filterFn`), not from what a project configured - a site with its own
 * `sortFn` renders its Explorer, and then that is read instead.
 *  - unlike the Explorer, a page named `tags` below the top level stays: the default filterFn
 *    drops every node of that name to hide Quartz's tag listings, which `readSiteFacts` leaves out
 *    already, and in Example it dropped the page about the Tags component;
 *  - a folder's name is its index page's title, else the folder's name on disk (from `filePath`),
 *    else its slug segment;
 *  - in every folder, folders before pages, each by name, numeric and case-insensitive;
 *  - depth first, a folder's own index page before its contents. The site's start page comes
 *    first; the Explorer does not list it, and `resolveOrder` would put it there anyway.
 */
export function explorerOrder(pages: Iterable<{ slug: string; title: string; filePath?: string }>): string[] {
  interface Node {
    segment: string
    folder: boolean
    page?: { slug: string; title: string }
    hint?: string
    children: Node[]
  }
  const root: Node = { segment: '', folder: true, children: [] }
  for (const p of pages) {
    const parts = p.slug.split('/')
    const fileParts = (p.filePath ?? '').split('/')
    let node = root
    for (const [i, segment] of parts.entries()) {
      const rest = parts.length - i
      if (rest === 1) {
        if (segment === 'index') node.page ??= p
        else node.children.push({ segment, folder: false, page: p, children: [] })
        break
      }
      // Like the Explorer: any child of that name, a page of the same name included, becomes the
      // folder.
      let child = node.children.find((c) => c.segment === segment)
      if (!child) {
        child = { segment, folder: false, children: [] }
        node.children.push(child)
      }
      child.folder = true
      child.hint = fileParts[fileParts.length - rest] || undefined
      node = child
    }
  }
  const name = (n: Node): string => (n.page && n.page.title !== 'index' ? n.page.title : '') || n.hint || n.segment
  const out: string[] = []
  const walk = (n: Node): void => {
    if (n.page) out.push(n.page.slug)
    const sorted = [...n.children].sort((a, b) =>
      a.folder === b.folder ? name(a).localeCompare(name(b), undefined, { numeric: true, sensitivity: 'base' }) : a.folder ? -1 : 1
    )
    for (const c of sorted) walk(c)
  }
  walk(root)
  return out
}

/** One place in the resolved document: a page with its heading level, or an interposed heading. */
export type DocItem =
  | { kind: 'page'; slug: string; level: number }
  | { kind: 'heading'; text: string; level: 1 }

export interface ResolvedOrder {
  items: DocItem[]
  /** Pages the book's own order names that the build no longer has. */
  missing: string[]
  /** Pages of the build that are new since the order was written; appended at the end. */
  appended: string[]
}

/**
 * The book's order against what the site has now.
 *
 * `navigation` is the order the built site shows (read from its navigation, see
 * export/pageScripts.ts), `available` every page of the build in the book's language. Following
 * the navigation, the book is the navigation within its root, minus `excluded`, plus pages the
 * navigation does not show - those are not silently dropped but left for the editor to offer.
 * With an own order, a page that is gone is named in `missing`, and a page that is new is appended
 * and named in `appended`, so a run can say what it did instead of the document changing shape
 * quietly.
 */
export function resolveOrder(book: Pick<BookDefinition, 'order' | 'excluded' | 'root'>, navigation: string[], available: ReadonlySet<string>): ResolvedOrder {
  const excluded = new Set(book.excluded)
  const usable = (slug: string): boolean => available.has(slug) && insideRoot(slug, book.root) && !excluded.has(slug)
  // The start page of the root comes first even when the navigation does not show it: Quartz's
  // Explorer lists folders and pages, but never the site's own index (measured on the handbook).
  const rootIndex = book.root === '' ? 'index' : `${book.root}/index`
  if (!navigation.includes(rootIndex)) navigation = [rootIndex, ...navigation]
  const entries: BookEntry[] = []
  const missing: string[] = []
  const appended: string[] = []
  if (book.order === null) {
    for (const slug of navigation) if (usable(slug)) entries.push({ slug })
  } else {
    const listed = new Set<string>()
    for (const e of book.order) {
      if ('heading' in e) {
        entries.push(e)
        continue
      }
      listed.add(e.slug)
      if (!available.has(e.slug)) missing.push(e.slug)
      else if (usable(e.slug)) entries.push(e)
    }
    for (const slug of navigation) {
      if (!listed.has(slug) && usable(slug)) {
        entries.push({ slug })
        appended.push(slug)
      }
    }
  }
  const seen = new Set<string>()
  const items: DocItem[] = []
  let inSection = false
  for (const e of entries) {
    if ('heading' in e) {
      items.push({ kind: 'heading', text: e.heading, level: 1 })
      inSection = true
      continue
    }
    if (seen.has(e.slug)) continue
    seen.add(e.slug)
    items.push({ kind: 'page', slug: e.slug, level: Math.min(6, Math.max(1, pageDepth(e.slug, book.root)) + (inSection ? 1 : 0)) })
  }
  return { items, missing, appended }
}

/**
 * Where a link to a page outside the book goes. With a baseUrl, to that page on the published
 * site - the reader of a PDF can still follow it. Without one there is no address to give, and the
 * link becomes text (the caller counts those, so the run can say so).
 */
export function outsideUrl(baseUrl: string | undefined, slug: string, hash: string): string | null {
  if (!baseUrl) return null
  const host = baseUrl.replace(/^https?:\/\//, '').replace(/\/+$/, '')
  if (!host) return null
  const path = slug === 'index' ? '' : slug.endsWith('/index') ? slug.slice(0, -'index'.length) : slug
  return `https://${host}/${path.split('/').map(encodeURIComponent).join('/')}${hash}`
}

/** A link as contentIndex.json stores it, as a slug: a folder link (`4-gestaltung/`) is its index. */
export function linkSlug(link: string): string {
  const s = link.replace(/^\/+/, '').split('#')[0]
  return s === '' || s.endsWith('/') ? `${s}index` : s
}

/**
 * Which pages of the book link to each page of the book, in book order. From the links Quartz
 * itself recorded (contentIndex.json) - the same source the site's Backlinks component reads -
 * restricted to the book, because a backlink into a page the reader does not have leads nowhere.
 */
export function backlinksInBook(slugs: string[], linksOf: (slug: string) => string[]): Map<string, string[]> {
  const inBook = new Set(slugs)
  const out = new Map<string, string[]>(slugs.map((s) => [s, []]))
  for (const from of slugs) {
    const targets = new Set(linksOf(from).map(linkSlug))
    for (const to of targets) if (to !== from && inBook.has(to)) out.get(to)!.push(from)
  }
  return out
}

/** The tags of the book's pages, each with its pages in book order, sorted for `locale`. */
export function tagRegister(slugs: string[], tagsOf: (slug: string) => string[], locale: string): { tag: string; pages: string[] }[] {
  const byTag = new Map<string, string[]>()
  for (const slug of slugs) for (const tag of new Set(tagsOf(slug))) byTag.set(tag, [...(byTag.get(tag) ?? []), slug])
  const collator = new Intl.Collator(locale || undefined, { numeric: true, sensitivity: 'base' })
  return [...byTag].map(([tag, pages]) => ({ tag, pages })).sort((a, b) => collator.compare(a.tag, b.tag))
}

/** The slug the register stands under in the document: a name no Quartz page can have. */
export const REGISTER_SLUG = '__quartzcontrol/register'
