/*
See LICENSE folder for this sample's licensing information.

Abstract:
Native SpatialSense design tokens for the RoomPlan UIKit app.
*/

import UIKit

// MARK: - SpatialSense Theme

enum SpatialSenseTheme {

    // MARK: - Colors

    enum Color {
        /// Brand primary `#1677FF`
        static let primary = UIColor(red: 22 / 255, green: 119 / 255, blue: 255 / 255, alpha: 1)
        /// Dark primary for dark mode accents `#177DDC`
        static let primaryDark = UIColor(red: 23 / 255, green: 125 / 255, blue: 220 / 255, alpha: 1)
        /// Active plan / emphasis blue `#003EB3`
        static let primaryEmphasis = UIColor(red: 0 / 255, green: 62 / 255, blue: 179 / 255, alpha: 1)
        /// Soft primary fill `#E6F4FF`
        static let primarySoft = UIColor(red: 230 / 255, green: 244 / 255, blue: 255 / 255, alpha: 1)
        /// Pale blue layout canvas `#F0F5FF`
        static let canvas = UIColor(red: 240 / 255, green: 245 / 255, blue: 255 / 255, alpha: 1)
        /// Plan card / surface white
        static let surface = UIColor.white
        /// Elevated dark surface `#141414`
        static let surfaceElevated = UIColor(red: 20 / 255, green: 20 / 255, blue: 20 / 255, alpha: 1)
        /// Dark navigation / sider `#1F1F1F`
        static let navDark = UIColor(red: 31 / 255, green: 31 / 255, blue: 31 / 255, alpha: 1)
        /// Immersive black canvas
        static let immersive = UIColor.black
        static let studioBackground = UIColor(red: 11 / 255, green: 13 / 255, blue: 16 / 255, alpha: 1)
        static let studioSurface = UIColor(red: 21 / 255, green: 24 / 255, blue: 29 / 255, alpha: 1)
        static let studioSurfaceRaised = UIColor(red: 30 / 255, green: 34 / 255, blue: 41 / 255, alpha: 1)
        static let studioBorder = UIColor.white.withAlphaComponent(0.09)
        /// Text emphasis `#101828`
        static let textEmphasis = UIColor(red: 16 / 255, green: 24 / 255, blue: 40 / 255, alpha: 1)
        /// Secondary label for light surfaces
        static let textSecondary = UIColor(red: 16 / 255, green: 24 / 255, blue: 40 / 255, alpha: 0.55)
        /// On inverse / white text
        static let textOnInverse = UIColor.white
        /// Subtle border
        static let borderSubtle = UIColor.black.withAlphaComponent(0.06)
        /// Default border `#D9D9D9`
        static let border = UIColor(red: 217 / 255, green: 217 / 255, blue: 217 / 255, alpha: 1)
        /// Card hover border `#BAE0FF`
        static let borderHover = UIColor(red: 186 / 255, green: 224 / 255, blue: 255 / 255, alpha: 1)
        /// Selected card border `#91CAFF`
        static let borderSelected = UIColor(red: 145 / 255, green: 202 / 255, blue: 255 / 255, alpha: 1)
        /// Success muted bg `#D9F7BE`
        static let successMuted = UIColor(red: 217 / 255, green: 247 / 255, blue: 190 / 255, alpha: 1)
        /// Success muted text `#135200`
        static let successText = UIColor(red: 19 / 255, green: 82 / 255, blue: 0 / 255, alpha: 1)
        /// Destructive
        static let destructive = UIColor.systemRed
        /// Overlay for capture chrome
        static let overlay = UIColor.black.withAlphaComponent(0.55)
        /// Overlay strong
        static let overlayStrong = UIColor.black.withAlphaComponent(0.72)
        /// Error overlay
        static let errorOverlay = UIColor.systemRed.withAlphaComponent(0.85)
        /// Status pill background
        static let statusPill = UIColor(red: 17 / 255, green: 37 / 255, blue: 69 / 255, alpha: 0.92)
        /// Selected menu accent `#3C89E8`
        static let siderSelected = UIColor(red: 60 / 255, green: 137 / 255, blue: 232 / 255, alpha: 1)

        /// Adaptive canvas for light/dark system appearance.
        static var adaptiveCanvas: UIColor {
            UIColor { traits in
                traits.userInterfaceStyle == .dark ? surfaceElevated : canvas
            }
        }

        /// Adaptive card surface.
        static var adaptiveSurface: UIColor {
            UIColor { traits in
                traits.userInterfaceStyle == .dark ? UIColor(red: 28 / 255, green: 28 / 255, blue: 28 / 255, alpha: 1) : surface
            }
        }

