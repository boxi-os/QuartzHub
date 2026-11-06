# Messgeschirr des Prototyps

Die Skripte, mit denen am 2026-11-05 auf `spike/native-macos` (QuartzControl) gemessen wurde,
gesichert aus dem Scratchpad jener Sitzung. Sie laufen nicht aus diesem Ordner: Sie importieren aus
`QuartzControl/node_modules` (playwright-core, pdf-lib) und erwarten den Spike-Helfer. Sie stehen
hier als Rezept für dieselben Messungen an QuartzHub (Start bis Fenster, RSS, PDF-Lesezeichen und
Ziele, Bedienungshilfen).

- `drive.mjs` — Helfer wie die App starten, Kanäle aufrufen
- `measure.sh`, `winid.swift`, `owners.swift` — Start bis Fenster (CGWindowList), Speicher
- `ax.js`, `axpos.js` — Bedienungshilfen per JXA, Klick nach Position
- `pdfinfo.mjs`, `tocpages.mjs`, `chrome-pdf.mjs`, `serve.mjs` — PDF-Vergleich Chrome/WebKit
