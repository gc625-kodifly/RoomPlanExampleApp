/*
See LICENSE folder for this sample's licensing information.

Abstract:
Polycam-style capture card: full-bleed preview with readable title bar.
*/

import UIKit

final class ScanCardView: UIView {

    var onTap: (() -> Void)?
    var onOverflow: (() -> Void)?

    private let container = UIView()
    private let thumbnailView = UIImageView()
    private let iconFallback = UIImageView()
    private let textBar = UIView()
    private let titleLabel = UILabel()
    private let dateLabel = UILabel()
    private let summaryLabel = UILabel()
    private let overflowButton = UIButton(type: .system)
    private let tapButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        container.translatesAutoresizingMaskIntoConstraints = false
        SpatialSenseTheme.applyStudioCardChrome(to: container)
        container.clipsToBounds = true
        addSubview(container)

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.backgroundColor = SpatialSenseTheme.Color.studioSurfaceRaised
        thumbnailView.clipsToBounds = true
        container.addSubview(thumbnailView)

        iconFallback.translatesAutoresizingMaskIntoConstraints = false
        iconFallback.image = UIImage(systemName: "viewfinder")
        iconFallback.tintColor = SpatialSenseTheme.Color.primary
        iconFallback.contentMode = .scaleAspectFit
        iconFallback.isHidden = true
        thumbnailView.addSubview(iconFallback)

        textBar.translatesAutoresizingMaskIntoConstraints = false
        textBar.backgroundColor = UIColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 0.94)
        container.addSubview(textBar)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = SpatialSenseTheme.Font.semibold(16)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1

        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = SpatialSenseTheme.Font.caption
        dateLabel.textColor = UIColor.white.withAlphaComponent(0.72)

        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.font = SpatialSenseTheme.Font.caption
        summaryLabel.textColor = UIColor.white.withAlphaComponent(0.58)
        summaryLabel.numberOfLines = 1

        let textStack = UIStackView(arrangedSubviews: [titleLabel, dateLabel, summaryLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 2
        textBar.addSubview(textStack)

        var overflowConfig = UIButton.Configuration.plain()
        overflowConfig.image = UIImage(systemName: "ellipsis")
        overflowConfig.baseForegroundColor = UIColor.white.withAlphaComponent(0.85)
        overflowButton.configuration = overflowConfig
        overflowButton.translatesAutoresizingMaskIntoConstraints = false
        overflowButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        overflowButton.layer.cornerRadius = 16
        overflowButton.clipsToBounds = true
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

            thumbnailView.topAnchor.constraint(equalTo: container.topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: textBar.topAnchor),
            thumbnailView.heightAnchor.constraint(equalToConstant: 132),

            iconFallback.centerXAnchor.constraint(equalTo: thumbnailView.centerXAnchor),
            iconFallback.centerYAnchor.constraint(equalTo: thumbnailView.centerYAnchor),
            iconFallback.widthAnchor.constraint(equalToConstant: 36),
            iconFallback.heightAnchor.constraint(equalToConstant: 36),

            textBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            textBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            textBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            textStack.topAnchor.constraint(equalTo: textBar.topAnchor, constant: 10),
            textStack.leadingAnchor.constraint(equalTo: textBar.leadingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: textBar.trailingAnchor, constant: -12),
            textStack.bottomAnchor.constraint(equalTo: textBar.bottomAnchor, constant: -10),

            overflowButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            overflowButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            overflowButton.widthAnchor.constraint(equalToConstant: 32),
            overflowButton.heightAnchor.constraint(equalToConstant: 32),

            tapButton.topAnchor.constraint(equalTo: container.topAnchor),
            tapButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tapButton.trailingAnchor.constraint(equalTo: overflowButton.leadingAnchor),
            tapButton.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    func configure(with room: SavedRoom, statusText: String? = nil, showsOverflow: Bool = true) {
        titleLabel.text = room.name
        dateLabel.text = room.formattedDate
        if !room.dimensionsSummary.isEmpty {
            summaryLabel.text = room.dimensionsSummary
            summaryLabel.isHidden = false
        } else if room.floorArea > 0 {
            summaryLabel.text = L10n.SavedRooms.area.localized(room.floorArea)
            summaryLabel.isHidden = false
        } else {
            summaryLabel.isHidden = true
        }
        overflowButton.isHidden = !showsOverflow

        if let image = RoomStorageManager.shared.getFloorPlanImage(for: room) {
            thumbnailView.image = image
            thumbnailView.backgroundColor = FloorPlanStyle.paper
            iconFallback.isHidden = true
        } else {
            thumbnailView.image = nil
            thumbnailView.backgroundColor = SpatialSenseTheme.Color.studioSurfaceRaised
            iconFallback.isHidden = false
        }

        let a11yStatus = statusText ?? ""
        accessibilityLabel = [room.name, room.formattedDate, a11yStatus]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        isAccessibilityElement = false
        tapButton.isAccessibilityElement = true
        tapButton.accessibilityLabel = accessibilityLabel
        tapButton.accessibilityTraits = .button
    }

    func configure(with pointCloud: SavedPointCloud, showsOverflow: Bool = true) {
        titleLabel.text = pointCloud.name
        dateLabel.text = pointCloud.formattedDate
        if pointCloud.pointCount > 0 {
            summaryLabel.text = "\(pointCloud.pointCount.formatted()) points"
            summaryLabel.isHidden = false
        } else {
            summaryLabel.isHidden = true
        }
        overflowButton.isHidden = !showsOverflow

        if let image = PointCloudStorageManager.shared.previewImage(for: pointCloud) {
            thumbnailView.image = image
            thumbnailView.backgroundColor = SpatialSenseTheme.Color.studioBackground
            iconFallback.isHidden = true
        } else {
            thumbnailView.image = nil
            thumbnailView.backgroundColor = SpatialSenseTheme.Color.studioSurfaceRaised
            iconFallback.image = UIImage(systemName: "point.3.connected.trianglepath.dotted")
            iconFallback.isHidden = false
        }

        accessibilityLabel = "\(pointCloud.name), \(pointCloud.formattedDate), point cloud"
        isAccessibilityElement = false
        tapButton.isAccessibilityElement = true
        tapButton.accessibilityLabel = accessibilityLabel
        tapButton.accessibilityTraits = .button
    }

    func setSelectedStyle(_ selected: Bool) {
        container.layer.borderColor = (selected
            ? SpatialSenseTheme.Color.borderSelected
            : SpatialSenseTheme.Color.studioBorder).cgColor
        container.layer.borderWidth = selected ? 2 : 1
    }

    @objc private func cardTapped() { onTap?() }
    @objc private func overflowTapped() { onOverflow?() }
}
