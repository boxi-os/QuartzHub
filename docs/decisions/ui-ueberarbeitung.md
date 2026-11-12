# UI-Überarbeitung

Seit 2026-11-12. Das Konzept mit Mock-Fenster, Regeln und Aufnahmen des Stands davor ist eine private
Konzeptseite (Artifact „QuartzHub UI-Konzept“). Hier stehen die Entscheidungen und was beim Bau des
Prototyps (Branch `ui-ueberarbeitung`) gemessen wurde.

## Entscheidungen des Nutzers

- **Unterreiter bleiben im Inhalt**, als eine Komponente für alle vier Seiten (`PageTabs`), nicht in
  Seitenleiste oder Symbolleiste.
- **Mindest-macOS 26.** Liquid Glass gibt es dann überall, die neuen Toolbar-APIs (`ToolbarSpacer`,
  `.glassProminent`, `safeAreaBar`) brauchen kein `#available`.
- **Formulare im breiten Fenster: Variante C** („Erklärung daneben“). Ab etwa 900 pt Inhaltsbreite
  stehen Überschrift und Erklärung eines Abschnitts links, die Einstellungen rechts daneben; darunter
  eine Spalte. Verworfen: A (mittig, viel leere Fläche) und B (zwei Spalten, die Leserichtung springt).
  B bleibt möglich für Seiten mit zwei gleichwertigen Abschnitten.
- **Bewegung statt Sprüngen:** Wechsel an Breitengrenzen, Auf- und Zuklappen, Ein- und Ausblenden
  werden animiert; Seiten- und Reiterwechsel nicht.

## macOS 26 als Ziel

Gemessen am 2026-11-12 mit Xcode 27.1: Das Anheben brachte sechs neue Veraltet-Warnungen, alle
behoben. `Text + Text` ist seit macOS 26 veraltet (jetzt Interpolation von `Text` in `Text`), und
`posix_spawn_file_actions_addchdir_np` heißt jetzt ohne `_np`. Im Paket steht `.macOS("26.0")`, weil
`.v26` erst ab swift-tools-version 6.2 bekannt ist und das Paket auf 6.0 bleibt.
