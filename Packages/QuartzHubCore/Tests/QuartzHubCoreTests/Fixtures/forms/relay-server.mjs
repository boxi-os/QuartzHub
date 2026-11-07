// A stand-in for the servers the relay probe meets, for scripts/relay-probe-golden.mjs and
// RelayProbeTests: one HTTP server on 127.0.0.1 that is also an HTTP proxy, so names like
// relay.test and other.test reach it without a resolver (QuartzControl's side sends them here as a
// proxy request, QuartzHub's URLSession through its proxy setting). The first path segment names
// the behaviour. Every request is noted (method, host, path with query, Origin); GET /__log on
// 127.0.0.1 answers the notes since the last call and clears them, GET /__reset clears the counters.
// Prints {"port":…} once it listens.
import { createServer } from 'node:http'

let log = []
let counts = {}
const json = (res, status, value) => {
  res.writeHead(status, { 'content-type': 'application/json' })
  res.end(JSON.stringify(value))
}
const page = (res, status, text, type = 'text/html') => {
  res.writeHead(status, { 'content-type': type })
  res.end(text)
}
// The header's bytes as UTF-8, as a server writes a non-ASCII Location (Node would send latin1).
const redirect = (res, status, location) => {
  res.writeHead(status, { location: Buffer.from(location, 'utf8').toString('latin1') })
  res.end()
}

