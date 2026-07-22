/*
See LICENSE folder for this sample's licensing information.

Abstract:
Capture-first SpatialSense library inspired by modern mobile 3D scanning apps.
*/

import UIKit
import RoomPlan
import ARKit

@MainActor
final class CaptureLibraryViewController: UIViewController {

    private enum LibraryCapture {
        case room(SavedRoom)
        case pointCloud(SavedPointCloud)

        var date: Date {
            switch self {
            case .room(let room): return room.date
            case .pointCloud(let pointCloud): return pointCloud.date
            }
        }
    }

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let capturesStack = UIStackView()
    private let countLabel = UILabel()
    private let emptyState = UIView()
    private let scanButton = UIButton(type: .system)

    private var savedRooms: [SavedRoom] = []
    private var savedPointClouds: [SavedPointCloud] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        checkDeviceCapability()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        reloadCaptures()
    }

    private func setupUI() {
        view.backgroundColor = SpatialSenseTheme.Color.studioBackground
        overrideUserInterfaceStyle = .dark

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 24
        scrollView.addSubview(contentStack)

        let topBar = makeTopBar()
        contentStack.addArrangedSubview(topBar)

        let heading = makeLibraryHeading()
        contentStack.addArrangedSubview(heading)

        let capturePrompt = makeCapturePrompt()
        contentStack.addArrangedSubview(capturePrompt)

        capturesStack.axis = .vertical
        capturesStack.spacing = 16
        contentStack.addArrangedSubview(capturesStack)

        setupEmptyState()
        contentStack.addArrangedSubview(emptyState)

        let dock = makeBottomDock()
        view.addSubview(dock)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: dock.topAnchor, constant: -8),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 18),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32),

            dock.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            dock.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            dock.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            dock.heightAnchor.constraint(equalToConstant: 78)
        ])
    }

    private func makeTopBar() -> UIView {
        let container = UIView()

        let mark = UIView()
        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.backgroundColor = SpatialSenseTheme.Color.primary
        mark.layer.cornerRadius = 12
        mark.layer.cornerCurve = .continuous

        let markIcon = UIImageView(image: UIImage(systemName: "square.stack.3d.up.fill"))
        markIcon.translatesAutoresizingMaskIntoConstraints = false
        markIcon.tintColor = .white
        markIcon.contentMode = .scaleAspectFit
        mark.addSubview(markIcon)

        let brand = UILabel()
        brand.translatesAutoresizingMaskIntoConstraints = false
        brand.text = "SpatialSense"
        brand.font = SpatialSenseTheme.Font.bold(22, relativeTo: .title2)
        brand.textColor = .white

        let help = makeRoundButton(icon: "questionmark")
        help.addTarget(self, action: #selector(showHelp), for: .touchUpInside)
        help.accessibilityLabel = L10n.Help.title.localized

        container.addSubview(mark)
        container.addSubview(brand)
        container.addSubview(help)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 48),
            mark.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            mark.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            mark.widthAnchor.constraint(equalToConstant: 42),
            mark.heightAnchor.constraint(equalToConstant: 42),
            markIcon.centerXAnchor.constraint(equalTo: mark.centerXAnchor),
            markIcon.centerYAnchor.constraint(equalTo: mark.centerYAnchor),
            markIcon.widthAnchor.constraint(equalToConstant: 23),
            markIcon.heightAnchor.constraint(equalToConstant: 23),
            brand.leadingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 12),
            brand.centerYAnchor.constraint(equalTo: mark.centerYAnchor),
            help.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            help.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func makeLibraryHeading() -> UIView {
        let title = UILabel()
        title.text = L10n.Home.SavedRooms.title.localized
        title.font = SpatialSenseTheme.Font.bold(32, relativeTo: .largeTitle)
        title.textColor = .white

        countLabel.font = SpatialSenseTheme.Font.body
        countLabel.textColor = UIColor.white.withAlphaComponent(0.48)

        let stack = UIStackView(arrangedSubviews: [title, countLabel])
        stack.axis = .vertical
        stack.spacing = 5
        return stack
    }

    private func makeCapturePrompt() -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = SpatialSenseTheme.Color.studioSurface
        card.layer.cornerRadius = 22
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = SpatialSenseTheme.Color.studioBorder.cgColor
        card.clipsToBounds = true

        let glow = UIView()
        glow.translatesAutoresizingMaskIntoConstraints = false
        glow.backgroundColor = SpatialSenseTheme.Color.primary.withAlphaComponent(0.16)
        glow.layer.cornerRadius = 70
        card.addSubview(glow)

        let iconTile = UIView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.backgroundColor = SpatialSenseTheme.Color.primary.withAlphaComponent(0.16)
        iconTile.layer.cornerRadius = 16
        iconTile.layer.cornerCurve = .continuous

        let icon = UIImageView(image: UIImage(systemName: "viewfinder"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = SpatialSenseTheme.Color.primary
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)
        iconTile.addSubview(icon)

        let eyebrow = UILabel()
        eyebrow.text = "LiDAR SPACE CAPTURE"
        eyebrow.font = SpatialSenseTheme.Font.semibold(11, relativeTo: .caption1)
        eyebrow.textColor = SpatialSenseTheme.Color.primary

        let title = UILabel()
        title.text = L10n.Home.NewScan.title.localized
        title.font = SpatialSenseTheme.Font.bold(25, relativeTo: .title2)
        title.textColor = .white

        let subtitle = UILabel()
        subtitle.text = L10n.Home.NewScan.subtitle.localized
        subtitle.font = SpatialSenseTheme.Font.body
        subtitle.textColor = UIColor.white.withAlphaComponent(0.58)
        subtitle.numberOfLines = 2

        let labels = UIStackView(arrangedSubviews: [eyebrow, title, subtitle])
        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.axis = .vertical
        labels.spacing = 5

        let arrow = UIImageView(image: UIImage(systemName: "arrow.up.right"))
        arrow.translatesAutoresizingMaskIntoConstraints = false
        arrow.tintColor = .white
        arrow.backgroundColor = SpatialSenseTheme.Color.primary
        arrow.layer.cornerRadius = 24
        arrow.contentMode = .center
        arrow.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)

        let tap = UIButton(type: .system)
        tap.translatesAutoresizingMaskIntoConstraints = false
        tap.accessibilityIdentifier = "home.newScan"
        tap.accessibilityLabel = L10n.Home.NewScan.title.localized
        tap.addTarget(self, action: #selector(startScan), for: .touchUpInside)

        card.addSubview(iconTile)
        card.addSubview(labels)
        card.addSubview(arrow)
        card.addSubview(tap)

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 154),
            glow.widthAnchor.constraint(equalToConstant: 140),
            glow.heightAnchor.constraint(equalToConstant: 140),
            glow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: 35),
            glow.topAnchor.constraint(equalTo: card.topAnchor, constant: -55),

            iconTile.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            iconTile.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 70),
            iconTile.heightAnchor.constraint(equalToConstant: 70),
            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),

            labels.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 18),
            labels.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: arrow.leadingAnchor, constant: -18),

            arrow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            arrow.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            arrow.widthAnchor.constraint(equalToConstant: 48),
            arrow.heightAnchor.constraint(equalToConstant: 48),

            tap.topAnchor.constraint(equalTo: card.topAnchor),
            tap.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            tap.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            tap.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])

        return card
    }

    private func setupEmptyState() {
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        emptyState.backgroundColor = SpatialSenseTheme.Color.studioSurface.withAlphaComponent(0.55)
        emptyState.layer.cornerRadius = 22
        emptyState.layer.cornerCurve = .continuous
        emptyState.layer.borderWidth = 1
        emptyState.layer.borderColor = SpatialSenseTheme.Color.studioBorder.cgColor

        let icon = UIImageView(image: UIImage(systemName: "cube.transparent"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = UIColor.white.withAlphaComponent(0.35)
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 38, weight: .light)

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = L10n.Home.emptyStateTitle.localized
        title.font = SpatialSenseTheme.Font.semibold(18)
        title.textColor = .white

        let detail = UILabel()
        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.text = L10n.Home.emptyState.localized
        detail.font = SpatialSenseTheme.Font.body
        detail.textColor = UIColor.white.withAlphaComponent(0.48)
        detail.textAlignment = .center
        detail.numberOfLines = 2

        emptyState.addSubview(icon)
        emptyState.addSubview(title)
        emptyState.addSubview(detail)

        NSLayoutConstraint.activate([
            emptyState.heightAnchor.constraint(equalToConstant: 200),
            icon.topAnchor.constraint(equalTo: emptyState.topAnchor, constant: 32),
            icon.centerXAnchor.constraint(equalTo: emptyState.centerXAnchor),
            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 18),
            title.centerXAnchor.constraint(equalTo: emptyState.centerXAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            detail.leadingAnchor.constraint(equalTo: emptyState.leadingAnchor, constant: 40),
            detail.trailingAnchor.constraint(equalTo: emptyState.trailingAnchor, constant: -40)
        ])
    }

    private func makeBottomDock() -> UIView {
        let dock = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        dock.translatesAutoresizingMaskIntoConstraints = false
        dock.layer.cornerRadius = 28
        dock.layer.cornerCurve = .continuous
        dock.clipsToBounds = true
        dock.layer.borderWidth = 1
        dock.layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor

        let library = makeDockButton(icon: "square.grid.2x2.fill", title: "Library", selected: true)
        library.addTarget(self, action: #selector(showSavedRooms), for: .touchUpInside)

        scanButton.translatesAutoresizingMaskIntoConstraints = false
        scanButton.backgroundColor = SpatialSenseTheme.Color.primary
        scanButton.tintColor = .white
        scanButton.setImage(UIImage(systemName: "plus"), for: .normal)
        scanButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 25, weight: .semibold),
            forImageIn: .normal
        )
        scanButton.layer.cornerRadius = 31
        scanButton.layer.cornerCurve = .continuous
        scanButton.layer.shadowColor = SpatialSenseTheme.Color.primary.cgColor
        scanButton.layer.shadowOpacity = 0.35
        scanButton.layer.shadowRadius = 14
        scanButton.layer.shadowOffset = CGSize(width: 0, height: 5)
        scanButton.accessibilityIdentifier = "home.newScan.floating"
        scanButton.accessibilityLabel = L10n.Home.NewScan.title.localized
        scanButton.addTarget(self, action: #selector(startScan), for: .touchUpInside)

        let settings = makeDockButton(icon: "gearshape.fill", title: L10n.Settings.title.localized, selected: false)
        settings.addTarget(self, action: #selector(showSettings), for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [library, scanButton, settings])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .equalCentering
        dock.contentView.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: dock.contentView.leadingAnchor, constant: 46),
            row.trailingAnchor.constraint(equalTo: dock.contentView.trailingAnchor, constant: -46),
            row.topAnchor.constraint(equalTo: dock.contentView.topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: dock.contentView.bottomAnchor, constant: -7),
            scanButton.widthAnchor.constraint(equalToConstant: 62),
            scanButton.heightAnchor.constraint(equalToConstant: 62)
        ])

        return dock
    }

    private func makeRoundButton(icon: String) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = SpatialSenseTheme.Color.studioSurfaceRaised
        button.tintColor = .white
        button.setImage(UIImage(systemName: icon), for: .normal)
        button.layer.cornerRadius = 20
        button.layer.cornerCurve = .continuous
        button.widthAnchor.constraint(equalToConstant: 40).isActive = true
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return button
    }

    private func makeDockButton(icon: String, title: String, selected: Bool) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: icon)
        configuration.title = title
        configuration.imagePlacement = .top
        configuration.imagePadding = 3
        configuration.baseForegroundColor = selected
            ? SpatialSenseTheme.Color.primary
            : UIColor.white.withAlphaComponent(0.48)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = SpatialSenseTheme.Font.medium(10, relativeTo: .caption2)
            return outgoing
        }
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 74).isActive = true
        return button
    }

    private func reloadCaptures() {
        savedRooms = RoomStorageManager.shared.getSavedRooms()
        savedPointClouds = PointCloudStorageManager.shared.getSavedPointClouds()
        let captures = (
            savedRooms.map(LibraryCapture.room) +
            savedPointClouds.map(LibraryCapture.pointCloud)
        ).sorted { $0.date > $1.date }

        countLabel.text = captures.isEmpty
            ? "Your LiDAR captures will appear here"
            : "\(captures.count) \(captures.count == 1 ? "capture" : "captures")"

        capturesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        emptyState.isHidden = !captures.isEmpty

        let visibleCaptures = Array(captures.prefix(6))
        var index = 0
        while index < visibleCaptures.count {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 16
            row.distribution = .fillEqually

            row.addArrangedSubview(makeCard(for: visibleCaptures[index]))
            if index + 1 < visibleCaptures.count {
                row.addArrangedSubview(makeCard(for: visibleCaptures[index + 1]))
            } else {
                row.addArrangedSubview(UIView())
            }

            capturesStack.addArrangedSubview(row)
            index += 2
        }
    }

    private func makeCard(for capture: LibraryCapture) -> ScanCardView {
        switch capture {
        case .room(let room):
            return makeCard(for: room)
        case .pointCloud(let pointCloud):
            let card = ScanCardView()
            card.configure(with: pointCloud)
            card.onTap = { [weak self] in self?.openPointCloud(pointCloud) }
            card.onOverflow = { [weak self] in self?.showPointCloudActions(for: pointCloud) }
            return card
        }
    }

    private func makeCard(for room: SavedRoom) -> ScanCardView {
        let card = ScanCardView()
        card.configure(with: room, statusText: L10n.Home.ScanStatus.ready.localized)
        card.onTap = { [weak self] in self?.openRoom(room) }
        card.onOverflow = { [weak self] in self?.showRoomActions(for: room) }
        return card
    }

    private func checkDeviceCapability() {
        guard !RoomCaptureSession.isSupported else { return }
        scanButton.isEnabled = false
        scanButton.alpha = 0.4
    }

    @objc private func startScan() {
        guard RoomCaptureSession.isSupported else {
            showUnsupportedDeviceAlert()
            return
        }

        let sheet = UIAlertController(
            title: "New Scan",
            message: "Choose the output you want to capture.",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "Room Model", style: .default) { [weak self] _ in
            self?.presentRoomScan()
        })

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            sheet.addAction(UIAlertAction(title: "PCD Point Cloud", style: .default) { [weak self] _ in
                self?.presentPointCloudScan()
            })
        }

        sheet.addAction(UIAlertAction(title: L10n.Common.cancel.localized, style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = scanButton
            popover.sourceRect = scanButton.bounds
        }
        present(sheet, animated: true)
    }

    private func presentRoomScan() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let controller = storyboard.instantiateViewController(
            withIdentifier: "RoomCaptureViewNavigationController"
        ) as? UINavigationController else { return }

        SpatialSenseTheme.configureNavigationBar(controller.navigationBar, immersive: true)
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }

    private func presentPointCloudScan() {
        let controller = PointCloudCaptureViewController()
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }

    @objc private func showSavedRooms() {
        let controller = SavedRoomsViewController()
        let navigation = UINavigationController(rootViewController: controller)
        SpatialSenseTheme.configureNavigationBar(navigation.navigationBar, immersive: true)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }

    @objc private func showSettings() {
        let controller = SettingsViewController(style: .insetGrouped)
        let navigation = UINavigationController(rootViewController: controller)
        SpatialSenseTheme.configureNavigationBar(navigation.navigationBar)
        present(navigation, animated: true)
    }

    @objc private func showHelp() {
        let controller = HelpViewController()
        let navigation = UINavigationController(rootViewController: controller)
        SpatialSenseTheme.configureNavigationBar(navigation.navigationBar)
        present(navigation, animated: true)
    }

    private func openRoom(_ room: SavedRoom) {
        let controller = RoomViewerViewController(savedRoom: room)
        let navigation = UINavigationController(rootViewController: controller)
        SpatialSenseTheme.configureNavigationBar(navigation.navigationBar, immersive: true)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }

    private func showRoomActions(for room: SavedRoom) {
        let sheet = UIAlertController(title: room.name, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: L10n.FloorPlan.view.localized, style: .default) { [weak self] _ in
            self?.openRoom(room)
        })
        sheet.addAction(UIAlertAction(title: L10n.Home.SavedRooms.title.localized, style: .default) { [weak self] _ in
            self?.showSavedRooms()
        })
        sheet.addAction(UIAlertAction(title: L10n.Common.cancel.localized, style: .cancel))
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(
            x: view.bounds.midX,
            y: view.bounds.midY,
            width: 1,
            height: 1
        )
        present(sheet, animated: true)
    }

    private func sharePointCloud(_ pointCloud: SavedPointCloud) {
        guard let url = try? PointCloudStorageManager.shared.fileURL(for: pointCloud) else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = view
        activity.popoverPresentationController?.sourceRect = CGRect(
            x: view.bounds.midX,
            y: view.bounds.midY,
            width: 1,
            height: 1
        )
        present(activity, animated: true)
    }

    private func openPointCloud(_ pointCloud: SavedPointCloud) {
        let controller = PointCloudViewerViewController(capture: pointCloud)
        let navigation = UINavigationController(rootViewController: controller)
        SpatialSenseTheme.configureNavigationBar(navigation.navigationBar, immersive: true)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }

    private func showPointCloudActions(for pointCloud: SavedPointCloud) {
        let sheet = UIAlertController(title: pointCloud.name, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Share PCD", style: .default) { [weak self] _ in
            self?.sharePointCloud(pointCloud)
        })
        sheet.addAction(UIAlertAction(title: L10n.Common.delete.localized, style: .destructive) { [weak self] _ in
            try? PointCloudStorageManager.shared.delete(pointCloud)
            self?.reloadCaptures()
        })
        sheet.addAction(UIAlertAction(title: L10n.Common.cancel.localized, style: .cancel))
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(
            x: view.bounds.midX,
            y: view.bounds.midY,
            width: 1,
            height: 1
        )
        present(sheet, animated: true)
    }

    private func showUnsupportedDeviceAlert() {
        let alert = UIAlertController(
            title: L10n.Alert.unsupportedDeviceTitle.localized,
            message: L10n.Alert.unsupportedDeviceMessage.localized,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Common.ok.localized, style: .default))
        present(alert, animated: true)
    }
}
