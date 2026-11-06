// What writePdf.ts relies on, read from a PDF: pages, size, outline, named destinations, links, tags.
import { readFileSync } from 'fs'
import { PDFDocument, PDFName, PDFDict, PDFArray, PDFString, PDFHexString } from '/Users/boxi/Development/QuartzControl/node_modules/pdf-lib/cjs/index.js'
for (const file of process.argv.slice(2)) {
  const doc = await PDFDocument.load(readFileSync(file), { updateMetadata: false })
  const pages = doc.getPages()
  const levels = []
  const walk = (first, d) => { for (let n = first; n; n = n.lookupMaybe(PDFName.of('Next'), PDFDict)) { levels[d] = (levels[d] ?? 0) + 1; walk(n.lookupMaybe(PDFName.of('First'), PDFDict), d + 1) } }
  walk(doc.catalog.lookupMaybe(PDFName.of('Outlines'), PDFDict)?.lookupMaybe(PDFName.of('First'), PDFDict), 0)
  const dests = doc.catalog.lookupMaybe(PDFName.of('Dests'), PDFDict)
  const namesDests = doc.catalog.lookupMaybe(PDFName.of('Names'), PDFDict)?.lookupMaybe(PDFName.of('Dests'), PDFDict)
  let internal = 0, uri = 0, other = 0
  for (const p of pages) {
    const annots = p.node.lookupMaybe(PDFName.of('Annots'), PDFArray)
    if (!annots) continue
    for (let i = 0; i < annots.size(); i++) {
      const a = annots.lookup(i, PDFDict)
      if (a.get(PDFName.of('Subtype'))?.toString() !== '/Link') continue
      const action = a.lookupMaybe(PDFName.of('A'), PDFDict)
      const s = action?.get(PDFName.of('S'))?.toString()
      if (a.get(PDFName.of('Dest')) || s === '/GoTo') internal++
      else if (s === '/URI') uri++
      else other++
    }
  }
  const box = pages[0].getMediaBox()
  console.log(JSON.stringify({
    file: file.split('/').pop(),
    pages: pages.length,
    size: `${Math.round(box.width)}x${Math.round(box.height)}`,
    outline: levels,
    dests: dests ? dests.keys().length : 0,
    namesTreeDests: !!namesDests,
    links: { internal, uri, other },
    tagged: !!doc.catalog.get(PDFName.of('StructTreeRoot')),
    markInfo: !!doc.catalog.get(PDFName.of('MarkInfo')),
    lang: doc.catalog.get(PDFName.of('Lang'))?.toString() ?? null
  }))
}
