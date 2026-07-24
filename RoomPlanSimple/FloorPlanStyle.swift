/*
See LICENSE folder for this sample's licensing information.

Abstract:
Shared Polycam-inspired floor plan palette and drawing constants.
*/

import UIKit

enum FloorPlanStyle {
    static let paper = UIColor(red: 0.97, green: 0.975, blue: 0.98, alpha: 1)
    static let roomFill = UIColor(red: 0.94, green: 0.95, blue: 0.96, alpha: 1)
    /// Soft charcoal, not pure black (Polycam-like).
    static let wallFill = UIColor(red: 0.22, green: 0.24, blue: 0.27, alpha: 1)
    static let wallStroke = UIColor(red: 0.18, green: 0.20, blue: 0.23, alpha: 1)
    static let gridLine = UIColor(red: 0.55, green: 0.60, blue: 0.68, alpha: 0.08)
    static let gridLineMajor = UIColor(red: 0.48, green: 0.52, blue: 0.58, alpha: 0.14)
    static let dimension = UIColor(red: 0.45, green: 0.48, blue: 0.52, alpha: 1)
    static let symbolStroke = UIColor(red: 0.68, green: 0.70, blue: 0.73, alpha: 1)
    static let symbolFill = UIColor(red: 0.98, green: 0.985, blue: 0.99, alpha: 1)
    static let openingStroke = UIColor(red: 0.58, green: 0.62, blue: 0.66, alpha: 1)
    static let doorStroke = UIColor(red: 0.38, green: 0.40, blue: 0.44, alpha: 1)
    static let windowStroke = UIColor(red: 0.32, green: 0.50, blue: 0.72, alpha: 1)

    /// Canonical plan wall thickness in meters. All walls stroke at this width.
    static let wallThicknessMeters: CGFloat = 0.14
    static let gridSpacingPoints: CGFloat = 32
    /// Soft corner radius for furniture symbols.
    static let symbolCornerRadius: CGFloat = 8
}
