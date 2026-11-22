// Adapts an unpacked qc-basic.qtpl to Quartz 5.2, in place.
//   node scripts/template-quartz52.mjs <unpacked qtpl> <quartz-5.2-project>
// Ran once on 2026-11-22 for Resources/templates/qc-basic.qtpl (unzip, run, zip again with the same
// entry order: `unzip -Z1 <old> | zip -X -D -9 <new> -@`); kept so the step can be read and repeated.
// Measured on a 5.2 copy of gui-test, which has the template's stylesheets
// (docs/decisions/phase-5-gleichstand.md, "Quartz 5.2", Vorlage):
// - plugins: drop the quartz-fonts entry (off here). 5.2 builds the plugin in, and an entry that is
//   off turns the built-in off and makes Quartz warn on every build.
// - appearance: `fonts` (configuration.fonts) with `fontOrigin: local`, or the built-in loads from
//   Google, and `interface` set to the body font: the built-in sets --font-interface to the
//   system's sans stack, where the template's stylesheets had var(--bodyFont) (7 kinds of element
//   changed font without it, none with it).
// - styles: callouts are <div> since 5.2 and lost the padding `article blockquote` gave them;
//   content.scss takes them in with :where(), below .callout's weight (0 differences in box and
//   title position against a 5.1 blockquote callout).
// - manifest: plugin stats and requires to match, versions as installed in the 5.2 project,
//   createdAt now (the newer package wins over a shipped copy or a cached one).
import fs from "node:fs"
import path from "node:path"

const [dir, project] = process.argv.slice(2)
if (!dir || !project) throw new Error("usage: template-quartz52.mjs <unpacked qtpl> <quartz-5.2-project>")
if (!fs.existsSync(path.join(project, "quartz", "plugins", "builtins", "fonts.ts"))) throw new Error(`${project}: not Quartz 5.2`)
const read = (f) => JSON.parse(fs.readFileSync(path.join(dir, f), "utf8"))
const write = (f, v) => fs.writeFileSync(path.join(dir, f), JSON.stringify(v, null, 2))

const plugins = read("parts/plugins.json")
const fontsEntry = plugins.entries.find((e) => e.name === "quartz-fonts")
if (!fontsEntry || fontsEntry.enabled !== false) throw new Error("quartz-fonts: expected an entry that is off")
plugins.entries = plugins.entries.filter((e) => e.name !== "quartz-fonts")
write("parts/plugins.json", plugins)

const appearance = read("parts/appearance.json")
const body = appearance.typography?.body
const bodyName = typeof body === "string" ? body : body?.name
if (!bodyName) throw new Error("appearance: no body font")
if (appearance.fontOrigin !== "local") throw new Error("appearance: fonts not served locally")
appearance.fonts = { fontOrigin: "local", interface: bodyName }
write("parts/appearance.json", appearance)

const contentScss = path.join(dir, "files", "styles", "custom", "content.scss")
const quotations = `  /* -------------------------------------------------------------------- quotations */

  blockquote {
`
let scss = fs.readFileSync(contentScss, "utf8")
if (!scss.includes(quotations)) throw new Error("content.scss: the blockquote rule moved")
scss = scss.replace(quotations, `  /* -------------------------------------------------------------------- quotations */

  // Quartz 5.2 writes callouts as <div>, before as <blockquote>: :where() keeps them in this rule
  // without its weight, so .callout (callouts.scss) still sets border, margin and background.
  blockquote,
  :where(div.callout) {
`)
fs.writeFileSync(contentScss, scss)

const manifest = read("manifest.json")
const part = manifest.parts.find((p) => p.id === "plugins")
part.stats.plugins = plugins.entries.length
part.stats.active = plugins.entries.filter((e) => e.enabled !== false).length
part.requires = part.requires.filter((r) => r.name !== "@quartz-community/quartz-fonts")
for (const p of manifest.parts) {
  for (const r of p.requires) {
    if (!r.version) continue
    const pkg = path.join(project, "node_modules", r.name, "package.json")
    if (fs.existsSync(pkg)) r.version = JSON.parse(fs.readFileSync(pkg, "utf8")).version
  }
}
manifest.createdAt = new Date().toISOString()
write("manifest.json", manifest)
console.log(`plugins ${part.stats.plugins}/${part.stats.active} active, fonts ${JSON.stringify(appearance.fonts)}, createdAt ${manifest.createdAt}`)
