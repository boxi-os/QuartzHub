import QuartzHubCore
import SwiftUI

/// „Im Handbuch nachlesen“: the handbook's chapter for a place (QuartzControl's `HandbookLink.tsx`).
/// The place is a key of `Handbook.pages`; the app's language picks the German or the English
/// chapter, because the handbook translates its paths too.
struct HandbookLink: View {
  let place: String?
  var title: String = L10n.t("common.handbookFor")
  /// Off among other plain links (the Projects window), on alone (the inspector).
  var showsIcon = true

  var body: some View {
    Link(destination: Handbook.url(for: place, language: L10n.language)) {
      if showsIcon { Label(title, systemImage: "book") } else { Text(title) }
    }
    .help(Handbook.url(for: place, language: L10n.language).absoluteString)
    .accessibilityIdentifier("handbook.link")
  }
}
