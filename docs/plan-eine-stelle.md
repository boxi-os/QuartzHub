# Plan: Jede Einstellung an einer Stelle (2026-11-16)

Anlass: Beim Ausprobieren des Randmenüs in gui-test hat der Nutzer `dividers` an drei Stellen gefunden
(Plugins ▸ Installiert, Plugins ▸ Navigationen, Layout ▸ Komponenten), und sie verhalten sich
verschieden: Die beiden Plugin-Reiter schreiben sofort, Layout erst mit „Speichern“. Der Nutzer:
„merkwürdig, dass man an drei Stellen dasselbe einstellen kann“. Entschieden ist nur, dass erst
dieser Plan kommt.

## Heute

| | Optionen | Platzierung | Speichern |
|---|---|---|---|
| **Plugins ▸ Installiert** (`PluginInspector`) | volles Formular (`OptionsForm`) | die rohen Felder (`position`, `priority`, `display`, `condition`, `group`, `groupOptions`) in einer Klappgruppe, dazu „Auf der Bühne zeigen“ | sofort |
| **Plugins ▸ Navigationen, Zusätzliche Inhalte, Formulare, Mehrsprachigkeit** | in Schritten | Schritt „Platz“ (`PlacementStep`, `LayoutEntries.place`) | sofort |
| **Layout ▸ Komponenten** (`ComponentInspector`) | volles Formular am Ende des Inspektors | Bereich, Früher/Später, Anzeige, Bedingung, Gruppe, `groupOptions`, Vorrat | mit der Seite („Speichern“) |

Jede Option eines Plugins lässt sich also an zwei Stellen einstellen (die vier eigenen Plugins an
drei), jede Platzierung an drei. Zwei Speicherarten für dieselbe Sache: Wer in Layout eine Option
ändert, sieht sie auf der Website erst nach „Speichern“, in Plugins sofort.

## Ziel

Jede Stelle hat ein Thema, und eine Einstellung steht dort, wo ihr Thema ist:

- **Plugins** ist für das, was ein Plugin tut: seine Optionen. Die vier eigenen Plugins in ihren
  Reitern (in Schritten), alle anderen in Installiert. Speichert sofort, wie heute.
- **Layout** ist für das, wo etwas steht: Bereich, Reihenfolge, Gruppe, Anzeige, Bedingung,
  Seitenarten. Speichert mit der Seite, wie heute, weil man dort umbaut und erst das Ergebnis
  schreiben will.

Wo eine Stelle etwas zeigt, das ihr nicht gehört, steht eine Zeile Zusammenfassung und ein Sprung
an die Stelle, der es gehört.

## Änderungen

### 1. Layout ▸ Komponenten: keine Optionen mehr

- Das `OptionsForm` am Ende von `ComponentInspector` fällt weg. An seiner Stelle ein Abschnitt
  „Optionen“ mit:
  - einer Zeile, was gesetzt ist („3 Optionen geändert“, bei den eigenen Plugins die Variante bzw.
    Art, z. B. „Randmenü“, „Datei“), aus denselben Quellen wie die Listen der Plugin-Reiter;
  - dem Knopf „Optionen bearbeiten“, der Plugins öffnet: bei quartz-navigations den Reiter
    Navigationen mit genau diesem Eintrag ausgewählt, bei quartz-layout-box Zusätzliche Inhalte, bei
    quartz-forms Formulare mit dem Layout-Formular (`layoutForm`), bei quartz-multilanguage
    Mehrsprachigkeit (Website), sonst Installiert mit dem Plugin ausgewählt.
- Hat die Layout-Seite Ungespeichertes, fragt der Sprung wie jedes Verlassen (`UnsavedGuard`).
- Die Bühne muss nach der Rückkehr zeigen, was Plugins geschrieben hat („Eine Seite besitzt ihr
  Dokument“: beim Erscheinen lesen). Beim Umsetzen nachmessen, nicht angenommen.

### 2. Plugins ▸ Installiert: die eigenen Plugins verweisen auf ihren Reiter

- Bei den vier eigenen Plugins zeigt der Inspektor statt des Formulars eine Zusammenfassung und
  „In Navigationen bearbeiten“ usw. Für alle anderen Plugins bleibt das Formular.
- Die rohe Platzierung (Klappgruppe „Platzierung“) fällt weg; stattdessen die Zeile, die sie heute
  zugeklappt schon zeigt (`placementSummary`), und „Auf der Bühne zeigen“ wie bisher.

**Offen:** Die rohen Felder sind heute der einzige Weg zu `priority` als Zahl und zu
`groupOptions.justify`, das Layout nicht anbietet. Vorschlag: `justify` kommt in Layouts
Gruppen-Abschnitt (dann fehlt nichts), `priority` als Zahl braucht niemand neben Früher/Später.

### 3. Der Platz-Schritt in den Plugin-Reitern bleibt

Er ist Teil des Einrichtens (`docs/plan-assistenten.md`): Wer eine Navigation anlegt, will sie
gleich an ihren Platz stellen und in der Vorschau sehen. Er schreibt sofort wie der ganze Reiter.
Unter ihm „Auf der Bühne zeigen“ für alles Weitere (Gruppe, Bedingung). Damit gibt es die
Platzierung an zwei Stellen, aber jede mit ihrem Anlass; die rohen Felder in Installiert, die
dritte Stelle, fallen weg.

### 4. Ein Sprung nach Plugins wie der nach Layout

- `OpenPluginsAction` neben `OpenLayoutAction` (`App/Shell/ProjectWindow.swift`) mit einem Ziel
  `(tab, Eintrag)`, übergeben über ein `PluginsHandOver` wie `LayoutHandOver`; die Plugins-Seite
  setzt Reiter und Auswahl (`navigations.selected`, `extraContent.selected` als Index,
  `forms.selected`, `plugins.selected`) beim Erscheinen.
- Ein Schritt im Verlauf (`history.send(.plugins, tab:)`), wie der Sprung nach Layout.

## Reihenfolge

1. Sprung nach Plugins (Punkt 4), mit UI-Test: aus Layout auf eine Navigation, der Reiter zeigt sie.
2. Layout ohne Optionen (Punkt 1), `justify` dazu.
3. Installiert (Punkt 2).
4. Handbuch: 4.x (Plugins) und 5.x (Layout) sagen, wo was eingestellt wird; Aufnahmen der beiden
   Inspektoren neu.

Je Schritt ein Commit mit Bau, `qh-check i18n`, Kerntests, Rauchtest und der App angesehen; neue
Texte über `scripts/strings.mjs`.

## Entscheidungen des Nutzers (2026-11-16)

1. Installiert behält bei den eigenen Plugins das Formular, zugeklappt als „Alle Optionen“; darüber
   die Zusammenfassung und der Sprung in den Reiter.
2. Die rohen Platzierungsfelder in Installiert fallen weg; `priority` als Zahl entfällt.
   `groupOptions.justify` braucht keinen Ersatz: Quartz' `Flex.tsx` schreibt es als `justify-self`,
   und das wirkt in einer Flex-Reihe nicht (beim Umsetzen gelesen, 2026-11-16).
