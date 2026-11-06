# QuartzHub

*[English](README.md)*

Eine native macOS-App, mit der man [Quartz 5](https://quartz.jzhao.xyz/)-Websites verwaltet:
Konfiguration, Plugins, Layout, Stile, Vorschau und Build, Veröffentlichen und Export als PDF, ePub
und Offline-HTML. QuartzHub ist die Nachfolgerin von
[QuartzControl](https://github.com/boxi-os/QuartzControl) (Electron), geschrieben in Swift, und
liest dieselben Projekte.

**Stand:** in Entwicklung, nicht veröffentlicht. Das erste Release kommt, wenn QuartzHub alles kann,
was QuartzControl 1.3 kann. Bis dahin ist QuartzControl das Werkzeug.

- macOS 15 oder neuer, Apple Silicon
- Bringt ein eigenes Node.js (für Quartz) und git mit
- Lizenz: GPL-3.0-or-later

## Bauen

Braucht Xcode 27.

```sh
scripts/fetch-runtime.sh   # Node und git nach Runtime/ (gepinnt, mit Prüfsumme)
scripts/xcodegen.sh        # QuartzHub.xcodeproj aus project.yml (XcodeGen, lokal geholt)
open QuartzHub.xcodeproj   # oder: scripts/package.sh für App und DMG
```

QuartzHub steht in keiner Verbindung zu Quartz oder seinem Autor.
