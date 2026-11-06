import http from 'http'; import { readFile } from 'fs/promises'; import { join, extname } from 'path'
const [root, port] = process.argv.slice(2)
const types = { '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript', '.svg': 'image/svg+xml', '.png': 'image/png', '.webp': 'image/webp', '.jpg': 'image/jpeg', '.woff2': 'font/woff2', '.json': 'application/json' }
http.createServer(async (req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname)
  if (p.endsWith('/')) p += 'index.html'
  for (const cand of [p, p + '.html']) {
    try { const b = await readFile(join(root, cand)); res.writeHead(200, { 'content-type': types[extname(cand)] ?? 'application/octet-stream' }); return res.end(b) } catch {}
  }
  res.writeHead(404); res.end()
}).listen(Number(port), '127.0.0.1', () => console.log('serving', root, port))
