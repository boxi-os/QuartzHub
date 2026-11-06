// The one protocol of every helper: one JSON request on stdin, one JSON answer on stdout, then
// exit. Swift starts the helper per request (HelperRunner, Phase 3) with a deadline; there is no
// long-lived process to keep in sync (the spike's sidecar idled at 200 MB).
//
//   exit 0 + { ok: true, … }      answered
//   exit 0 + { ok: false, error } the request could not be answered (bad input, unreadable file)
//   anything else                 the helper itself broke; Swift reports it as such
export function runHelper(handle: (request: unknown) => Record<string, unknown> | Promise<Record<string, unknown>>): void {
  const chunks: Buffer[] = []
  process.stdin.on('data', (c: Buffer) => chunks.push(c))
  process.stdin.on('end', async () => {
    let answer: Record<string, unknown>
    try {
      const request: unknown = JSON.parse(Buffer.concat(chunks).toString('utf-8'))
      answer = { ok: true, ...(await handle(request)) }
    } catch (error) {
      answer = { ok: false, error: error instanceof Error ? error.message : String(error) }
    }
    process.stdout.write(JSON.stringify(answer))
  })
}
