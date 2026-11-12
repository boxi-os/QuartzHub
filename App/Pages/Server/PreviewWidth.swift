import QuartzHubCore
import SwiftUI

/// The width the preview is drawn at, per band (QuartzControl's `previewWidthPx`): real device
/// widths, a phone (390) and an iPad upright (820), pulled into the project's own bands; with a
/// mobile band up to 900, 820 is a phone. nil for Desktop, which renders at
/// `ScaledSite.desktopWidth`, wider than the tablet band.
enum PreviewWidth {
  enum Mode: String, CaseIterable, Identifiable {
    case desktop, tablet, mobile
    var id: String { rawValue }

    var title: String {
      switch self {
      case .desktop: L10n.t("buildServer.viewport.desktop")
      case .tablet: L10n.t("buildServer.viewport.tablet")
      case .mobile: L10n.t("buildServer.viewport.mobile")
      }
    }
  }

  static let phone = 390.0
  static let tabletPortrait = 820.0

  static func points(_ mode: Mode, widths: (tablet: Double, mobile: Double)) -> Double? {
    switch mode {
    case .desktop: nil
    case .mobile: min(phone, widths.mobile)
    case .tablet: max(min(tabletPortrait, widths.tablet), widths.mobile + 1)
    }
  }
}
