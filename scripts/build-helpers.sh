#!/bin/sh
# Bündelt die JS-Helfer (Helpers/src) mit esbuild zu je einer CommonJS-Datei in Helpers/dist,
# mit dem Node aus Runtime/ (scripts/fetch-runtime.sh), damit der Bau nicht vom Node des Rechners
# abhängt. Die Pakete kommen aus Helpers/package-lock.json (npm ci).
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NODE_BIN="$ROOT/Runtime/node/bin"
[ -x "$NODE_BIN/node" ] || { echo "[helpers] Runtime/node fehlt: erst scripts/fetch-runtime.sh" >&2; exit 1; }
export PATH="$NODE_BIN:$PATH"
cd "$ROOT/Helpers"
if [ ! -d node_modules ] || [ package-lock.json -nt node_modules ]; then
  if [ -f package-lock.json ]; then npm ci --no-audit --no-fund; else npm install --no-audit --no-fund; fi
fi
rm -rf dist
for name in yaml-edit dts-schema; do
  node_modules/.bin/esbuild "src/$name.ts" --bundle --platform=node --target=node24 --format=cjs \
    --minify-syntax --legal-comments=eof --outfile="dist/$name.cjs" --log-level=warning
done
ls -la dist | sed -n '2,$p' >&2
