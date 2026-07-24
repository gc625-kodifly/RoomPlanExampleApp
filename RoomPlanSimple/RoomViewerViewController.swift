//
//  RoomViewerViewController.swift
//  RoomPlanSimple
//
//  Comprehensive viewer for saved rooms - floor plan, 3D model, photos, WiFi data
//

import UIKit
import RoomPlan
import SceneKit

@MainActor
class RoomViewerViewController: UIViewController {

    // MARK: - Types

    private enum ViewMode {
        case floorPlan
        case model3D
        case photos
    }

    // MARK: - Properties

    private let savedRoom: SavedRoom
    private var currentMode: ViewMode = .floorPlan
    private var floorPlanImage: UIImage?

    // UI Components
    private let modeScrollView = UIScrollView()
    private let modeStack = UIStackView()
    private var modeButtons: [UIButton] = []
    private var selectedModeIndex = 0
    private let containerView = UIView()
    private weak var modelSceneView: SCNView?


    // MARK: - Initialization

    init(savedRoom: SavedRoom) {
        self.savedRoom = savedRoom
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadRoomData()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let modelSceneView {
            fitCamera(in: modelSceneView)
        }
    }

    // MARK: - Setup

    private func setupUI() {
        title = savedRoom.name
        view.backgroundColor = SpatialSenseTheme.Color.immersive
        overrideUserInterfaceStyle = .dark

        // Navigation buttons
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissView)
        )

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(shareRoom)
        )

        if let navBar = navigationController?.navigationBar {
            SpatialSenseTheme.configureNavigationBar(navBar, immersive: true)
        }

        // Floating segmented control panel
        let segmentContainer = UIView()
        segmentContainer.translatesAutoresizingMaskIntoConstraints = false
        segmentContainer.backgroundColor = SpatialSenseTheme.Color.overlayStrong
        segmentContainer.layer.cornerRadius = SpatialSenseTheme.Radius.control
        segmentContainer.layer.borderWidth = 1
        segmentContainer.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
        view.addSubview(segmentContainer)

        modeScrollView.translatesAutoresizingMaskIntoConstraints = false
        modeScrollView.showsHorizontalScrollIndicator = false
        modeScrollView.alwaysBounceHorizontal = true
        segmentContainer.addSubview(modeScrollView)

        modeStack.translatesAutoresizingMaskIntoConstraints = false
        modeStack.axis = .horizontal
        modeStack.spacing = SpatialSenseTheme.Space.sm
        modeScrollView.addSubview(modeStack)
        configureModeButtons()

        // Container view
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = SpatialSenseTheme.Color.immersive
        view.addSubview(containerView)
        view.sendSubviewToBack(containerView)

        NSLayoutConstraint.activate([
            segmentContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: SpatialSenseTheme.Space.sm),
            segmentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SpatialSenseTheme.Space.md),
            segmentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SpatialSenseTheme.Space.md),

            modeScrollView.topAnchor.constraint(equalTo: segmentContainer.topAnchor, constant: SpatialSenseTheme.Space.sm),
            modeScrollView.leadingAnchor.constraint(equalTo: segmentContainer.leadingAnchor, constant: SpatialSenseTheme.Space.sm),
            modeScrollView.trailingAnchor.constraint(equalTo: segmentContainer.trailingAnchor, constant: -SpatialSenseTheme.Space.sm),
            modeScrollView.bottomAnchor.constraint(equalTo: segmentContainer.bottomAnchor, constant: -SpatialSenseTheme.Space.sm),
            modeScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),

            modeStack.topAnchor.constraint(equalTo: modeScrollView.contentLayoutGuide.topAnchor),
            modeStack.leadingAnchor.constraint(equalTo: modeScrollView.contentLayoutGuide.leadingAnchor),
            modeStack.trailingAnchor.constraint(equalTo: modeScrollView.contentLayoutGuide.trailingAnchor),
            modeStack.bottomAnchor.constraint(equalTo: modeScrollView.contentLayoutGuide.bottomAnchor),
            modeStack.heightAnchor.constraint(equalTo: modeScrollView.frameLayoutGuide.heightAnchor),

            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureModeButtons() {
        let modes = [
            (L10n.Viewer.Mode.floorPlan.localized, "square.split.bottomrightquarter"),
            (L10n.Viewer.Mode.model3D.localized, "cube"),
            (L10n.Viewer.Mode.photos.localized, "photo.on.rectangle")
        ]

        modeButtons = modes.enumerated().map { index, mode in
            var configuration = UIButton.Configuration.plain()
            configuration.title = mode.0
            configuration.image = UIImage(systemName: mode.1)
            configuration.imagePadding = 6
            configuration.contentInsets = NSDirectionalEdgeInsets(
                top: 10,
                leading: 12,
                bottom: 10,
                trailing: 12
            )
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = SpatialSenseTheme.Font.caption
                return outgoing
            }
            let button = UIButton(configuration: configuration)
            button.tag = index
            button.accessibilityLabel = mode.0
            button.addTarget(self, action: #selector(modeButtonTapped(_:)), for: .touchUpInside)
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            modeStack.addArrangedSubview(button)
            return button
        }
        updateModeButtonStyles()
    }

    private func updateModeButtonStyles() {
        for (index, button) in modeButtons.enumerated() {
            let selected = index == selectedModeIndex
            button.configuration?.baseForegroundColor = selected
                ? SpatialSenseTheme.Color.primary
                : UIColor.white.withAlphaComponent(0.55)
            button.configuration?.background.backgroundColor = .clear
            button.accessibilityTraits = selected ? [.button, .selected] : .button
        }
    }

    private func loadRoomData() {
        self.floorPlanImage = RoomStorageManager.shared.getFloorPlanImage(for: savedRoom)
        showFloorPlan()
    }

    // MARK: - Mode Switching

    @objc private func modeButtonTapped(_ sender: UIButton) {
        selectedModeIndex = sender.tag
        updateModeButtonStyles()
        modeScrollView.scrollRectToVisible(sender.frame.insetBy(dx: -16, dy: 0), animated: true)

        // Remove current view
        modelSceneView = nil
        children.forEach { $0.removeFromParent(); $0.view.removeFromSuperview() }

        switch selectedModeIndex {
        case 0:
            currentMode = .floorPlan
            showFloorPlan()
        case 1:
            currentMode = .model3D
            show3DModel()
        case 2:
            currentMode = .photos
            showPhotos()
        default:
            break
        }
    }

    private func showFloorPlan() {
        guard let floorPlanData = RoomStorageManager.shared.loadFloorPlanData(for: savedRoom) else {
            showMessage(L10n.Viewer.noFloorPlan.localized)
            return
        }

        let floorPlanView = FloorPlanView(frame: containerView.bounds)
        floorPlanView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        floorPlanView.configure(with: floorPlanData)
        floorPlanView.backgroundColor = FloorPlanStyle.paper
        containerView.addSubview(floorPlanView)
    }

    private func show3DModel() {

        let sceneView = SCNView(frame: containerView.bounds)
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.backgroundColor = SpatialSenseTheme.Color.immersive
        sceneView.allowsCameraControl = true
        sceneView.antialiasingMode = .multisampling4X
        sceneView.preferredFramesPerSecond = 60
        sceneView.rendersContinuously = false

        // New saves use exact object bounds with offline, bundled Kenney assets.
        // Older saves remain viewable through the original RoomPlan USDZ.
        let floorPlanData = RoomStorageManager.shared.loadFloorPlanData(for: savedRoom)
        let measuredScene = floorPlanData.flatMap { data in
            RoomSceneBuilder.canBuildScene(from: data) ? RoomSceneBuilder.makeScene(from: data) : nil
        }
        let usdzURL = RoomStorageManager.shared.getUsdzURL(for: savedRoom)
        let scene = measuredScene ?? (try? SCNScene(url: usdzURL, options: nil))
        sceneView.autoenablesDefaultLighting = measuredScene == nil

        if let scene {
            sceneView.scene = scene
            modelSceneView = sceneView

            // Use one app-owned fitted camera so viewport changes can be handled consistently.
            if scene.rootNode.childNode(withName: "Camera", recursively: false) == nil {
                addFittedCamera(to: scene)
            }
            sceneView.pointOfView = scene.rootNode.childNode(withName: "Camera", recursively: false)
            fitCamera(in: sceneView)
        } else {
            showMessage(L10n.Viewer.no3DModel.localized)
            return
        }

        let vc = UIViewController()
        vc.view = sceneView
        addChild(vc)
        containerView.addSubview(vc.view)
        vc.didMove(toParent: self)


        // Add instructions overlay
        let instructionsLabel = UILabel()
        instructionsLabel.text = L10n.Viewer.model3DHint.localized
        instructionsLabel.font = SpatialSenseTheme.Font.caption
        instructionsLabel.adjustsFontForContentSizeCategory = true
        instructionsLabel.numberOfLines = 0
        instructionsLabel.textColor = SpatialSenseTheme.Color.textOnInverse.withAlphaComponent(0.75)
        instructionsLabel.textAlignment = .center
        instructionsLabel.backgroundColor = SpatialSenseTheme.Color.overlayStrong
        instructionsLabel.translatesAutoresizingMaskIntoConstraints = false
        sceneView.addSubview(instructionsLabel)

        NSLayoutConstraint.activate([
            instructionsLabel.bottomAnchor.constraint(equalTo: sceneView.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            instructionsLabel.centerXAnchor.constraint(equalTo: sceneView.centerXAnchor),
            instructionsLabel.widthAnchor.constraint(lessThanOrEqualTo: sceneView.widthAnchor, constant: -32)
        ])
    }

    private func showPhotos() {
        let photos = RoomStorageManager.shared.getPhotos(for: savedRoom)

        if photos.isEmpty {
            showMessage(L10n.Viewer.photosPlaceholder.localized)
            return
        }

        // Create collection view for photos
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = SpatialSenseTheme.Color.immersive
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(PhotoCell.self, forCellWithReuseIdentifier: "PhotoCell")
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        // Store photos for collection view
        objc_setAssociatedObject(collectionView, photosAssociatedKey, photos, .OBJC_ASSOCIATION_RETAIN)

        let vc = UIViewController()
        vc.view.backgroundColor = SpatialSenseTheme.Color.immersive
        vc.view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: vc.view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor)
        ])

        addChild(vc)
        containerView.addSubview(vc.view)
        vc.view.frame = containerView.bounds
        vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        vc.didMove(toParent: self)
    }

    private func showMessage(_ message: String) {
        let label = UILabel()
        label.text = message
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.frame = containerView.bounds
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let vc = UIViewController()
        vc.view.backgroundColor = SpatialSenseTheme.Color.immersive
        vc.view.addSubview(label)

        addChild(vc)
        containerView.addSubview(vc.view)
        vc.view.frame = containerView.bounds
        vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        vc.didMove(toParent: self)
    }

    // MARK: - Actions

    @objc private func dismissView() {
        dismiss(animated: true)
    }

    @objc private func shareRoom() {
        let alert = UIAlertController(
            title: L10n.Export.title.localized,
            message: L10n.Export.chooseExport.localized,
            preferredStyle: .actionSheet
        )

        alert.addAction(UIAlertAction(title: L10n.Export.usdz.localized, style: .default) { [weak self] _ in
            self?.shareUSDZ()
        })

        alert.addAction(UIAlertAction(title: L10n.Export.obj.localized, style: .default) { [weak self] _ in
            self?.shareOBJ()
        })

        alert.addAction(UIAlertAction(title: L10n.Export.stl.localized, style: .default) { [weak self] _ in
            self?.shareSTL()
        })

        alert.addAction(UIAlertAction(title: L10n.Export.dxf.localized, style: .default) { [weak self] _ in
            self?.shareFloorPlanDXF()
        })

        alert.addAction(UIAlertAction(title: L10n.Export.svg.localized, style: .default) { [weak self] _ in
            self?.shareFloorPlanSVG()
        })

        alert.addAction(UIAlertAction(title: L10n.Export.png.localized, style: .default) { [weak self] _ in
            self?.shareFloorPlanPNG()
        })

        alert.addAction(UIAlertAction(title: L10n.Export.ifc.localized, style: .default) { [weak self] _ in
            self?.shareIFC()
        })

        alert.addAction(UIAlertAction(title: L10n.Export.complete.localized, style: .default) { [weak self] _ in
            self?.shareCompleteRoom()
        })

        alert.addAction(UIAlertAction(title: L10n.Common.cancel.localized, style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }

        present(alert, animated: true)
    }

    private func shareUSDZ() {
        let url = RoomStorageManager.shared.getUsdzURL(for: savedRoom)
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activityVC.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(activityVC, animated: true)
    }

    private func shareOBJ() {
        exportAndShare { try RoomStorageManager.shared.exportToOBJ(for: self.savedRoom) }
    }

    private func shareSTL() {
        exportAndShare { try RoomStorageManager.shared.exportToSTL(for: self.savedRoom) }
    }

    private func shareFloorPlanDXF() {
        exportAndShare { try RoomStorageManager.shared.exportToDXF(for: self.savedRoom) }
    }

    private func shareFloorPlanSVG() {
        exportAndShare { try RoomStorageManager.shared.exportToSVG(for: self.savedRoom) }
    }

    private func shareFloorPlanPNG() {
        // TODO: Implementation for sharing floor plan PNG
        guard let image = floorPlanImage else {
            showMessage(L10n.Viewer.noFloorPlan.localized)
            return
        }
        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        activityVC.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(activityVC, animated: true)
    }

    private func shareIFC() {
        do {
            let ifcURL = try RoomStorageManager.shared.exportToIFC(for: savedRoom)
            let activityVC = UIActivityViewController(activityItems: [ifcURL], applicationActivities: nil)
            activityVC.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
            present(activityVC, animated: true)
        } catch {
            showMessage(L10n.Export.error.localized)
            print("IFC export failed: \(error)")
        }
    }

    private func shareCompleteRoom() {
        do {
            let exportURL = try RoomStorageManager.shared.exportRoomAsZIP(for: savedRoom)
            let activityVC = UIActivityViewController(activityItems: [exportURL], applicationActivities: nil)
            activityVC.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
            present(activityVC, animated: true)
        } catch {
            showMessage(L10n.Export.error.localized)
            print("Complete export failed: \(error)")
        }
    }

    private func exportAndShare(_ export: () throws -> URL) {
        do {
            let url = try export()
            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activityVC.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
            present(activityVC, animated: true)
        } catch {
            showMessage(L10n.Export.error.localized)
        }
    }

    private func addFittedCamera(to scene: SCNScene) {
        let camera = SCNCamera()
        camera.fieldOfView = 48
        camera.zNear = 0.02
        let target = SCNNode()
        target.name = "Camera target"
        scene.rootNode.addChildNode(target)
        let cameraNode = SCNNode()
        cameraNode.name = "Camera"
        cameraNode.camera = camera
        let lookAt = SCNLookAtConstraint(target: target)
        lookAt.isGimbalLockEnabled = true
        cameraNode.constraints = [lookAt]
        scene.rootNode.addChildNode(cameraNode)
    }

    private func fitCamera(in sceneView: SCNView) {
        guard
            let scene = sceneView.scene,
            sceneView.bounds.width > 0,
            sceneView.bounds.height > 0
        else {
            return
        }
        if scene.rootNode.childNode(withName: "Measured room", recursively: false) != nil {
            RoomSceneBuilder.refitCamera(in: scene, viewportSize: sceneView.bounds.size)
            return
        }
        guard
            let cameraNode = scene.rootNode.childNode(withName: "Camera", recursively: false),
            let camera = cameraNode.camera,
            let target = scene.rootNode.childNode(withName: "Camera target", recursively: false)
        else {
            return
        }
        let (minimum, maximum) = scene.rootNode.flattenedClone().boundingBox
        let center = SIMD3<Float>(
            (minimum.x + maximum.x) / 2,
            (minimum.y + maximum.y) / 2,
            (minimum.z + maximum.z) / 2
        )
        let extent = SIMD3<Float>(
            maximum.x - minimum.x,
            maximum.y - minimum.y,
            maximum.z - minimum.z
        )
        let distance = SceneCameraFit.distance(
            toFit: extent,
            verticalFieldOfViewDegrees: Float(camera.fieldOfView),
            aspectRatio: Float(sceneView.bounds.width / sceneView.bounds.height)
        )
        let direction = simd_normalize(SIMD3<Float>(0.55, 0.45, 0.72))
        target.position = SCNVector3(center.x, center.y, center.z)
        camera.zFar = Double(max(distance + simd_length(extent) * 2, 40))
        cameraNode.position = SCNVector3(
            center.x + direction.x * distance,
            center.y + direction.y * distance,
            center.z + direction.z * distance
        )
    }
}

