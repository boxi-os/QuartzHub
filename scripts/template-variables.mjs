// Writes a template's variable catalogue (docs/plan-plugin-variablen.md, Teil D) into an unpacked
// .qtpl, in place: the `quartz-variables` comment at the end of files/styles/custom/foundation.scss
// (an earlier catalogue there is replaced) and `createdAt` in the manifest, so the newer package
// wins over a cached copy.
//   node scripts/template-variables.mjs <unpacked qtpl> <catalogue.json> <createdAt>
//   node scripts/template-variables.mjs <foundation.scss> <catalogue.json>   (a project's own copy)
// The catalogue of the base template is scripts/template-variables/qc-basic.json: groups with
// English and German labels, then per variable [name, group, kind, description, description_de].
// Pack again with the same entry order: `unzip -Z1 <old> | zip -X -D -9 <new> -@` from inside the
// unpacked folder. First run 2026-11-22 for Resources/templates/qc-basic.qtpl.
import fs from "node:fs"
import path from "node:path"

const [dir, catalogueFile, createdAt] = process.argv.slice(2)
const intoFile = dir?.endsWith(".scss")
if (!dir || !catalogueFile || (!intoFile && !createdAt)) {
  console.error("usage: template-variables.mjs <unpacked qtpl> <catalogue.json> <createdAt> | <file.scss> <catalogue.json>")
  process.exit(2)
}
const data = JSON.parse(fs.readFileSync(catalogueFile, "utf8"))

export function block(data) {
  const vs = data.variables.map(([name, group, kind, description, description_de]) => ({ name, group, kind, description, description_de }))
  const json = (v) => JSON.stringify(v).replace(/":/g, '": ').replace(/,"/g, ', "')
  const lines = ["{", '  "groups": [']
  data.groups.forEach((g, i) => lines.push("    " + json(g) + (i < data.groups.length - 1 ? "," : "")))
  lines.push("  ],", '  "variables": [')
  vs.forEach((v, i) => lines.push("    " + json(v) + (i < vs.length - 1 ? "," : "")))
  lines.push("  ]", "}")
  const body = lines.join("\n")
  if (body.includes("*/")) throw new Error("a description holds */")
  JSON.parse(body)
  return (
    "/* ------------------------------------------------------------------------ catalogue */\n\n" +
    "// What each variable of this template is for, in groups, for editors such as QuartzHub\n" +
    "// (Styles ▸ Variables). The values live in the css-vars block and in the rules above; this\n" +
    "// only explains them.\n" +
    "/* quartz-variables\n" + body + "\n*/\n"
  )
}

const foundation = intoFile ? dir : path.join(dir, "files/styles/custom/foundation.scss")
const text = fs.readFileSync(foundation, "utf8")
  .replace(/\n*\/\* -+ catalogue \*\/[\s\S]*?\/\* quartz-variables[\s\S]*?\*\/\n?/, "\n")
  .replace(/\n+$/, "")
fs.writeFileSync(foundation, text + "\n\n" + block(data))
if (intoFile) {
  console.log(`${data.variables.length} variables in ${data.groups.length} groups`)
  process.exit(0)
}

const manifestFile = path.join(dir, "manifest.json")
const manifest = JSON.parse(fs.readFileSync(manifestFile, "utf8"))
manifest.createdAt = createdAt
fs.writeFileSync(manifestFile, JSON.stringify(manifest, null, 2))
console.log(`${data.variables.length} variables in ${data.groups.length} groups`)
