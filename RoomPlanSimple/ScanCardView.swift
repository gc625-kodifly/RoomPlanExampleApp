/*
See LICENSE folder for this sample's licensing information.

Abstract:
SpatialSense-style scan/project card used on Home and Saved Rooms.
*/

import UIKit

final class ScanCardView: UIView {

    // MARK: - Callbacks

    var onTap: (() -> Void)?
    var onOverflow: (() -> Void)?

    // MARK: - UI

    private let container = UIView()
    private let thumbnailView = UIImageView()
    private let iconFallback = UIImageView()
    private let titleLabel = UILabel()
    private let dateLabel = UILabel()
    private let summaryLabel = UILabel()
    private let statusTag = UILabel()
    private let overflowButton = UIButton(type: .system)
    private let tapButton = UIButton(type: .system)

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // MARK: - Setup

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        container.translatesAutoresizingMaskIntoConstraints = false
        SpatialSenseTheme.applyStudioCardChrome(to: container)
        addSubview(container)

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.backgroundColor = SpatialSenseTheme.Color.studioSurfaceRaised
        thumbnailView.layer.cornerRadius = SpatialSenseTheme.Radius.lg
        thumbnailView.layer.cornerCurve = .continuous
        thumbnailView.clipsToBounds = true
        container.addSubview(thumbnailView)

        iconFallback.translatesAutoresizingMaskIntoConstraints = false
        iconFallback.image = UIImage(systemName: "viewfinder")
        iconFallback.tintColor = SpatialSenseTheme.Color.primary
        iconFallback.contentMode = .scaleAspectFit
        iconFallback.isHidden = true
        thumbnailView.addSubview(iconFallback)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = SpatialSenseTheme.Font.semibold(17)
        titleLabel.textColor = SpatialSenseTheme.Color.textOnInverse
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontForContentSizeCategory = true

        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = SpatialSenseTheme.Font.caption
        dateLabel.textColor = SpatialSenseTheme.Color.textOnInverse.withAlphaComponent(0.55)
        dateLabel.adjustsFontForContentSizeCategory = true

        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.font = SpatialSenseTheme.Font.caption
        summaryLabel.textColor = SpatialSenseTheme.Color.textOnInverse.withAlphaComponent(0.72)
        summaryLabel.numberOfLines = 2
        summaryLabel.adjustsFontForContentSizeCategory = true