const server = createServer((req, res) => {
  const proxied = /^https?:\/\//.test(req.url)
  const url = new URL(proxied ? req.url : `http://${req.headers.host}${req.url}`)
  const host = url.host
  const port = server.address().port
  if (!proxied && url.pathname === '/__log') return json(res, 200, log.splice(0))
  if (!proxied && url.pathname === '/__reset') { counts = {}; log = []; return json(res, 200, {}) }
  log.push({ method: req.method, host: host.replace(`:${port}`, ':@PORT@'), path: url.pathname + url.search, origin: req.headers.origin ?? null })
  const [, kind, ...rest] = url.pathname.split('/')
  const file = rest.join('/')
  const generation = url.searchParams.get('generation')
  counts[kind] = (counts[kind] ?? 0) + 1
  const query = url.search
  switch (kind) {
    case '': return page(res, 200, '<!doctype html><html><body>Willkommen</body></html>')
    case 'ok': return json(res, 200, { ok: true, stamp: 's1', ...(generation ? { generation } : {}), counters: true })
    case 'ok-nocounters': return json(res, 200, { ok: true, stamp: 's1', ...(generation ? { generation } : {}), counters: 'ja' })
    case 'ok-nostamp': return json(res, 200, { ok: true, generation })
    case 'ok-old': return json(res, 200, { ok: true, stamp: 's1', generation: 'alt', counters: false })
    case 'ok-late': return json(res, 200, { ok: true, stamp: 's1', generation: counts[kind] === 1 ? 'alt' : generation })
    case 'ok-status': return json(res, 201, { ok: true, stamp: 's1', generation })
    case 'unknown': return json(res, 400, { ok: false, error: 'unknown_form' })
    case 'origin': return json(res, 403, { ok: false, error: 'origin', message: `Origin nicht erlaubt: ${'ä'.repeat(296)}😀 und mehr` })
    case 'longerr': return json(res, 400, { ok: false, error: `${'e'.repeat(79)}😀rest`, message: 7 })
    case 'mbstring': return json(res, 500, { ok: false, error: 'mbstring_config' })
    case 'php500': return page(res, 500, '  \n')
    case 'host500': return page(res, 500, '<!doctype html><html><body><h1>Internal Server Error</h1></body></html>')
    case 'nophp':
      if (file === 'config.php') return page(res, 200, "<?php return ['secret' => 'x'];", 'text/plain')
      return page(res, 200, '<?php // quartz-forms relay', 'text/plain')
    case 'nophp-closed':
      if (file === 'config.php') return page(res, 403, 'Forbidden')
      return page(res, 200, '<?php // quartz-forms relay', 'text/plain')
    case 'fatal-html': return page(res, 200, "<br />\n<b>Fatal error</b>:  Uncaught Error: Failed opening required '/srv/www/forms/config.php' (include_path='.:/usr/share/php') in /srv/www/forms/send.php:12\nStack trace:\n#0 {main}\n  thrown in <b>/srv/www/forms/send.php</b> on line <b>12</b><br />\n")
    case 'warn-html': return page(res, 200, '<br />\n<b>Warning</b>:  Undefined variable $x in <b>/srv/send.php</b> on line <b>3</b><br />\n{"ok":true,"stamp":"s1"}')
    case 'warn-text': return page(res, 200, `PHP Deprecated:  Creation of dynamic property in /srv/send.php on line 9\n${JSON.stringify({ ok: true, stamp: 's1', generation })}`, 'text/plain')
    case 'fatal-text': return page(res, 500, `PHP Fatal error:  ${'x'.repeat(320)} in /srv/send.php:4\n`, 'text/plain')
    case 'host404-warning': return page(res, 404, '<!doctype html><html><body><p>Warning: Diese Seite gibt es nicht mehr in /alt/ on line 1</p></body></html>')
    case 'text404-warning': return page(res, 404, 'Warning: this page has moved to /new/\n', 'text/plain')
    case 'fpm': return page(res, 404, 'File not found.\n', 'text/plain')
    case 'notfound': return page(res, 404, '<!doctype html><title>404</title>')
    case 'big': return page(res, 200, 'x'.repeat(100 * 1024), 'text/plain')
    case 'bigjson': return page(res, 200, JSON.stringify({ ok: true, stamp: 's1', pad: 'y'.repeat(70 * 1024) }), 'application/json')
    case 'slowbody':
    case 'slowjson':
    case 'slowhtml': {
      res.writeHead(200, { 'content-type': kind === 'slowjson' ? 'application/json' : kind === 'slowhtml' ? 'text/html; charset=utf-8' : 'text/plain' })
      res.write('anfang')
      const timer = setInterval(() => res.write('.'), 300)
      res.on('close', () => clearInterval(timer))
      return
    }
    case 'silent': return
    case 'drop': return req.socket.destroy()
    case 'r301-same': return redirect(res, 301, `/ok/send.php${query}`)
    case 'r303-same': return redirect(res, 303, `/ok/send.php${query}`)
    case 'r307-same': return redirect(res, 307, `/ok/send.php${query}`)
    case 'r308-same-home': return redirect(res, 308, '/')
    case 'r307-same-home': return redirect(res, 307, '/?x=1')
    case 'r301-same-home': return redirect(res, 301, '/')
    case 'r302-cross-relay': return redirect(res, 302, `http://other.test/ok/send.php${query}`)
    case 'r308-cross-relay': return redirect(res, 308, `http://other.test/ok/send.php${query.replace(/&generation=[^&]*/, '')}`)
    case 'r302-cross-home': return redirect(res, 302, `http://other.test/${query}`)
    case 'r302-cross-api': return redirect(res, 302, 'http://other.test/unknown-api/x')
    case 'unknown-api': return json(res, 404, { ok: false, error: 'not_found' })
    case 'r302-cross-origin-refusal': return redirect(res, 302, `http://other.test/origin/send.php${query}`)
    case 'r301-to-local': return redirect(res, 301, `http://127.0.0.1:${port}/ok/send.php${query}`)
    case 'r301-to-hex': return redirect(res, 301, `http://0x7f000001:${port}/ok/send.php`)
    case 'r301-to-v6': return redirect(res, 301, `http://[::1]:${port}/ok/send.php`)
    case 'r301-to-lan': return redirect(res, 301, 'http://192.168.1.20/ok/send.php')
    case 'r302-chain': return redirect(res, 302, `http://other.test/r302-chain2/send.php${query}`)
    case 'r302-chain2': return redirect(res, 307, `http://relay.test/ok/send.php${query}`)
    case 'r302-long': return redirect(res, 302, `http://other.test/${'ü'.repeat(200)}?geheim=1`)
    case 'r302-cross-nostamp': return redirect(res, 302, 'http://other.test/ok-nostamp/send.php')
    case 'r302-away-and-back': return redirect(res, 302, 'http://other.test/r307-back/send.php')
    case 'r307-back': return redirect(res, 307, 'http://relay.test/ok/send.php')
    case 'r303-then-301': return redirect(res, 303, `/r301-same/send.php${query}`)
    case 'endless': {
      res.writeHead(200, { 'content-type': 'application/json' })
      const chunk = 'z'.repeat(16 * 1024)
      const timer = setInterval(() => res.write(chunk), 20)
      res.on('close', () => clearInterval(timer))
      return
    }
    case 'half':
      if (file === 'counters/qf-probe.count') return page(res, 200, 'quartz-forms relay probe 0', 'text/plain')
      return
    case 'cnt-probe':
      if (file === 'counters/qf-probe.count') return page(res, 200, 'quartz-forms relay probe 0', 'text/plain')
      return json(res, 200, { ok: true, stamp: 's1', generation })
    case 'cnt-ht':
      if (file === 'counters/.htaccess') return page(res, 200, '# quartz-forms relay: counters\nDeny from all\n', 'text/plain')
      if (file === 'counters/qf-probe.count') return page(res, 403, 'Forbidden')
      return json(res, 200, { ok: true, stamp: 's1', generation })
    case 'cnt-all200':
      if (file === 'send.php') return json(res, 200, { ok: true, stamp: 's1', generation })
      return page(res, 200, '<!doctype html><html><body>Start</body></html>')
    default: return page(res, 404, 'nichts')
  }
})
server.listen(0, '127.0.0.1', () => process.stdout.write(`${JSON.stringify({ port: server.address().port })}\n`))
