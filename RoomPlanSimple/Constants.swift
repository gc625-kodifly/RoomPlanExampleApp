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
        static let cornerRadius: CGFloat = 8.0
        static let statusLabelFontSize: CGFloat = 14.0
        static let statusLabelMinHeight: CGFloat = 32.0
        static let statusLabelTopOffset: CGFloat = 50.0
        static let overlayAlpha: CGFloat = 0.6
        static let errorOverlayAlpha: CGFloat = 0.8
    }

    // MARK: - Colors

    enum Colors {
        static let overlayBackground = UIColor.black.withAlphaComponent(UI.overlayAlpha)
        static let errorBackground = UIColor.systemRed.withAlphaComponent(UI.errorOverlayAlpha)
        static let activeNavBarTint = UIColor.white
        static let completeNavBarTint = UIColor.systemBlue
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
