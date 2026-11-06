// Reference: Chrome prints the probe document with the options writePdf.ts gives printToPDF.
import { chromium } from '/Users/boxi/Development/QuartzControl/node_modules/playwright-core/index.mjs'
const [url, out] = process.argv.slice(2)
const browser = await chromium.launch({ channel: 'chrome' })
const page = await browser.newPage({ viewport: { width: Math.round(((210 - 36) / 25.4) * 96), height: 1000 } })
await page.emulateMedia({ media: 'print', colorScheme: 'light' })
const t0 = Date.now()
await page.goto(url, { waitUntil: 'networkidle' })
await page.pdf({ path: out, preferCSSPageSize: true, width: '210mm', height: '297mm', printBackground: true, outline: true, tagged: true })
console.log('chrome pdf in', Date.now() - t0, 'ms')
await browser.close()