// MARK: - UICollectionViewDelegate & DataSource

private let photosAssociatedKey = UnsafeRawPointer(bitPattern: "photosKey".hashValue)!

extension RoomViewerViewController: UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let photos = objc_getAssociatedObject(collectionView, photosAssociatedKey) as? [UIImage] else {
            return 0
        }
        return photos.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "PhotoCell", for: indexPath) as! PhotoCell

        if let photos = objc_getAssociatedObject(collectionView, photosAssociatedKey) as? [UIImage] {
            cell.configure(with: photos[indexPath.item])
        }

        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let padding: CGFloat = 8
        let columns: CGFloat = 2
        let totalPadding = padding * (columns + 1)
        let itemWidth = (collectionView.bounds.width - totalPadding) / columns
        return CGSize(width: itemWidth, height: itemWidth)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let photos = objc_getAssociatedObject(collectionView, photosAssociatedKey) as? [UIImage] else {
            return
        }

        // Show full-screen image viewer
        let fullScreenVC = PhotoViewerViewController(images: photos, startingIndex: indexPath.item)
        fullScreenVC.modalPresentationStyle = .overFullScreen
        present(fullScreenVC, animated: true)
    }
}

// MARK: - PhotoCell

private class PhotoCell: UICollectionViewCell {
    private let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    func configure(with image: UIImage) {
        imageView.image = image
    }
}

