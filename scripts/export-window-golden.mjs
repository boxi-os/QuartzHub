#!/usr/bin/env node
// Golden file for ExportWindow's rule, made by QuartzControl's own export/exportWindow.ts with
// Electron as a stand-in that hands over what the window registers: the `onBeforeRequest` handler
// is called with one request after another (address and Chromium's resource type) and answers
// whether it cancels, and what the window counted afterwards (refused by type and host, fetched by
// host); `will-navigate` and `will-redirect` with addresses; the window-open handler; the
// permission handler. What WebKit makes of the same rule is measured through `qh-check
// export-window`.
//
//   Runtime/node/bin/node scripts/export-window-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'export-window')

const electron = `
export const session = { fromPartition() { return globalThis.__session } }
export class BrowserWindow {
  constructor(options) { globalThis.__windowOptions = options; this.webContents = globalThis.__webContents }
  isDestroyed() { return false }
  destroy() {}
}`
globalThis.__on = {}
globalThis.__session = {
  webRequest: { onBeforeRequest(handler) { globalThis.__before = handler } },
  setPermissionRequestHandler(handler) { globalThis.__permission = handler },
  clearStorageData: async () => {}
}
globalThis.__webContents = {
  setWindowOpenHandler(handler) { globalThis.__open = handler },
  on(event, handler) { globalThis.__on[event] = handler }
}
const { openExportWindow } = await loadQuartzControl(control, 'electron/main/services/export/exportWindow.ts', {
  ...commonStubs, electron, '../../appWindows': 'export function markHelperWindow() {}'
})

const origin = 'http://127.0.0.1:52103'
const win = openExportWindow(origin, { width: 658, height: 1000 })
const requests = [
  [`${origin}/`, 'mainFrame'], [`${origin}/index.css`, 'stylesheet'], [`${origin}/static/x.js`, 'script'], [`${origin}/static/contentIndex.json`, 'xhr'],
  [origin, 'mainFrame'], [`${origin}x/evil`, 'script'], ['http://127.0.0.1:52104/x.js', 'script'], ['http://localhost:52103/x.js', 'script'],
  ['data:image/png;base64,AAAA', 'image'], ['data:text/javascript,1', 'script'], ['blob:http://127.0.0.1:52103/1-2', 'script'], ['devtools://devtools/x', 'other'],
  ['https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css', 'stylesheet'], ['https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/fonts/KaTeX_Main-Regular.woff2', 'font'],
  ['https://fonts.gstatic.com/s/inter/v1/a.woff2', 'font'], ['https://example.com/picture.png', 'image'], ['https://example.com:8443/picture.png', 'image'],
  ['https://cdnjs.cloudflare.com/ajax/libs/mermaid/11.4.0/mermaid.min.js', 'script'], ['https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs', 'script'],
  ['https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js', 'script'], ['https://cdn.jsdelivr.net/npm/mermaid-chunk.js', 'script'], ['https://x.example/mermaidx.js', 'script'],
  ['https://x.example/Mermaid.js', 'script'], ['https://plausible.io/js/script.js', 'script'], ['https://plausible.io/api/event', 'ping'], ['https://plausible.io/api/event', 'xhr'],
  ['https://cdn.jsdelivr.net/npm/d3@7', 'script'], ['wss://live.example/socket', 'webSocket'], ['ws://127.0.0.1:52104/ws', 'webSocket'],
  ['https://www.youtube.com/embed/x', 'subFrame'], ['https://example.com/video.mp4', 'media'], ['https://example.com/doc.pdf', 'object'],
  ['chrome-extension://mhjfbmdgcfjbbpaeojofohoefgiehjai/index.html', 'subFrame'], ['about:blank', 'subFrame'], ['ftp://example.com/x', 'other'],
  ['not a url at all, longer than forty characters for the cut', 'other'], ['https://example.com/a.css', 'stylesheet'], ['https://example.com/a.css', 'stylesheet'],
  ['https://user:pw@example.com/p.png', 'image'], ['https://EXAMPLE.com/p.png', 'image'], ['https://xn--grten-gra.example/p.png', 'image'], ['https://gärten.example/p.png', 'image'],
  ['https://[::1]:8080/p.png', 'image'], ['https://example.com/beacon', 'ping'], ['https://example.com/csp', 'cspReport'], ['https://example.com/x', 'other']
]
const decisions = []
for (const [url, resourceType] of requests) {
  let answer
  globalThis.__before({ url, resourceType }, (a) => { answer = a })
  decisions.push({ url, resourceType, cancel: !!answer?.cancel })
}
const navigations = []
for (const event of ['will-navigate', 'will-redirect']) {
  for (const url of [`${origin}/a`, `${origin}/`, origin, 'https://example.com/', `${origin}x/`, 'about:blank', 'javascript:alert(1)', `${origin.replace('52103', '52104')}/`]) {
    let prevented = false
    globalThis.__on[event]({ preventDefault() { prevented = true } }, url)
    navigations.push({ event, url, prevented })
  }
}
let granted
globalThis.__permission(null, 'notifications', (g) => { granted = g })
const golden = {
  origin, decisions, navigations, refused: [...win.refused], fetched: [...win.fetched],
  windowOpen: globalThis.__open({ url: 'https://example.com/' }), permissionGranted: granted,
  windowOptions: { show: globalThis.__windowOptions.show, sandbox: globalThis.__windowOptions.webPreferences.sandbox, backgroundThrottling: globalThis.__windowOptions.webPreferences.backgroundThrottling }
}
mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'rule.json'), JSON.stringify(golden, null, 1) + '\n')
console.log(`${decisions.length} requests (${decisions.filter((d) => d.cancel).length} refused), ${navigations.length} navigations`)
