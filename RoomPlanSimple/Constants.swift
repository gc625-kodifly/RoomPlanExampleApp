/*
See LICENSE folder for this sample's licensing information.

Abstract:
Centralized constants and configuration values (Issue #19).
*/

import UIKit

// MARK: - App Constants (Issue #19)

enum AppConstants {

    // MARK: - UI Configuration

    enum UI {
        static let animationDuration: TimeInterval = 0.3
        static let statusLabelAutoHideDelay: TimeInterval = 2.0
        static let cornerRadius: CGFloat = SpatialSenseTheme.Radius.md
        static let statusLabelFontSize: CGFloat = 14.0
        static let statusLabelMinHeight: CGFloat = SpatialSenseTheme.Size.statusPillHeight
        static let statusLabelTopOffset: CGFloat = 50.0
        static let overlayAlpha: CGFloat = 0.55
        static let errorOverlayAlpha: CGFloat = 0.85
    }

    // MARK: - Colors (SpatialSense-aligned)

    enum Colors {
        static let overlayBackground = SpatialSenseTheme.Color.overlay
        static let errorBackground = SpatialSenseTheme.Color.errorOverlay
        static let activeNavBarTint = SpatialSenseTheme.Color.textOnInverse
        static let completeNavBarTint = SpatialSenseTheme.Color.primary
        static let primary = SpatialSenseTheme.Color.primary
        static let canvas = SpatialSenseTheme.Color.canvas
        static let navDark = SpatialSenseTheme.Color.navDark
    }

    // MARK: - Export Configuration

    enum Export {
        static let filePrefix = "Room"
        static let dateFormat = "yyyyMMdd_HHmmss"
        static let fileExtension = "usdz"
    }

    // MARK: - Strings (Localized)

    enum Strings {
        static var exportTitle: String { L10n.Export.title.localized }
        static var exportMessage: String { L10n.Export.chooseFormat.localized }
        static var errorTitle: String { L10n.Common.error.localized }
        static var cancelButton: String { L10n.Common.cancel.localized }
        static var okButton: String { L10n.Common.ok.localized }
        static var tryAgainButton: String { L10n.Export.tryAgain.localized }
        static var scanningStarted: String { L10n.Scan.started.localized }
        static var scanningFailed: String { L10n.Scan.failed.localized }
        static var scanEndedWithError: String { L10n.Scan.endedWithError.localized }
        static var noElementsDetected: String { L10n.Scan.noElementsDetected.localized }
        static var unsupportedDeviceTitle: String { L10n.Alert.unsupportedDeviceTitle.localized }
        static var unsupportedDeviceMessage: String { L10n.Alert.unsupportedDeviceMessage.localized }
        static var deviceNotSupported: String { L10n.Scan.Error.deviceNotSupported.localized }
        static var unableToStartScanning: String { L10n.Alert.scanningUnavailable.localized }
    }
}
