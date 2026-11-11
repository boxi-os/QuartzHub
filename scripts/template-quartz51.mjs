// Adapts an unpacked qc-basic.qtpl to Quartz 5.1, in place.
//   node scripts/template-quartz51.mjs <unpacked qtpl> <quartz-5.1-project>
// Ran once on 2026-11-11 for Resources/templates/qc-basic.qtpl (unzip, run, zip again with the same
// entry order: `unzip -Z1 <old> | zip -X -D -9 <new> -@`); kept so the step can be read and repeated.
// - plugins: drop the entries 5.1 built in (crawl-links, remove-draft, content-index; their options
//   here equal 5.1's defaults) and the deprecated hard-line-breaks (off here); GFM 30 before OFM 40;
//   OFM without parseArrows (2.x has no such option); note-properties without delimiters/language
//   (configuration.frontmatter; the values were the defaults).
// - manifest: plugin stats and requires to match, versions as installed in the 5.1 project,
//   createdAt now (the newer package wins over a shipped copy).
// - content: paragraphs, list items and quotes unwrapped to one line each; 5.1 renders a single
//   line break as <br>, as Obsidian does.
import fs from "node:fs"
import path from "node:path"

const [dir, project] = process.argv.slice(2)
const read = (f) => JSON.parse(fs.readFileSync(path.join(dir, f), "utf8"))
const write = (f, v) => fs.writeFileSync(path.join(dir, f), JSON.stringify(v, null, 2))

const dropped = new Set(["crawl-links", "remove-draft", "content-index", "hard-line-breaks"])
const plugins = read("parts/plugins.json")
plugins.entries = plugins.entries.filter((e) => !dropped.has(e.name))
for (const e of plugins.entries) {
  if (e.name === "obsidian-flavored-markdown") {
    delete e.options.parseArrows
    e.order = 40
  }
  if (e.name === "github-flavored-markdown") e.order = 30
  if (e.name === "note-properties") {
    if (e.options.delimiters !== "---" || e.options.language !== "yaml") throw new Error("note-properties: not the defaults")
    delete e.options.delimiters
    delete e.options.language
  }
}
write("parts/plugins.json", plugins)

const manifest = read("manifest.json")
const part = manifest.parts.find((p) => p.id === "plugins")
part.stats.plugins = plugins.entries.length
part.stats.active = plugins.entries.filter((e) => e.enabled !== false).length
part.requires = part.requires.filter((r) => !dropped.has(r.name.split("/").pop()))
for (const p of manifest.parts) {
  for (const r of p.requires) {
    if (!r.version) continue
    const pkg = path.join(project, "node_modules", r.name, "package.json")
    if (fs.existsSync(pkg)) r.version = JSON.parse(fs.readFileSync(pkg, "utf8")).version
  }
}
manifest.createdAt = new Date().toISOString()
write("manifest.json", manifest)

// ── unwrap ──
const listItem = /^(\s*)([-*+]|\d+[.)])\s+(\[.\]\s+)?/
const hardBreak = (line) => / {2}$/.test(line) || /\\$/.test(line)
function unwrap(text) {
  const lines = text.split("\n")
  const out = []
  let i = 0
  if (lines[0] === "---") {
    const end = lines.indexOf("---", 1)
    out.push(...lines.slice(0, end + 1))
    i = end + 1
  }
  let fence = null
  // What the last output line can take: "para", "list:<indent>", "quote", or null.
  let open = null
  for (; i < lines.length; i++) {
    const line = lines[i]
    const fenceMark = line.match(/^\s*(```|~~~)/)
    if (fence) {
      out.push(line)
      if (fenceMark && fenceMark[1] === fence) fence = null
      continue
    }
    if (fenceMark) {
      fence = fenceMark[1]
      out.push(line)
      open = null
      continue
    }
    const prev = out.length - 1
    const canJoin = open && !hardBreak(out[prev])
    if (line.trim() === "" || /^\s*(#|\||<|\$\$|!\[\[|---\s*$)/.test(line)) {
      out.push(line)
      open = null
      continue
    }
    const quote = line.match(/^>\s?(.*)$/)
    if (quote) {
      const body = quote[1]
      if (open === "quote" && canJoin && body.trim() && !/^(\[!|[-*+]\s|\d+[.)]\s|#|\|)/.test(body)) {
        out[prev] = out[prev].trimEnd() + " " + body.trim()
      } else {
        out.push(line)
      }
      open = body.trim() && !/^\[!/.test(body) && !/^#/.test(body) ? "quote" : body.startsWith("[!") ? "quote-head" : null
      continue
    }
    const item = line.match(listItem)
    if (item) {
      out.push(line)
      open = `list:${item[0].length}`
      continue
    }
    if (open?.startsWith("list:") && canJoin && line.match(/^\s*/)[0].length >= 2) {
      out[prev] = out[prev].trimEnd() + " " + line.trim()
      continue
    }
    if (open === "para" && canJoin && !/^\s/.test(line)) {
      out[prev] = out[prev].trimEnd() + " " + line.trim()
      continue
    }
    out.push(line)
    open = /^\s/.test(line) ? null : "para"
  }
  return out.join("\n")
}

const content = read("parts/content.json")
let changed = 0
for (const f of content.files.filter((f) => f.endsWith(".md"))) {
  const file = path.join(dir, "files", "content", f)
  const before = fs.readFileSync(file, "utf8")
  const after = unwrap(before)
  // Only line breaks (and a quote's "> ") may change, never a word.
  const words = (t) => t.replace(/^>\s?/gm, "").replace(/\s+/g, " ").trim()
  if (words(before) !== words(after)) throw new Error(`${f}: words changed`)
  if (after !== before) {
    fs.writeFileSync(file, after)
    changed++
  }
}
console.log(`plugins ${part.stats.plugins}/${part.stats.active} active, ${changed} pages unwrapped, createdAt ${manifest.createdAt}`)