        statusTag.translatesAutoresizingMaskIntoConstraints = false
        statusTag.font = SpatialSenseTheme.Font.caption
        statusTag.textColor = SpatialSenseTheme.Color.textOnInverse
        statusTag.backgroundColor = SpatialSenseTheme.Color.primary.withAlphaComponent(0.9)
        statusTag.layer.cornerRadius = 7
        statusTag.clipsToBounds = true
        statusTag.textAlignment = .center
        statusTag.setContentHuggingPriority(.required, for: .horizontal)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, dateLabel, summaryLabel, statusTag])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = SpatialSenseTheme.Space.xs
        textStack.alignment = .leading
        container.addSubview(textStack)

        var overflowConfig = UIButton.Configuration.plain()
        overflowConfig.image = UIImage(systemName: "ellipsis")
        overflowConfig.baseForegroundColor = SpatialSenseTheme.Color.textOnInverse.withAlphaComponent(0.75)
        overflowConfig.contentInsets = NSDirectionalEdgeInsets(
            top: SpatialSenseTheme.Space.sm,
            leading: SpatialSenseTheme.Space.sm,
            bottom: SpatialSenseTheme.Space.sm,
            trailing: SpatialSenseTheme.Space.sm
        )
        overflowButton.configuration = overflowConfig
        overflowButton.translatesAutoresizingMaskIntoConstraints = false
        overflowButton.addTarget(self, action: #selector(overflowTapped), for: .touchUpInside)
        overflowButton.accessibilityLabel = L10n.Common.edit.localized
        container.addSubview(overflowButton)

        tapButton.translatesAutoresizingMaskIntoConstraints = false
        tapButton.backgroundColor = .clear
        tapButton.addTarget(self, action: #selector(cardTapped), for: .touchUpInside)
        container.addSubview(tapButton)
        container.sendSubviewToBack(tapButton)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 152),

            thumbnailView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            thumbnailView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 122),
            thumbnailView.heightAnchor.constraint(equalToConstant: 122),
            thumbnailView.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor, constant: 14),
            thumbnailView.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -14),

            iconFallback.centerXAnchor.constraint(equalTo: thumbnailView.centerXAnchor),
            iconFallback.centerYAnchor.constraint(equalTo: thumbnailView.centerYAnchor),
            iconFallback.widthAnchor.constraint(equalToConstant: 38),
            iconFallback.heightAnchor.constraint(equalToConstant: 38),

            overflowButton.topAnchor.constraint(equalTo: container.topAnchor, constant: SpatialSenseTheme.Space.sm),
            overflowButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -SpatialSenseTheme.Space.sm),
            overflowButton.widthAnchor.constraint(equalToConstant: SpatialSenseTheme.Size.minimumHitTarget),
            overflowButton.heightAnchor.constraint(equalToConstant: SpatialSenseTheme.Size.minimumHitTarget),

            textStack.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: overflowButton.leadingAnchor, constant: -SpatialSenseTheme.Space.sm),
            textStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor, constant: SpatialSenseTheme.Space.md),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -SpatialSenseTheme.Space.md),

            statusTag.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            statusTag.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),

            tapButton.topAnchor.constraint(equalTo: container.topAnchor),
            tapButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tapButton.trailingAnchor.constraint(equalTo: overflowButton.leadingAnchor),
            tapButton.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        // Padding for status tag text
        statusTag.layoutMargins = UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
    }

    // MARK: - Configure

    func configure(with room: SavedRoom, statusText: String? = nil, showsOverflow: Bool = true) {
        titleLabel.text = room.name
        dateLabel.text = room.formattedDate

        var summaryParts: [String] = []
        if !room.summary.isEmpty { summaryParts.append(room.summary) }
        if !room.dimensionsSummary.isEmpty { summaryParts.append(room.dimensionsSummary) }
        summaryLabel.text = summaryParts.joined(separator: " · ")
        summaryLabel.isHidden = summaryParts.isEmpty

        let resolvedStatus = statusText ?? L10n.Home.ScanStatus.ready.localized
        statusTag.text = "  \(resolvedStatus)  "
        statusTag.isHidden = resolvedStatus.isEmpty

        overflowButton.isHidden = !showsOverflow

        if let image = RoomStorageManager.shared.getFloorPlanImage(for: room) {
            thumbnailView.image = image
            iconFallback.isHidden = true
        } else {
            thumbnailView.image = nil
            iconFallback.isHidden = false
        }

        accessibilityLabel = "\(room.name), \(room.formattedDate), \(resolvedStatus)"
        isAccessibilityElement = false
        tapButton.isAccessibilityElement = true
        tapButton.accessibilityLabel = accessibilityLabel
        tapButton.accessibilityTraits = .button
    }

    func configure(with pointCloud: SavedPointCloud, showsOverflow: Bool = true) {
        titleLabel.text = pointCloud.name
        dateLabel.text = pointCloud.formattedDate
        var details: [String] = []
        if pointCloud.pointCount > 0 {
            details.append("\(pointCloud.pointCount.formatted()) points")
        }
        if pointCloud.triangleCount > 0 {
            details.append("\(pointCloud.triangleCount.formatted()) triangles")
        }
        details.append(pointCloud.hasColor ? "Color PCD + PLY" : "PCD")
        summaryLabel.text = details.joined(separator: " · ")
        summaryLabel.isHidden = false
        statusTag.text = "  Point Cloud  "
        statusTag.isHidden = false
        overflowButton.isHidden = !showsOverflow
        thumbnailView.image = nil
        iconFallback.image = UIImage(systemName: "point.3.connected.trianglepath.dotted")
        iconFallback.isHidden = false

        accessibilityLabel = "\(pointCloud.name), \(pointCloud.formattedDate), point cloud"
        isAccessibilityElement = false
        tapButton.isAccessibilityElement = true
        tapButton.accessibilityLabel = accessibilityLabel
        tapButton.accessibilityTraits = .button
    }

    func setSelectedStyle(_ selected: Bool) {
        container.layer.borderColor = (selected
            ? SpatialSenseTheme.Color.borderSelected
            : SpatialSenseTheme.Color.borderSubtle).cgColor
        container.layer.borderWidth = selected ? 2 : 1
    }

    // MARK: - Actions

    @objc private func cardTapped() {
        onTap?()
    }

    @objc private func overflowTapped() {
        onOverflow?()
    }
}
