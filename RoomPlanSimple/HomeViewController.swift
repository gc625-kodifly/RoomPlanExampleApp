//
//  HomeViewController.swift
//  RoomPlanSimple
//
//  SpatialSense-inspired workspace home screen
//

import UIKit
import RoomPlan
import ARKit

@MainActor
class HomeViewController: UIViewController {

    // MARK: - UI Components

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let brandHeader = UIView()
    private let brandMark = UIImageView()
    private let brandTitleLabel = UILabel()
    private let brandSubtitleLabel = UILabel()

    private let headingLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let newScanButton = UIButton(type: .system)
    private let pointCloudScanButton = UIButton(type: .system)
    private let secondaryActionsStack = UIStackView()

    private let recentHeaderStack = UIStackView()
    private let recentScansLabel = UILabel()
    private let viewAllButton = UIButton(type: .system)
    private let recentScansStack = UIStackView()
    private let emptyStateContainer = UIView()

    private var isStartingScan = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        checkDeviceCapability()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        if let navBar = navigationController?.navigationBar {
            SpatialSenseTheme.configureNavigationBar(navBar, immersive: false)
        }
        updateRecentScans()

        #if DEBUG
        RoomStorageManager.shared.debugStorageInfo()
        #endif
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = SpatialSenseTheme.Color.adaptiveCanvas
        title = L10n.Home.brandName.localized
        navigationItem.largeTitleDisplayMode = .never

