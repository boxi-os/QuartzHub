#!/usr/bin/env node
// Golden file for InlineSvg, made by QuartzControl's own src/utils/inlineSvg.ts running in Google
// Chrome (headless, through QuartzControl's playwright-core): the renderer's DOMParser is the XML
// parser the sanitizer was written against. The inputs are the corpus of QuartzControl's
// check:inline-svg (what must not get through, and what must) plus edges of the XML side: a DOCTYPE
// with entities, whitespace, CDATA, comments and processing instructions in every place, editor
// namespaces, attribute names in every case, CSS escapes, the id rewriting.
//
//   Runtime/node/bin/node scripts/inline-svg-golden.mjs [../QuartzControl]
import { mkdirSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'inline-svg')
const require = createRequire(join(control, 'package.json'))
const { build } = require('esbuild')
const { chromium } = require('playwright-core')

const bundle = await build({ entryPoints: [join(control, 'src/utils/inlineSvg.ts')], bundle: true, write: false, format: 'iife', globalName: 'InlineSvg', logLevel: 'error' })

const X = 'http://www.w3.org/1999/xhtml'
const svg = (inner, attrs = '') => `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 24 24"${attrs}>${inner}</svg>`
const RUN = 'window.__ran=(window.__ran||0)+1'
const cases = [
  // check:inline-svg, what must not get through
  ['<script>', svg(`<script>${RUN}</script><path d="M0 0"/>`)],
  ['XHTML-<img onerror>', svg(`<img xmlns="${X}" src="x" onerror="${RUN}"/>`)],
  ['Processing Instruction mit <img onerror>', svg(`<?x ><img src=x onerror="${RUN}">?><path d="M0 0"/>`)],
  ['Tab im Schema', svg(`<a href="java&#9;script:${RUN}"><path d="M0 0h24v24H0z"/></a>`)],
  ['Zeilenumbrüche im Schema', svg(`<a href="&#10;java&#13;script:${RUN}"><path d="M0 0h24v24H0z"/></a>`)],
  ['xlink:href mit javascript:', svg(`<a xlink:href="javascript:${RUN}"><path d="M0 0h24v24H0z"/></a>`)],
  ['<set> auf href', svg(`<a href="#"><set attributeName="href" to="javascript:${RUN}"/><path d="M0 0h24v24H0z"/></a>`)],
  ['<animate> auf HREF', svg(`<a href="#"><animate attributeName="HREF" values="javascript:${RUN}"/><path d="M0 0h24v24H0z"/></a>`)],
  ['<set> auf xlink:href', svg(`<a href="#"><set attributeName="xlink:href" to="javascript:${RUN}"/><path d="M0 0h24v24H0z"/></a>`)],
  ['XHTML-<meta refresh>', svg(`<meta xmlns="${X}" http-equiv="refresh" content="0;url=about:blank"/>`)],
  ['<style> für die ganze Seite', svg('<style>body{display:none}</style><path d="M0 0"/>')],
  ['XHTML-<iframe>', svg(`<iframe xmlns="${X}" src="javascript:${RUN}"/>`)],
  ['<foreignObject>', svg(`<foreignObject><div xmlns="${X}" onclick="${RUN}">x</div></foreignObject>`)],
  ['CDATA mit Markup', svg(`<text><![CDATA[</text><img src=x onerror="${RUN}">]]></text>`)],
  ['Kommentar, den HTML früher beendet', svg(`<!--><img src=x onerror="${RUN}">--><path d="M0 0"/>`)],
  ['SVG-<img>, das aus dem SVG ausbricht', svg(`<img src="x" onerror="${RUN}"/>`)],
  ['onload an der Wurzel', svg('<path d="M0 0"/>', ` onload="${RUN}"`)],
  ['data:text/html im Verweis', svg(`<a href="data:text/html,&lt;script>parent.${RUN}&lt;/script>"><path d="M0 0h24v24H0z"/></a>`)],
  ['<use> auf eine fremde Datei', svg('<use href="https://example.com/sprite.svg#a"/>')],
  ['<image> mit SVG-Daten', svg(`<image href="data:image/svg+xml,&lt;svg xmlns='http://www.w3.org/2000/svg' onload='${RUN}'/>"/>`)],
  ['style-Attribut mit fremder url()', svg('<path style="fill:url(https://example.com/x)" d="M0 0"/>')],
  ['Element eines fremden Namensraums', svg('<x:script xmlns:x="http://www.w3.org/2000/svg">' + RUN + '</x:script>')],
  ['Markdown-Link mit javascript: im Text', svg(`<text>[KLICK](javascript:${RUN})</text>`)],
  ['Markdown-Link in CDATA', svg(`<text><![CDATA[[KLICK](javascript:${RUN})]]></text>`)],
  ['Markdown-Bild mit fremder Adresse im Text', svg('<text>![x](https://example.com/p.png)</text>')],
  ['Autolink im Text', svg(`<text>&lt;javascript:${RUN}&gt; www.example.com a@example.com</text>`)],
  ['<use HREF> auf eine fremde Datei', svg('<use HREF="https://example.com/sprite.svg#a"/>')],
  ['<feImage HREF> auf eine fremde Datei', svg('<filter id="f"><feImage HREF="https://example.com/f.png"/></filter><rect width="9" height="9" filter="url(#f)"/>')],
  ['<image HREF> über http', svg('<image HREF="http://example.com/i.png" width="9" height="9"/>')],
  ['<set ATTRIBUTENAME="href"> nach außen', svg('<a href="#"><set ATTRIBUTENAME="href" to="https://example.com/phish"/><rect width="24" height="24"/></a>')],
  ['<use HREF> mit SVG-Daten', svg(`<use HREF="data:image/svg+xml;base64,${Buffer.from(`<svg xmlns='http://www.w3.org/2000/svg' id='x'><image href='x' onerror='${RUN}'/></svg>`).toString('base64')}#x"/>`)],
  ['CSS-Escape in url() im style', svg('<rect width="9" height="9" style="background-image:u\\72 l(https://example.com/b.png)"/>')],
  ['image-set() im style', svg('<rect width="9" height="9" style="mask-image:image-set(&quot;https://example.com/m.png&quot; 1x)"/>')],
  ['CSS-Escape in url() in fill', svg('<rect width="9" height="9" fill="u\\72 l(https://example.com/p.svg#p)"/>')],
  ['href und HREF zugleich', svg('<use href="#s" HREF="https://example.com/s.svg#a"/>')],
  ['Zeilenanfang mit Markdown in einem Attribut', svg('<path aria-label="x&#10;# Titel&#10;- Punkt" d="M0 0&#10;- 1 2"/>')],
  ['Zeilenanfang mit Markdown im Text', svg('<text>x\n# Titel\n- Punkt\n1. Eins</text>')],
  ['Markdown-Link über Escapes im Text', svg(`<text>\\[KLICK\\](javascript:${RUN})</text>`)],
  // check:inline-svg, what must get through
  ['ein gewöhnliches Icon', svg(
    '<defs><linearGradient id="g"><stop offset="0" stop-color="red"/></linearGradient><symbol id="s"><circle cx="5" cy="5" r="4"/></symbol></defs>' +
      '<title>Logo &amp; Name</title><g class="a" fill="url(#g)" style="fill:url(#g);stroke:currentColor"><path d="M0 0h24"/><use href="#s"/><use xlink:href="#s"/></g>' +
      '<animate attributeName="opacity" values="0;1" dur="1s"/><a href="https://example.com/"><rect width="1" height="1"/></a>',
    ' class="eigen" width="24" height="24"'), 'Mein Logo.svg'],
  ['Illustrator mit internem CSS', '<svg xmlns="http://www.w3.org/2000/svg" id="Ebene_1" viewBox="0 0 24 24"><defs><style>.st0{fill:#E30613}.st1{fill:none;stroke:#1D1D1B;stroke-width:2}</style></defs><circle class="st0" cx="12" cy="12" r="8"/><line class="st1" x1="0" y1="0" x2="24" y2="24"/></svg>'],
  ['zwei Dateien mit denselben Ids', `<svg xmlns="http://www.w3.org/2000/svg" id="Ebene_1" viewBox="0 0 24 24" aria-labelledby="t"><title id="t">red</title><defs><linearGradient id="g"><stop stop-color="red"/></linearGradient><clipPath id="clip0_1_2"><rect width="24" height="24"/></clipPath><path id="p" d="M0 0h9"/></defs><g clip-path="url(#clip0_1_2)" style="fill:url(#g)"><rect width="24" height="24" fill="url(&quot;#g&quot;)"/><use href="#p"/><animate attributeName="opacity" begin="p.click" values="0;1"/></g></svg>`, 'rot.svg'],
  ['vier Schreibweisen eines Verweises', `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><defs><linearGradient id="g1"><stop stop-color="red"/></linearGradient><path id="s" d="M0 0h9"/></defs><g id="liste" aria-activedescendant="eins" aria-errormessage="fehler"><title id="eins">a</title><desc id="fehler">b</desc></g><rect id="r" width="9" height="9" style="fill:url(#g\\31)"/><use id="u" href=" #s"/><animate id="anim.1" attributeName="opacity" values="0;1" dur="1s"/><animate id="b" attributeName="opacity" begin="anim.1.end" values="1;0"/></svg>`, 'formen.svg'],
  ['kein SVG: html', '<html/>'], ['kein SVG: Text', 'kein xml'],
  // the XML side
  ['DOCTYPE mit Entity', '<?xml version="1.0"?><!DOCTYPE svg [<!ENTITY farbe "red">]><svg xmlns="http://www.w3.org/2000/svg"><rect fill="&farbe;" width="1" height="1"/><text>&farbe;</text></svg>'],
  ['DOCTYPE mit externer Entity', '<?xml version="1.0"?><!DOCTYPE svg [<!ENTITY ext SYSTEM "file:///etc/hosts">]><svg xmlns="http://www.w3.org/2000/svg"><text>&ext;</text></svg>'],
  ['Inkscape', '<?xml version="1.0" encoding="UTF-8" standalone="no"?>\n<!-- Created with Inkscape -->\n\n<svg\n   width="24"\n   height="24"\n   viewBox="0 0 24 24"\n   version="1.1"\n   id="svg5"\n   inkscape:version="1.2"\n   sodipodi:docname="icon.svg"\n   xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape"\n   xmlns:sodipodi="http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd"\n   xmlns="http://www.w3.org/2000/svg"\n   xmlns:svg="http://www.w3.org/2000/svg"\n   xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"\n   xmlns:cc="http://creativecommons.org/ns#"\n   xmlns:dc="http://purl.org/dc/elements/1.1/">\n  <sodipodi:namedview\n     id="namedview7"\n     pagecolor="#ffffff" />\n  <defs\n     id="defs2" />\n  <metadata><rdf:RDF><cc:Work rdf:about=""><dc:title>x</dc:title></cc:Work></rdf:RDF></metadata>\n\n\n  <g\n     inkscape:label="Ebene 1"\n     inkscape:groupmode="layer"\n     id="layer1">\n    <path\n       style="fill:#000000;stroke-width:0.5"\n       d="M 2,2 H 22 V 22 H 2 Z"\n       id="rect1" />\n  </g>\n</svg>\n', 'icon.svg'],
  ['Figma', '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">\n<g clip-path="url(#clip0_1_2)">\n<path d="M12 2L2 22H22L12 2Z" fill="#1E1E1E"/>\n</g>\n<defs>\n<clipPath id="clip0_1_2">\n<rect width="24" height="24" fill="white"/>\n</clipPath>\n</defs>\n</svg>\n', 'Frame 1.svg'],
  ['svg:-Präfix', '<svg:svg xmlns:svg="http://www.w3.org/2000/svg" viewBox="0 0 1 1"><svg:rect width="1" height="1"/></svg:svg>', 'praefix.svg'],
  ['Wurzel ohne Namensraum', '<svg viewBox="0 0 1 1"><rect/></svg>'],
  ['Wurzel im falschen Namensraum', '<svg xmlns="http://www.w3.org/1999/xhtml"><rect/></svg>'],
  ['parsererror als Element', svg('<parsererror/><rect/>')],
  ['nicht wohlgeformt', svg('<rect></g>')],
  ['doppeltes Attribut', svg('<rect width="1" width="2"/>')],
  ['Attributnamen in jeder Schreibweise', svg('<linearGradient GRADIENTUNITS="userSpaceOnUse" gradientUnits="x" id="L"/><rect VIEWBOX="0 0 1 1" ViewBox="9" data-x="1" Data-X="2" aria-hidden="true" ONCLICK="x" onClick="y" _bad="1" a.b="ok" a-b="ok"/>')],
  ['xml:space und xml:lang', svg('<text xml:space="preserve" xml:lang="de">  a  </text>')],
  ['fremder Attribut-Namensraum', svg('<rect xmlns:f="https://example.com/f" f:x="1" width="1"/>')],
  ['Verweise auf Ids, die es nicht gibt', svg('<use href="#nope"/><rect fill="url(#nope)" aria-labelledby="nope a"/><animate begin="nope.click;  x.end ; 5s" attributeName="opacity"/>')],
  ['Ids mit Sonderzeichen', svg('<linearGradient id="a b"/><linearGradient id="c\\d"/><rect fill="url(#a\\ b)" style="fill:url(&quot;#c\\\\d&quot;)"/><rect id="dot.ted" fill="url(#dot.ted)"/>')],
  ['leeres id', svg('<rect id="" width="1"/><use href="#"/>')],
  ['Bilder', svg('<image href="data:image/png;base64,AAAA"/><image href="data:image/jpg,x"/><image href="data:image/svg+xml,x"/><image href="HTTPS://x/y.png"/><image href="ftp://x"/><image href="#local"/><a href="MAILTO:a@b"/><a href=" https://x"/><a href="http://x"/>')],
  ['CSS-Escapes', svg('<rect fill="\\75 rl(https://x)"/><rect fill="\\000075rl(https://x)"/><rect fill="u\\rl(https://x)"/><rect fill="\\0 rl(x)"/><rect fill="url(  &quot;#ok&quot;)"/><rect style="background:URL(#ok)"/><rect style="x:\\40 import"/><rect style="width:expression (1)"/><rect fill="src(x)"/><rect fill="image(x)"/><rect fill="cross-fade(x)"/><rect title="JaVaScRiPt:x"/>')],
  ['Animationen', svg('<animate attributeName="xlink:HREF"/><animate attributeName=" onclick"/><animateMotion attributeName="ON"/><animateTransform attributeName="transform" type="rotate"/><set attributeName="fill" to="red"/><animate attributeName="x:on"/>')],
  ['Text mit allen Markdown-Zeichen', svg('<text>a&amp;b&lt;c&gt;[d](e)!f*g_h`i~j\\k|l:m#n+o=p.q@r-s "t\' u</text>')],
  ['Leerzeilen', svg('\n\n<g>\n\n\n<rect/>\n  \n</g>\n\n')],
  ['Klassen an der Wurzel', svg('<rect/>', ' class="  icon svg-logo  "'), 'logo.SVG'],
  ['Dateiname ohne Buchstaben', svg('<rect/>'), '.svg'],
  ['Dateiname mit Zeichen', svg('<rect/>'), '--Ünïcödé & Co. 2.svg'],
  ['Attributwerte mit Zeichen', svg('<rect aria-label="a&amp;b&lt;c&gt;&quot;d&apos;e&#10;f&#13;g&#9;h" width="1"/>')],
  ['tiefe Verschachtelung', svg('<g>'.repeat(40) + '<rect/>' + '</g>'.repeat(40))],
  ['nur die Wurzel', '<svg xmlns="http://www.w3.org/2000/svg"/>', 'leer.svg'],
  ['Kommentare und PIs überall', '<?xml version="1.0"?><!--a--><?pi x?><svg xmlns="http://www.w3.org/2000/svg"><!--b--><?pi y?><g><!--c--></g></svg><!--d--><?pi z?>'],
  ['href und xlink:href zugleich', svg('<symbol id="a"/><symbol id="b"/><use xlink:href="#b" href="#a"/><use href="#a" xlink:href="#b"/>')],
  ['Unicode', svg('<text>日本語 🎨 Ä</text><rect aria-label="Grüße 🎨"/>'), 'Grüße.svg']
]

const browser = await chromium.launch({ channel: 'chrome' })
const page = await browser.newPage()
await page.setContent('<!doctype html><title>t</title>')
await page.addScriptTag({ content: bundle.outputFiles[0].text })
const results = []
for (const [name, text, file = 'test-icon.svg'] of cases) {
  const result = await page.evaluate(([t, n]) => InlineSvg.inlineSvg(t, n), [text, file])
  results.push({ name, text, file, result })
}
await browser.close()
mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'cases.json'), JSON.stringify(results, null, 2) + '\n')
console.log(`inline-svg: ${results.length} cases`)
for (const r of results) console.log(`  ${r.name}: ${r.result.ok ? `removed ${r.result.removed}${r.result.styled ? ' styled' : ''} ${r.result.markup.slice(0, 90)}` : 'rejected'}`)