// MARK: - PhotoViewerViewController

private class PhotoViewerViewController: UIViewController {
    private let images: [UIImage]
    private var currentIndex: Int
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let closeButton = UIButton(type: .system)
    private let pageLabel = UILabel()

    init(images: [UIImage], startingIndex: Int) {
        self.images = images
        self.currentIndex = startingIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        showImage(at: currentIndex)
    }

    private func setupUI() {
        view.backgroundColor = .black

        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 4.0
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)

        // Dark chip so the control stays readable on light floor plans and bright photos.
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        closeButton.layer.cornerRadius = 22
        closeButton.layer.cornerCurve = .continuous
        closeButton.layer.borderWidth = 1
        closeButton.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        closeButton.accessibilityLabel = L10n.Common.close.localized
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        pageLabel.textColor = SpatialSenseTheme.Color.textOnInverse
        pageLabel.textAlignment = .center
        pageLabel.font = SpatialSenseTheme.Font.caption
        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            imageView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),

            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            pageLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            pageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])

        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeLeft.direction = .left
        view.addGestureRecognizer(swipeLeft)

        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeRight.direction = .right
        view.addGestureRecognizer(swipeRight)
    }

    private func showImage(at index: Int) {
        guard index >= 0, index < images.count else { return }
        currentIndex = index
        imageView.image = images[index]
        pageLabel.text = "\(index + 1) / \(images.count)"
        scrollView.zoomScale = 1.0
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        if gesture.direction == .left {
            if currentIndex < images.count - 1 {
                showImage(at: currentIndex + 1)
            }
        } else if gesture.direction == .right {
            if currentIndex > 0 {
                showImage(at: currentIndex - 1)
            }
        }
    }
}

extension PhotoViewerViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
}
