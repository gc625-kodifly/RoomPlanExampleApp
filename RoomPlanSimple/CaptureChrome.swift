/*
See LICENSE folder for this sample's licensing information.

Abstract:
Shared capture-session chrome so room and point-cloud modes stay aligned.
*/

import UIKit

enum CaptureChrome {

    static let controlSize: CGFloat = 56
    static let compactControlSize: CGFloat = 48

    static func circleButton(systemName: String, diameter: CGFloat = compactControlSize) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = .white
        button.backgroundColor = SpatialSenseTheme.Color.overlayStrong
        button.layer.cornerRadius = diameter / 2
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        button.widthAnchor.constraint(equalToConstant: diameter).isActive = true
        button.heightAnchor.constraint(equalToConstant: diameter).isActive = true
        return button
    }

    static func statusLabel() -> UILabel {
        let label = SpatialSenseTheme.statusPillLabel()
        label.isHidden = false
        return label
    }

    /// Pins close top-leading, secondary bottom-leading, primary bottom-trailing.
    static func pin(
        close: UIView,
        secondary: UIView,
        primary: UIView,
        in view: UIView
    ) {
        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            close.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),

            secondary.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            secondary.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            secondary.widthAnchor.constraint(equalToConstant: controlSize),
            secondary.heightAnchor.constraint(equalToConstant: controlSize),

            primary.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            primary.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            primary.heightAnchor.constraint(equalToConstant: controlSize),
            primary.widthAnchor.constraint(greaterThanOrEqualToConstant: 120)
        ])
    }
}