        /// Adaptive primary text.
        static var adaptiveText: UIColor {
            UIColor { traits in
                traits.userInterfaceStyle == .dark ? textOnInverse.withAlphaComponent(0.92) : textEmphasis
            }
        }

        /// Adaptive secondary text.
        static var adaptiveSecondaryText: UIColor {
            UIColor { traits in
                traits.userInterfaceStyle == .dark ? textOnInverse.withAlphaComponent(0.55) : textSecondary
            }
        }

        /// Adaptive primary brand color.
        static var adaptivePrimary: UIColor {
            UIColor { traits in
                traits.userInterfaceStyle == .dark ? primaryDark : primary
            }
        }
    }

    // MARK: - Spacing

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: - Radius

    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let pill: CGFloat = 999
        static let card: CGFloat = 12
        static let button: CGFloat = 8
        static let control: CGFloat = 12
    }

    // MARK: - Size

    enum Size {
        static let minimumHitTarget: CGFloat = 44
        static let navbarHeight: CGFloat = 64
        static let controlButton: CGFloat = 52
        static let photoButton: CGFloat = 60
        static let cardMinHeight: CGFloat = 88
        static let thumbnail: CGFloat = 72
        static let iconTile: CGFloat = 40
        static let statusPillHeight: CGFloat = 32
        static let toolbarControl: CGFloat = 36
    }

    // MARK: - Typography

    enum Font {
        // Prefer Plus Jakarta when embedded; otherwise SF (system) keeps Dynamic Type honest.
        private static let brandFamily = "PlusJakartaSans-Regular"
        private static let brandFamilyBold = "PlusJakartaSans-Bold"
        private static let brandFamilySemiBold = "PlusJakartaSans-SemiBold"
        private static let brandFamilyMedium = "PlusJakartaSans-Medium"

        static func regular(_ size: CGFloat, relativeTo textStyle: UIFont.TextStyle = .body) -> UIFont {
            scaled(named: brandFamily, size: size, weight: .regular, relativeTo: textStyle)
        }

        static func medium(_ size: CGFloat, relativeTo textStyle: UIFont.TextStyle = .body) -> UIFont {
            scaled(named: brandFamilyMedium, size: size, weight: .medium, relativeTo: textStyle)
        }

        static func semibold(_ size: CGFloat, relativeTo textStyle: UIFont.TextStyle = .headline) -> UIFont {
            scaled(named: brandFamilySemiBold, size: size, weight: .semibold, relativeTo: textStyle)
        }

        static func bold(_ size: CGFloat, relativeTo textStyle: UIFont.TextStyle = .title2) -> UIFont {
            scaled(named: brandFamilyBold, size: size, weight: .bold, relativeTo: textStyle)
        }

        static var title: UIFont { bold(28, relativeTo: .largeTitle) }
        static var heading: UIFont { semibold(22, relativeTo: .title2) }
        static var subheading: UIFont { semibold(17, relativeTo: .headline) }
        static var body: UIFont { regular(15, relativeTo: .body) }
        static var caption: UIFont { regular(13, relativeTo: .footnote) }
        static var micro: UIFont { medium(11, relativeTo: .caption2) }
        static var button: UIFont { semibold(16, relativeTo: .headline) }

        private static func scaled(
            named name: String,
            size: CGFloat,
            weight: UIFont.Weight,
            relativeTo textStyle: UIFont.TextStyle
        ) -> UIFont {
            let base = UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: weight)
            return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
        }
    }

    // MARK: - Shadows

    enum Shadow {
        static let cardOpacity: Float = 0.08
        static let cardRadius: CGFloat = 8
        static let cardOffset = CGSize(width: 0, height: 2)
    }

    // MARK: - Factory helpers

    static func applyCardChrome(to view: UIView, elevated: Bool = true) {
        view.backgroundColor = Color.adaptiveSurface
        view.layer.cornerRadius = Radius.card
        view.layer.borderWidth = 1
        view.layer.borderColor = Color.borderSubtle.cgColor
        view.clipsToBounds = false
        if elevated {
            view.layer.shadowColor = UIColor.black.cgColor
            view.layer.shadowOpacity = Shadow.cardOpacity
            view.layer.shadowRadius = Shadow.cardRadius
            view.layer.shadowOffset = Shadow.cardOffset
        }
    }

    static func applyStudioCardChrome(to view: UIView) {
        view.backgroundColor = Color.studioSurface
        view.layer.cornerRadius = Radius.lg
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1
        view.layer.borderColor = Color.studioBorder.cgColor
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.24
        view.layer.shadowRadius = 16
        view.layer.shadowOffset = CGSize(width: 0, height: 8)
    }

    static func primaryButtonConfiguration(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil
    ) -> UIButton.Configuration {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = Color.primary
        config.baseForegroundColor = Color.textOnInverse
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(
            top: Space.md - 2,
            leading: Space.md,
            bottom: Space.md - 2,
            trailing: Space.md
        )

        var titleAttr = AttributedString(title)
        titleAttr.font = Font.button
        config.attributedTitle = titleAttr

        // Subtitles are discouraged in the product chrome. Keep optional for rare states only.
        if let subtitle, !subtitle.isEmpty {
            var subtitleAttr = AttributedString(subtitle)
            subtitleAttr.font = Font.caption
            config.attributedSubtitle = subtitleAttr
        }

        if let icon {
            config.image = UIImage(systemName: icon)
            config.imagePlacement = .leading
            config.imagePadding = Space.sm
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        }

        return config
    }

    static func secondaryButtonConfiguration(title: String, icon: String? = nil) -> UIButton.Configuration {
        var config = UIButton.Configuration.bordered()
        config.baseForegroundColor = Color.adaptivePrimary
        config.background.backgroundColor = Color.adaptiveSurface
        config.background.strokeColor = Color.border
        config.background.strokeWidth = 1
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(
            top: Space.sm + 2,
            leading: Space.md,
            bottom: Space.sm + 2,
            trailing: Space.md
        )

        var titleAttr = AttributedString(title)
        titleAttr.font = Font.semibold(14)
        config.attributedTitle = titleAttr

        if let icon {
            config.image = UIImage(systemName: icon)
            config.imagePlacement = .leading
            config.imagePadding = Space.sm
        }

        return config
    }

    static func circularControlButton(systemName: String, diameter: CGFloat = Size.controlButton) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = Color.textOnInverse
        button.backgroundColor = Color.overlay
        button.layer.cornerRadius = diameter / 2
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        button.widthAnchor.constraint(equalToConstant: diameter).isActive = true
        button.heightAnchor.constraint(equalToConstant: diameter).isActive = true
        return button
    }

    static func captureActionConfiguration(
        title: String,
        systemName: String
    ) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: systemName)
        configuration.imagePadding = Space.sm
        configuration.baseBackgroundColor = Color.primary
        configuration.baseForegroundColor = Color.textOnInverse
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 12,
            leading: Space.md,
            bottom: 12,
            trailing: Space.md
        )
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = Font.button
            return outgoing
        }
        return configuration
    }

    static func statusPillLabel() -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Font.medium(13, relativeTo: .footnote)
        label.textColor = Color.textOnInverse
        label.textAlignment = .center
        label.backgroundColor = Color.statusPill
        label.layer.cornerRadius = Radius.md
        label.clipsToBounds = true
        label.isHidden = true
        return label
    }

    static func configureNavigationBar(_ navigationBar: UINavigationBar, immersive: Bool = false) {
        let appearance = UINavigationBarAppearance()
        if immersive {
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = Color.navDark
            appearance.titleTextAttributes = [
                .foregroundColor: Color.textOnInverse,
                .font: Font.semibold(17)
            ]
            appearance.largeTitleTextAttributes = [
                .foregroundColor: Color.textOnInverse,
                .font: Font.bold(28)
            ]
            navigationBar.tintColor = Color.siderSelected
            navigationBar.overrideUserInterfaceStyle = .dark
        } else {
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = Color.adaptiveCanvas
            appearance.titleTextAttributes = [
                .foregroundColor: Color.adaptiveText,
                .font: Font.semibold(17)
            ]
            appearance.largeTitleTextAttributes = [
                .foregroundColor: Color.adaptiveText,
                .font: Font.bold(28)
            ]
            navigationBar.tintColor = Color.adaptivePrimary
            navigationBar.overrideUserInterfaceStyle = .unspecified
        }
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
    }

    static func applyBrandGradient(to layer: CALayer, bounds: CGRect) {
        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor(red: 37 / 255, green: 115 / 255, blue: 241 / 255, alpha: 1).cgColor,
            UIColor(red: 168 / 255, green: 168 / 255, blue: 168 / 255, alpha: 1).cgColor
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.frame = bounds
        layer.insertSublayer(gradient, at: 0)
    }
}

// MARK: - UIColor hex convenience

extension UIColor {
    convenience init(ssHex hex: String, alpha: CGFloat = 1.0) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if sanitized.hasPrefix("#") { sanitized.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&rgb)
        self.init(
            red: CGFloat((rgb & 0xFF0000) >> 16) / 255,
            green: CGFloat((rgb & 0x00FF00) >> 8) / 255,
            blue: CGFloat(rgb & 0x0000FF) / 255,
            alpha: alpha
        )
    }
}
