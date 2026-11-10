// An FTP session with QuartzControl's own client (basic-ftp 6.2.0), for QuartzHub's FTP adapter:
// FTPS as QuartzControl spoke it (explicit TLS, the data connections resuming the control
// connection's session, Node's certificate checks), the same commands, listings and error text.
//
// The one exception to protocol.ts: a deploy run is one session of many calls, so this helper
// lives for that run. One JSON object per line on stdin, `{ id, op, args }`, one answer per line
// on stdout, `{ id, ok: true, value }` or `{ id, ok: false, error: { ftp, code, message, nodeCode } }`
// (`ftp` for basic-ftp's FTPError: a reply of the server; `nodeCode` Node's code of anything else,
// which is all a refused connection to a host with several addresses says: Node's AggregateError
// has an empty message and the first attempt's code). It ends with "close" or the end of stdin.
import { createInterface } from 'node:readline'
import { Writable } from 'node:stream'
import { Client, FTPError } from 'basic-ftp'

const TIMEOUT_MS = 30_000
const client = new Client(TIMEOUT_MS)

type Args = Record<string, unknown>

async function run(op: string, a: Args): Promise<unknown> {
  switch (op) {
    case 'access': {
      await client.access({ host: a.host as string, port: a.port as number, user: a.user as string, password: a.password as string | undefined,
        secure: a.secure as boolean, ...(a.ca ? { secureOptions: { ca: a.ca as string } } : {}) })
      return null
    }
    case 'pwd': return client.pwd()
    case 'cd': await client.cd(a.path as string); return null
    case 'ensureDir': await client.ensureDir(a.path as string); return null
    case 'size': return client.size(a.path as string)
    case 'remove': await client.remove(a.path as string); return null
    case 'send': { const r = await client.send(a.command as string); return { code: r.code, message: r.message } }
    case 'uploadFrom': await client.uploadFrom(a.local as string, a.remote as string); return null
    case 'downloadTo': {
      const chunks: Buffer[] = []
      const sink = new Writable({ write(chunk: Buffer, _e, done) { chunks.push(chunk); done() } })
      await client.downloadTo(sink, a.path as string)
      return Buffer.concat(chunks).toString('base64')
    }
    case 'list':
      return (await client.list(a.path as string | undefined)).map((f) => ({
        name: f.name, type: f.type, isSymbolicLink: f.isSymbolicLink, isDirectory: f.isDirectory,
        permissions: f.permissions ? { user: f.permissions.user, group: f.permissions.group, world: f.permissions.world } : null
      }))
    case 'close': client.close(); return null
    default: throw new Error(`unknown op ${op}`)
  }
}

const lines = createInterface({ input: process.stdin })
let queue = Promise.resolve()
lines.on('line', (line) => {
  queue = queue.then(async () => {
    let request: { id: number; op: string; args?: Args }
    try {
      request = JSON.parse(line)
    } catch {
      return
    }
    try {
      const value = await run(request.op, request.args ?? {})
      process.stdout.write(`${JSON.stringify({ id: request.id, ok: true, value: value ?? null })}\n`)
    } catch (error) {
      const ftp = error instanceof FTPError
      process.stdout.write(`${JSON.stringify({ id: request.id, ok: false, error: {
        ftp, code: ftp ? (error as FTPError).code : null, message: error instanceof Error ? error.message : String(error), text: String(error),
        nodeCode: !ftp && typeof (error as { code?: unknown })?.code === 'string' ? (error as { code: string }).code : null
      } })}\n`)
    }
    if (request.op === 'close') process.exit(0)
  })
})
// The end of stdin ends the session after what is still queued.
lines.on('close', () => { queue = queue.then(() => { client.close(); process.exit(0) }) })
