// Page numbers of the TOC targets: Chrome via named destinations (writePdf.ts), WebKit via the
// explicit destinations of the TOC's own link annotations.
import { readFileSync } from 'fs'
import { PDFDocument, PDFName, PDFDict, PDFArray } from '/Users/boxi/Development/QuartzControl/node_modules/pdf-lib/cjs/index.js'
const [chromeFile, webkitFile] = process.argv.slice(2)
async function load(f) { const d = await PDFDocument.load(readFileSync(f), { updateMetadata: false }); return { d, pageNo: new Map(d.getPages().map((p, i) => [p.ref.toString(), i + 1])) } }
function linkTargets({ d, pageNo }, pageIndex) {
  const out = []
  const annots = d.getPages()[pageIndex].node.lookupMaybe(PDFName.of('Annots'), PDFArray)
  for (let i = 0; i < (annots?.size() ?? 0); i++) {
    const a = annots.lookup(i, PDFDict)
    const rawDest = a.lookup(PDFName.of('Dest'))
    let dest = rawDest instanceof PDFArray ? rawDest : undefined
    const action = a.lookupMaybe(PDFName.of('A'), PDFDict)
    let named = null
    if (!dest && action) { const dd = action.get(PDFName.of('D')); if (dd instanceof PDFArray) dest = dd; else named = dd?.toString() }
    if (!dest && !named && rawDest) named = rawDest.toString()
    if (dest) out.push(pageNo.get(dest.get(0).toString()) ?? '?')
    else if (named) {
      const dests = d.catalog.lookupMaybe(PDFName.of('Dests'), PDFDict)
      const v = dests?.lookup(PDFName.of(named.replace(/^\//, '').replace(/^\(|\)$/g, '')))
      const arr = v instanceof PDFArray ? v : v?.lookupMaybe?.(PDFName.of('D'), PDFArray)
      out.push(arr ? pageNo.get(arr.get(0).toString()) : `named:${named}`)
    }
  }
  return out
}
const c = await load(chromeFile), w = await load(webkitFile)
console.log('chrome TOC targets:', linkTargets(c, 1).join(' '))
console.log('webkit TOC targets:', linkTargets(w, 1).join(' '))
