#!/usr/bin/env node
// Golden file for WebURL, made by Node's own WHATWG `URL` (the one QuartzControl's main process
// reads a webhook with): each case is an input and what `new URL()` answers, or that it throws.
// `beyond` marks the inputs WebURL leaves to Node on purpose (a host to decode or map, IPv6, an
// IPv4 address in another form); the Swift test expects `.unsupported` for exactly those.
//
//   Runtime/node/bin/node scripts/web-url-golden.mjs
import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'web-url')

const inputs = [
  'https://api.netlify.com/build_hooks/5f1a2b3c4d5e6f7a8b9c0d1e', 'https://webhook.site/0b7e6c1a-2f9d-4c3e-9a8b-7d6c5e4f3a2b',
  'https://api.cloudflare.com/client/v4/pages/webhooks/deploy_hooks/abcdef12-3456', 'https://API.Vercel.com/v1/integrations/deploy/prj_x/AbCdEf',
  'HTTPS://Example.COM:443/a', 'https://example.com:8443/a?b=c#d', 'https://example.com:0443/x', 'https://example.com:00000443/x',
  'https://example.com:65535/', 'https://example.com:65536/', 'https://example.com:/x', 'https://example.com:12a/', 'https://example.com:0/',
  'http://example.com:80/', 'http://example.com:443/', 'https://u:p@example.com/hook', 'https://u@example.com', 'https://:p@example.com',
  'https://:@example.com', 'https://@example.com', 'https://a@b@example.com/x', 'https://a:b:c@example.com', 'https://us er:pa ss@example.com',
  'https://user@', 'https://', 'https:', 'https:example.com/x', 'https:/example.com', 'https:///example.com', 'https:\\\\example.com\\a\\b',
  '  https://example.com/x  ', '\thttps://exa\nmple.com/a\tb', 'https://example.com', 'https://example.com?q', 'https://example.com#f',
  'https://example.com/?', 'https://example.com/#', 'https://example.com/a/./b/../c', 'https://example.com/a/%2e/b/%2E%2e/c',
  'https://example.com/a/..', 'https://example.com/a/.', 'https://example.com/a b/c"d<e>f^g`h{i}j|k', 'https://example.com/ä/ö?ü=1#ß',
  'https://example.com/?a=1&b=two+words&c=%C3%A4&d&=e&f=%zz&g=%E2%82', "https://example.com/?q='x'&r=\"y\"", 'https://example.com/#a b"c<d>e`f',
  'https://example.com/%41%2f', 'https://example.com/a?b?c#d#e', 'https://exa mple.com/', 'https://exa<mple.com/', 'https://exa^mple.com',
  'https://exa|mple.com', 'https://exam_ple.com/', 'https://example.com./x', 'https://a..b.com/', 'https://xn--bcher-kva.de/',
  'https://127.0.0.1/hook', 'https://127.0.0.1:8441/x', 'https://192.168.64.2/', 'https://255.255.255.255/', 'https://256.0.0.1/',
  'https://1.2.3/', 'https://0x7f.1/', 'https://010.0.0.1/', 'https://1.2.3.4./', 'https://example.123/', 'https://123.example/',
  'https://bücher.de/', 'https://BÜCHER.de/', 'https://ex%41mple.com/', 'https://[::1]/', 'https://[2001:db8::1]:8443/x',
  'https://ｇithub.com/', 'http://example.com/', 'ws://example.com/', 'wss://example.com:443/', 'ftp://example.com:21/x',
  'mailto:hook@example.com', 'file:///etc/passwd', 'javascript:alert(1)', 'data:text/plain,x', 'example.com/hook', '//example.com/hook',
  '', ' ', 'h ttps://example.com', '1https://example.com', 'https://example.com/\u0000', 'https://exa\u0001mple.com/',
  'https://example.com/%', 'https://example.com/?a=%2B+b', 'https://example.com:8443', 'HTTPS://EXAMPLE.COM/PATH?QUERY#FRAG',
]
const beyond = new Set(['https://bücher.de/', 'https://BÜCHER.de/', 'https://ex%41mple.com/', 'https://[::1]/', 'https://[2001:db8::1]:8443/x',
  'https://ｇithub.com/', 'https://1.2.3/', 'https://0x7f.1/', 'https://010.0.0.1/', 'https://256.0.0.1/', 'https://example.123/'])
const special = new Set(['http:', 'https:', 'ws:', 'wss:', 'ftp:'])
const cases = inputs.map((input) => {
  let url
  try {
    url = new URL(input)
  } catch {
    return { input, throws: true, beyond: beyond.has(input) }
  }
  if (!special.has(url.protocol)) return { input, protocol: url.protocol, beyond: beyond.has(input) }
  return {
    input, beyond: beyond.has(input), protocol: url.protocol, username: url.username, password: url.password, hostname: url.hostname,
    port: url.port, pathname: url.pathname, search: url.search, hash: url.hash, origin: url.origin, href: url.href,
    searchParams: [...url.searchParams.values()]
  }
})
mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'cases.json'), JSON.stringify(cases, null, 1) + '\n')
console.log(`${cases.length} cases`)