        setupNavigationBar()
        setupScrollView()
        setupBrandHeader()
        setupHeading()
        setupActionButtons()
        setupRecentScans()
    }

    private func setupNavigationBar() {
        let settingsItem = UIBarButtonItem(
            image: UIImage(systemName: "gearshape.fill"),
            style: .plain,
            target: self,
            action: #selector(showSettings)
        )
        settingsItem.accessibilityLabel = L10n.Settings.title.localized

        let helpItem = UIBarButtonItem(
            image: UIImage(systemName: "questionmark.circle"),
            style: .plain,
            target: self,
            action: #selector(showHelp)
        )
        helpItem.accessibilityLabel = L10n.Help.title.localized

        navigationItem.rightBarButtonItems = [settingsItem, helpItem]
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = SpatialSenseTheme.Space.lg
        contentStack.alignment = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: SpatialSenseTheme.Space.md),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: SpatialSenseTheme.Space.md),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -SpatialSenseTheme.Space.md),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -SpatialSenseTheme.Space.lg),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -SpatialSenseTheme.Space.xl)
        ])
    }

    private func setupBrandHeader() {
        brandHeader.translatesAutoresizingMaskIntoConstraints = false
        brandHeader.backgroundColor = SpatialSenseTheme.Color.navDark
        brandHeader.layer.cornerRadius = SpatialSenseTheme.Radius.lg
        brandHeader.clipsToBounds = true

        brandMark.translatesAutoresizingMaskIntoConstraints = false
        brandMark.image = UIImage(systemName: "square.stack.3d.up.fill")
        brandMark.tintColor = SpatialSenseTheme.Color.siderSelected
        brandMark.contentMode = .scaleAspectFit

        brandTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        brandTitleLabel.text = L10n.Home.brandName.localized
        brandTitleLabel.font = SpatialSenseTheme.Font.semibold(18)
        brandTitleLabel.textColor = SpatialSenseTheme.Color.textOnInverse
        brandTitleLabel.adjustsFontForContentSizeCategory = true

        brandSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        brandSubtitleLabel.text = L10n.Home.header.localized
        brandSubtitleLabel.font = SpatialSenseTheme.Font.caption
        brandSubtitleLabel.textColor = SpatialSenseTheme.Color.textOnInverse.withAlphaComponent(0.7)
        brandSubtitleLabel.adjustsFontForContentSizeCategory = true

        let textStack = UIStackView(arrangedSubviews: [brandTitleLabel, brandSubtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        brandHeader.addSubview(brandMark)
        brandHeader.addSubview(textStack)
        contentStack.addArrangedSubview(brandHeader)

        NSLayoutConstraint.activate([
            brandHeader.heightAnchor.constraint(greaterThanOrEqualToConstant: 72),

            brandMark.leadingAnchor.constraint(equalTo: brandHeader.leadingAnchor, constant: SpatialSenseTheme.Space.md),
            brandMark.centerYAnchor.constraint(equalTo: brandHeader.centerYAnchor),
            brandMark.widthAnchor.constraint(equalToConstant: SpatialSenseTheme.Size.iconTile),
            brandMark.heightAnchor.constraint(equalToConstant: SpatialSenseTheme.Size.iconTile),

            textStack.leadingAnchor.constraint(equalTo: brandMark.trailingAnchor, constant: SpatialSenseTheme.Space.md),
            textStack.trailingAnchor.constraint(equalTo: brandHeader.trailingAnchor, constant: -SpatialSenseTheme.Space.md),
            textStack.centerYAnchor.constraint(equalTo: brandHeader.centerYAnchor)
        ])

        // Accent gradient strip at top of brand header
        let accent = UIView()
        accent.translatesAutoresizingMaskIntoConstraints = false
        accent.backgroundColor = SpatialSenseTheme.Color.primary
        brandHeader.addSubview(accent)
        NSLayoutConstraint.activate([
            accent.topAnchor.constraint(equalTo: brandHeader.topAnchor),
            accent.leadingAnchor.constraint(equalTo: brandHeader.leadingAnchor),
            accent.trailingAnchor.constraint(equalTo: brandHeader.trailingAnchor),
            accent.heightAnchor.constraint(equalToConstant: 3)
        ])
    }

    private func setupHeading() {
        headingLabel.text = L10n.Home.header.localized
        headingLabel.font = SpatialSenseTheme.Font.heading
        headingLabel.textColor = SpatialSenseTheme.Color.adaptiveText
        headingLabel.numberOfLines = 0
        headingLabel.adjustsFontForContentSizeCategory = true

        subtitleLabel.text = L10n.Home.subtitle.localized
        subtitleLabel.font = SpatialSenseTheme.Font.body
        subtitleLabel.textColor = SpatialSenseTheme.Color.adaptiveSecondaryText
        subtitleLabel.numberOfLines = 0
        subtitleLabel.adjustsFontForContentSizeCategory = true

        let headingStack = UIStackView(arrangedSubviews: [headingLabel, subtitleLabel])
        headingStack.axis = .vertical
        headingStack.spacing = SpatialSenseTheme.Space.sm
        contentStack.addArrangedSubview(headingStack)
    }

    private func setupActionButtons() {
        newScanButton.configuration = SpatialSenseTheme.primaryButtonConfiguration(
            title: L10n.Home.NewScan.title.localized,
            subtitle: L10n.Home.NewScan.subtitle.localized,
            icon: "plus.viewfinder"
        )
        newScanButton.translatesAutoresizingMaskIntoConstraints = false
        newScanButton.heightAnchor.constraint(equalToConstant: 80).isActive = true
        newScanButton.accessibilityIdentifier = "home.newScan"
        newScanButton.addTarget(self, action: #selector(startScan), for: .touchUpInside)

        pointCloudScanButton.configuration = SpatialSenseTheme.primaryButtonConfiguration(
            title: "Point Cloud Scan",
            subtitle: "Capture ARKit mesh vertices for PCD export",
            icon: "point.3.connected.trianglepath.dotted"
        )
        pointCloudScanButton.translatesAutoresizingMaskIntoConstraints = false
        pointCloudScanButton.heightAnchor.constraint(equalToConstant: 80).isActive = true
        pointCloudScanButton.accessibilityIdentifier = "home.pointCloudScan"
        pointCloudScanButton.addTarget(self, action: #selector(startPointCloudScan), for: .touchUpInside)

        let savedButton = UIButton(type: .system)
        savedButton.configuration = SpatialSenseTheme.secondaryButtonConfiguration(
            title: L10n.Home.SavedRooms.title.localized,
            icon: "square.stack.3d.up"
        )
        savedButton.accessibilityIdentifier = "home.savedRooms"
        savedButton.addTarget(self, action: #selector(showSavedRooms), for: .touchUpInside)

        let helpButton = UIButton(type: .system)
        helpButton.configuration = SpatialSenseTheme.secondaryButtonConfiguration(
            title: L10n.Home.Help.title.localized,
            icon: "questionmark.circle"
        )
        helpButton.addTarget(self, action: #selector(showHelp), for: .touchUpInside)

        secondaryActionsStack.axis = .horizontal
        secondaryActionsStack.spacing = SpatialSenseTheme.Space.sm
        secondaryActionsStack.distribution = .fillEqually
        secondaryActionsStack.addArrangedSubview(savedButton)
        secondaryActionsStack.addArrangedSubview(helpButton)

        let actionsStack = UIStackView(arrangedSubviews: [newScanButton, pointCloudScanButton, secondaryActionsStack])
        actionsStack.axis = .vertical
        actionsStack.spacing = SpatialSenseTheme.Space.md
        contentStack.addArrangedSubview(actionsStack)
    }

    private func setupRecentScans() {
        recentScansLabel.text = L10n.Home.recentScans.localized
        recentScansLabel.font = SpatialSenseTheme.Font.subheading
        recentScansLabel.textColor = SpatialSenseTheme.Color.adaptiveText
        recentScansLabel.adjustsFontForContentSizeCategory = true

        var viewAllConfig = UIButton.Configuration.plain()
        viewAllConfig.title = L10n.Home.viewAll.localized
        viewAllConfig.baseForegroundColor = SpatialSenseTheme.Color.adaptivePrimary
        viewAllConfig.contentInsets = .zero
        viewAllButton.configuration = viewAllConfig
        viewAllButton.titleLabel?.font = SpatialSenseTheme.Font.semibold(14)
        viewAllButton.addTarget(self, action: #selector(showSavedRooms), for: .touchUpInside)

        recentHeaderStack.axis = .horizontal
        recentHeaderStack.alignment = .center
        recentHeaderStack.distribution = .equalSpacing
        recentHeaderStack.addArrangedSubview(recentScansLabel)
        recentHeaderStack.addArrangedSubview(viewAllButton)
        contentStack.addArrangedSubview(recentHeaderStack)

        recentScansStack.axis = .vertical
        recentScansStack.spacing = SpatialSenseTheme.Space.md
        contentStack.addArrangedSubview(recentScansStack)

        setupEmptyState()
        contentStack.addArrangedSubview(emptyStateContainer)
    }

    private func setupEmptyState() {
        emptyStateContainer.translatesAutoresizingMaskIntoConstraints = false
        SpatialSenseTheme.applyCardChrome(to: emptyStateContainer)

        let icon = UIImageView(image: UIImage(systemName: "cube.transparent"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = SpatialSenseTheme.Color.adaptivePrimary
        icon.contentMode = .scaleAspectFit

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = L10n.Home.emptyStateTitle.localized
        title.font = SpatialSenseTheme.Font.subheading
        title.textColor = SpatialSenseTheme.Color.adaptiveText
        title.textAlignment = .center
        title.adjustsFontForContentSizeCategory = true

        let body = UILabel()
        body.translatesAutoresizingMaskIntoConstraints = false
        body.text = L10n.Home.emptyState.localized
        body.font = SpatialSenseTheme.Font.body
        body.textColor = SpatialSenseTheme.Color.adaptiveSecondaryText
        body.textAlignment = .center
        body.numberOfLines = 0
        body.adjustsFontForContentSizeCategory = true

        emptyStateContainer.addSubview(icon)
        emptyStateContainer.addSubview(title)
        emptyStateContainer.addSubview(body)

        NSLayoutConstraint.activate([
            emptyStateContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),

            icon.topAnchor.constraint(equalTo: emptyStateContainer.topAnchor, constant: SpatialSenseTheme.Space.lg),
            icon.centerXAnchor.constraint(equalTo: emptyStateContainer.centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 36),
            icon.heightAnchor.constraint(equalToConstant: 36),

            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: SpatialSenseTheme.Space.md),
            title.leadingAnchor.constraint(equalTo: emptyStateContainer.leadingAnchor, constant: SpatialSenseTheme.Space.lg),
            title.trailingAnchor.constraint(equalTo: emptyStateContainer.trailingAnchor, constant: -SpatialSenseTheme.Space.lg),

            body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: SpatialSenseTheme.Space.sm),
            body.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: emptyStateContainer.bottomAnchor, constant: -SpatialSenseTheme.Space.lg)
        ])
    }

    // MARK: - Recent Scans

    private func updateRecentScans() {
        recentScansStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let savedRooms = RoomStorageManager.shared.getSavedRooms()
        let recentRooms = Array(savedRooms.prefix(3))

        if recentRooms.isEmpty {
            recentHeaderStack.isHidden = true
            recentScansStack.isHidden = true
            emptyStateContainer.isHidden = false
        } else {
            recentHeaderStack.isHidden = false
            recentScansStack.isHidden = false
            emptyStateContainer.isHidden = true
            viewAllButton.isHidden = savedRooms.count <= 3

            for room in recentRooms {
                let card = ScanCardView()
                card.configure(with: room, statusText: L10n.Home.ScanStatus.local.localized)
                card.onTap = { [weak self] in
                    self?.openRoom(room)
                }
                card.onOverflow = { [weak self] in
                    self?.showRoomActions(for: room)
                }
                recentScansStack.addArrangedSubview(card)
            }
        }
    }

    // MARK: - Device Check

    private func checkDeviceCapability() {
        if !RoomCaptureSession.isSupported {
            newScanButton.isEnabled = false
            newScanButton.alpha = 0.55
            pointCloudScanButton.isEnabled = false
            pointCloudScanButton.alpha = 0.55
            var config = newScanButton.configuration
            config?.attributedSubtitle = AttributedString(L10n.Home.NewScan.noLidar.localized)
            newScanButton.configuration = config
        } else if !ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            pointCloudScanButton.isEnabled = false
            pointCloudScanButton.alpha = 0.55
            var config = pointCloudScanButton.configuration
            config?.attributedSubtitle = AttributedString("Scene reconstruction is unavailable on this device")
            pointCloudScanButton.configuration = config
        }
    }

    // MARK: - Actions

    @objc private func startScan() {
        presentRoomScan()
    }

    @objc private func startPointCloudScan() {
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) else {
            showError(message: "This device does not support ARKit scene reconstruction.")
            return
        }
        let controller = PointCloudCaptureViewController()
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }

    private func presentRoomScan() {
        guard !isStartingScan else { return }

        guard RoomCaptureSession.isSupported else {
            showUnsupportedDeviceAlert()
            return
        }

        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let viewController = storyboard.instantiateViewController(
            withIdentifier: "RoomCaptureViewNavigationController") as? UINavigationController else {
            showError(message: "Unable to start scanning - RoomCaptureViewController not found in storyboard")
            return
        }

        if let navBar = viewController.navigationBar as UINavigationBar? {
            SpatialSenseTheme.configureNavigationBar(navBar, immersive: true)
        }
        viewController.modalPresentationStyle = .fullScreen
        present(viewController, animated: true)
    }

    @objc private func showSavedRooms() {
        let savedRoomsVC = SavedRoomsViewController()
        let navController = UINavigationController(rootViewController: savedRoomsVC)
        SpatialSenseTheme.configureNavigationBar(navController.navigationBar, immersive: false)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }

    @objc private func showSettings() {
        let settingsVC = SettingsViewController(style: .insetGrouped)
        let navController = UINavigationController(rootViewController: settingsVC)
        SpatialSenseTheme.configureNavigationBar(navController.navigationBar, immersive: false)
        present(navController, animated: true)
    }

    @objc private func showHelp() {
        let helpVC = HelpViewController()
        let navController = UINavigationController(rootViewController: helpVC)
        SpatialSenseTheme.configureNavigationBar(navController.navigationBar, immersive: false)
        present(navController, animated: true)
    }

    private func openRoom(_ room: SavedRoom) {
        let viewerVC = RoomViewerViewController(savedRoom: room)
        let navController = UINavigationController(rootViewController: viewerVC)
        SpatialSenseTheme.configureNavigationBar(navController.navigationBar, immersive: true)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }

    private func showRoomActions(for room: SavedRoom) {
        let alert = UIAlertController(title: room.name, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: L10n.FloorPlan.view.localized, style: .default) { [weak self] _ in
            self?.openRoom(room)
        })
        alert.addAction(UIAlertAction(title: L10n.Home.SavedRooms.title.localized, style: .default) { [weak self] _ in
            self?.showSavedRooms()
        })
        alert.addAction(UIAlertAction(title: L10n.Common.cancel.localized, style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    // MARK: - Alerts

    private func showUnsupportedDeviceAlert() {
        let alert = UIAlertController(
            title: L10n.Alert.unsupportedDeviceTitle.localized,
            message: L10n.Alert.unsupportedDeviceMessage.localized,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Common.ok.localized, style: .default))
        present(alert, animated: true)
    }

    private func showError(message: String) {
        let alert = UIAlertController(
            title: L10n.Common.error.localized,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Common.ok.localized, style: .default))
        present(alert, animated: true)
    }
}
