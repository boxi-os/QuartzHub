# QuartzHub

*[English](README.md)*

Eine native macOS-App, mit der man [Quartz 5](https://quartz.jzhao.xyz/)-Websites verwaltet:
Konfiguration, Plugins, Layout, Stile, Vorschau und Build, Veröffentlichen und Export als PDF, ePub
und Offline-HTML. QuartzHub ist die Nachfolgerin von
[QuartzControl](https://github.com/boxi-os/QuartzControl) (Electron), geschrieben in Swift, und
liest dieselben Projekte.

**Fassung 1.0.0.** Die DMG gibt es unter [Releases](https://github.com/boxi-os/QuartzHub/releases/latest);
das [Handbuch](https://boxi-os.github.io/QuartzHub/) erklärt jedes Fenster und jede Seite. QuartzHub ist
nicht notarisiert: Der erste Start braucht „Dennoch öffnen“ unter Systemeinstellungen ▸ Datenschutz &
Sicherheit.

- macOS 26 oder neuer, Apple Silicon
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
