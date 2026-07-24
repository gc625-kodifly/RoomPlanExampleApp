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

    private let blueprintBackground = BlueprintBackgroundView()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let capturesStack = UIStackView()
    private let countLabel = UILabel()
    private let emptyState = UIView()
    private let scanButton = UIButton(type: .system)
    private var lastRenderedColumnCount = 0

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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let columnCount = preferredColumnCount
        if columnCount != lastRenderedColumnCount, !savedRooms.isEmpty || !savedPointClouds.isEmpty {
            reloadCaptures()
        }
    }

    private func setupUI() {
        view.backgroundColor = SpatialSenseTheme.Color.studioBackground
        overrideUserInterfaceStyle = .dark

        blueprintBackground.translatesAutoresizingMaskIntoConstraints = false
        blueprintBackground.variant = .darkStudio
        blueprintBackground.gridSpacing = 36
        view.addSubview(blueprintBackground)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        view.addSubview(scrollView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 20
        scrollView.addSubview(contentStack)

        let topBar = makeTopBar()
        contentStack.addArrangedSubview(topBar)

        let heading = makeLibraryHeading()
        contentStack.addArrangedSubview(heading)

        capturesStack.axis = .vertical
        capturesStack.spacing = 16
        contentStack.addArrangedSubview(capturesStack)

        setupEmptyState()
        contentStack.addArrangedSubview(emptyState)

        let dock = makeBottomDock()
        view.addSubview(dock)

        NSLayoutConstraint.activate([
            blueprintBackground.topAnchor.constraint(equalTo: view.topAnchor),
            blueprintBackground.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blueprintBackground.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blueprintBackground.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: dock.topAnchor, constant: -8),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32),

            dock.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            dock.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            dock.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            dock.heightAnchor.constraint(equalToConstant: 64)
        ])
    }

    private func makeTopBar() -> UIView {
        let container = UIView()

        let mark = UIImageView(image: UIImage(named: "BrandMark"))
        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.contentMode = .scaleAspectFit
        mark.accessibilityIgnoresInvertColors = true

        let brand = UILabel()
        brand.translatesAutoresizingMaskIntoConstraints = false
        brand.text = L10n.Home.brandName.localized
        brand.font = SpatialSenseTheme.Font.semibold(20, relativeTo: .title3)
        brand.textColor = .white

        let help = makeRoundButton(icon: "questionmark")
        help.addTarget(self, action: #selector(showHelp), for: .touchUpInside)
        help.accessibilityLabel = L10n.Home.Help.title.localized

        container.addSubview(mark)
        container.addSubview(brand)
        container.addSubview(help)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 44),
            mark.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            mark.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            mark.widthAnchor.constraint(equalToConstant: 28),
            mark.heightAnchor.constraint(equalToConstant: 28),
            brand.leadingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 10),
            brand.centerYAnchor.constraint(equalTo: mark.centerYAnchor),
            help.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            help.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func makeLibraryHeading() -> UIView {
        let title = UILabel()
        title.text = L10n.Home.SavedRooms.title.localized
        title.font = SpatialSenseTheme.Font.semibold(28, relativeTo: .title1)
        title.textColor = .white

        countLabel.font = SpatialSenseTheme.Font.caption
        countLabel.textColor = UIColor.white.withAlphaComponent(0.42)
        countLabel.numberOfLines = 1

        let stack = UIStackView(arrangedSubviews: [title, countLabel])
        stack.axis = .vertical
        stack.spacing = 6
        return stack
    }

    private func setupEmptyState() {
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        emptyState.backgroundColor = .clear

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = L10n.Home.emptyStateTitle.localized
        title.font = SpatialSenseTheme.Font.semibold(17)
        title.textColor = .white

        let detail = UILabel()
        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.text = L10n.Home.capturesEmptyHint.localized
        detail.font = SpatialSenseTheme.Font.body
        detail.textColor = UIColor.white.withAlphaComponent(0.42)
        detail.textAlignment = .left
        detail.numberOfLines = 0

        emptyState.addSubview(title)
        emptyState.addSubview(detail)

        NSLayoutConstraint.activate([
            emptyState.heightAnchor.constraint(greaterThanOrEqualToConstant: 96),
            title.topAnchor.constraint(equalTo: emptyState.topAnchor, constant: 24),
            title.leadingAnchor.constraint(equalTo: emptyState.leadingAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            detail.leadingAnchor.constraint(equalTo: emptyState.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: emptyState.trailingAnchor),
            detail.bottomAnchor.constraint(equalTo: emptyState.bottomAnchor, constant: -8)
        ])
    }

    private func makeBottomDock() -> UIView {
        let dock = UIView()
        dock.translatesAutoresizingMaskIntoConstraints = false
        dock.backgroundColor = SpatialSenseTheme.Color.studioSurface.withAlphaComponent(0.92)
        dock.layer.cornerRadius = 18
        dock.layer.cornerCurve = .continuous
        dock.layer.borderWidth = 1
        dock.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor

        let library = makeDockButton(
            icon: "square.grid.2x2.fill",
            title: L10n.Home.libraryTab.localized,
            selected: true
        )
        library.addTarget(self, action: #selector(showSavedRooms), for: .touchUpInside)
        library.accessibilityIdentifier = "home.savedRooms"

        scanButton.translatesAutoresizingMaskIntoConstraints = false
        var scanConfig = UIButton.Configuration.filled()
        scanConfig.title = L10n.Home.NewScan.title.localized
        scanConfig.image = UIImage(systemName: "plus")
        scanConfig.imagePadding = 8
        scanConfig.baseBackgroundColor = SpatialSenseTheme.Color.primary
        scanConfig.baseForegroundColor = .white
        scanConfig.cornerStyle = .capsule
        scanConfig.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18)
        scanConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = SpatialSenseTheme.Font.semibold(15)
            return outgoing
        }
        scanButton.configuration = scanConfig
        scanButton.accessibilityIdentifier = "home.newScan.floating"
        scanButton.accessibilityLabel = L10n.Home.NewScan.title.localized
        scanButton.addTarget(self, action: #selector(startScan), for: .touchUpInside)

        let settings = makeDockButton(
            icon: "gearshape.fill",
            title: L10n.Settings.title.localized,
            selected: false
        )
        settings.addTarget(self, action: #selector(showSettings), for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [library, scanButton, settings])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .equalCentering
        dock.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: dock.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: dock.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: dock.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: dock.bottomAnchor, constant: -10),
            scanButton.heightAnchor.constraint(equalToConstant: 44)
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
            outgoing.font = SpatialSenseTheme.Font.caption
            return outgoing
        }
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.numberOfLines = 1
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.85
        button.widthAnchor.constraint(equalToConstant: 82).isActive = true
        return button
    }

    private func reloadCaptures() {
        savedRooms = RoomStorageManager.shared.getSavedRooms()
        savedPointClouds = PointCloudStorageManager.shared.getSavedPointClouds()
        let captures = (
            savedRooms.map(LibraryCaptureItem.room) +
            savedPointClouds.map(LibraryCaptureItem.pointCloud)
        ).sorted { $0.date > $1.date }

        if captures.isEmpty {
            countLabel.text = L10n.Home.capturesEmptyHint.localized
        } else {
            let noun = captures.count == 1
                ? L10n.Home.capturesCountOne.localized
                : L10n.Home.capturesCountMany.localized
            countLabel.text = String(format: L10n.Home.capturesCount.localized, captures.count, noun)
        }

        capturesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        emptyState.isHidden = !captures.isEmpty

        let visibleCaptures = Array(captures.prefix(6))
        let columnCount = preferredColumnCount
        lastRenderedColumnCount = columnCount
        var index = 0
        while index < visibleCaptures.count {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 16
            row.distribution = .fillEqually

            row.addArrangedSubview(makeCard(for: visibleCaptures[index]))
            if columnCount == 2, index + 1 < visibleCaptures.count {
                row.addArrangedSubview(makeCard(for: visibleCaptures[index + 1]))
            } else if columnCount == 2 {
                row.addArrangedSubview(UIView())
            }

            capturesStack.addArrangedSubview(row)
            index += columnCount
        }
    }

    private var preferredColumnCount: Int {
        view.bounds.width >= 700 ? 2 : 1
    }

    private func makeCard(for capture: LibraryCaptureItem) -> ScanCardView {
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
        card.configure(with: room)
        card.onTap = { [weak self] in self?.openRoom(room) }
        card.onOverflow = { [weak self] in self?.showRoomActions(for: room) }
        return card
    }

    private func checkDeviceCapability() {
        scanButton.accessibilityValue = RoomCaptureSession.isSupported
            ? "Room scan and point cloud available"
            : "Scanning is unavailable on this device"
    }

    @objc private func startScan() {
        // No title/message eyebrows. Actions speak for themselves.
        let sheet = UIAlertController(
            title: nil,
            message: nil,
            preferredStyle: .actionSheet
        )
        let roomAction = UIAlertAction(
            title: L10n.Scan.Sheet.room.localized,
            style: .default
        ) { [weak self] _ in
            self?.presentRoomScan()
        }
        roomAction.accessibilityIdentifier = "newScan.roomModel"
        roomAction.isEnabled = RoomCaptureSession.isSupported
        sheet.addAction(roomAction)

        let pointCloudSupported = ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
        let pointCloudAction = UIAlertAction(
            title: L10n.Scan.Sheet.pointCloud.localized,
            style: .default
        ) { [weak self] _ in
            self?.presentPointCloudScan()
        }
        pointCloudAction.accessibilityIdentifier = "newScan.pointCloud"
        pointCloudAction.isEnabled = pointCloudSupported
        sheet.addAction(pointCloudAction)

        if !RoomCaptureSession.isSupported || !pointCloudSupported {
            let unavailable = UIAlertAction(
                title: L10n.Scan.Sheet.lidarRequired.localized,
                style: .default
            )
            unavailable.isEnabled = false
            sheet.addAction(unavailable)
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
        sheet.addAction(UIAlertAction(title: L10n.Common.edit.localized, style: .default) { [weak self] _ in
            self?.renameRoom(room)
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

    private func renameRoom(_ room: SavedRoom) {
        let alert = UIAlertController(title: L10n.Common.edit.localized, message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = room.name
            field.placeholder = L10n.SavedRooms.roomNamePlaceholder.localized
            field.clearButtonMode = .whileEditing
            field.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: L10n.Common.cancel.localized, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.Common.save.localized, style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let typed = alert?.textFields?.first?.text?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !typed.isEmpty else { return }
            var updated = room
            updated.name = typed
            do {
                try RoomStorageManager.shared.updateRoom(updated)
                self.reloadCaptures()
            } catch {
                // Keep quiet; library still shows previous name.
            }
        })
        present(alert, animated: true)
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
        sheet.addAction(UIAlertAction(title: L10n.Common.edit.localized, style: .default) { [weak self] _ in
            self?.renamePointCloud(pointCloud)
        })
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

    private func renamePointCloud(_ pointCloud: SavedPointCloud) {
        let alert = UIAlertController(title: L10n.Common.edit.localized, message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = pointCloud.name
            field.placeholder = "Point cloud name"
            field.clearButtonMode = .whileEditing
            field.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: L10n.Common.cancel.localized, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.Common.save.localized, style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let typed = alert?.textFields?.first?.text?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !typed.isEmpty else { return }
            var updated = pointCloud
            updated.name = typed
            do {
                try PointCloudStorageManager.shared.update(updated)
                self.reloadCaptures()
            } catch {
                // Keep quiet; library still shows previous name.
            }
        })
        present(alert, animated: true)
    }

}
