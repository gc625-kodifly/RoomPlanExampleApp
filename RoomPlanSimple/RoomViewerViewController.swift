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
        case wifiHeatmap
    }

    // MARK: - Properties

    private let savedRoom: SavedRoom
    private var wifiSamples: [WiFiSample] = []
    private var currentMode: ViewMode = .floorPlan
    private var floorPlanImage: UIImage?

    // UI Components
    private let segmentedControl = UISegmentedControl(items: [
        L10n.Viewer.Mode.floorPlan.localized,
        L10n.Viewer.Mode.model3D.localized,
        L10n.Viewer.Mode.photos.localized,
        L10n.Viewer.Mode.wifi.localized
    ])
    private let containerView = UIView()


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

        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.selectedSegmentTintColor = SpatialSenseTheme.Color.primary
        segmentedControl.setTitleTextAttributes([
            .foregroundColor: SpatialSenseTheme.Color.textOnInverse.withAlphaComponent(0.7),
            .font: SpatialSenseTheme.Font.medium(12)
        ], for: .normal)
        segmentedControl.setTitleTextAttributes([
            .foregroundColor: SpatialSenseTheme.Color.textOnInverse,
            .font: SpatialSenseTheme.Font.semibold(12)
        ], for: .selected)
        segmentContainer.addSubview(segmentedControl)

        // Container view
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = SpatialSenseTheme.Color.immersive
        view.addSubview(containerView)
        view.sendSubviewToBack(containerView)

        NSLayoutConstraint.activate([
            segmentContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: SpatialSenseTheme.Space.sm),
            segmentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SpatialSenseTheme.Space.md),
            segmentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SpatialSenseTheme.Space.md),

            segmentedControl.topAnchor.constraint(equalTo: segmentContainer.topAnchor, constant: SpatialSenseTheme.Space.sm),
            segmentedControl.leadingAnchor.constraint(equalTo: segmentContainer.leadingAnchor, constant: SpatialSenseTheme.Space.sm),
            segmentedControl.trailingAnchor.constraint(equalTo: segmentContainer.trailingAnchor, constant: -SpatialSenseTheme.Space.sm),
            segmentedControl.bottomAnchor.constraint(equalTo: segmentContainer.bottomAnchor, constant: -SpatialSenseTheme.Space.sm),

            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func loadRoomData() {
        // Load WiFi samples if available
        self.wifiSamples = RoomStorageManager.shared.loadWiFiSamples(for: savedRoom)

        // Load floor plan image
        self.floorPlanImage = RoomStorageManager.shared.getFloorPlanImage(for: savedRoom)

        // Show floor plan by default
        showFloorPlan()
    }

    // MARK: - Mode Switching

    @objc private func modeChanged() {
        // Remove current view
        children.forEach { $0.removeFromParent(); $0.view.removeFromSuperview() }

        switch segmentedControl.selectedSegmentIndex {
        case 0:
            currentMode = .floorPlan
            showFloorPlan()
        case 1:
            currentMode = .model3D
            show3DModel()
        case 2:
            currentMode = .photos
            showPhotos()
        case 3:
            currentMode = .wifiHeatmap
            showWiFiHeatmap()
        default:
            break
        }
    }

    private func showFloorPlan() {
        guard let image = floorPlanImage else {
            showMessage(L10n.Viewer.noFloorPlan.localized)
            return
        }

        // Create an interactive image view with pinch/pan gestures
        let scrollView = UIScrollView(frame: containerView.bounds)
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.minimumZoomScale = 0.5
        scrollView.maximumZoomScale = 4.0
        scrollView.delegate = self
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = true

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.tag = 100 // Tag for zoom reference

        scrollView.addSubview(imageView)
        containerView.addSubview(scrollView)

        // Add pinch gesture hint
        let hintLabel = UILabel()
        hintLabel.text = L10n.Viewer.floorPlanHint.localized
        hintLabel.font = SpatialSenseTheme.Font.caption
        hintLabel.textColor = SpatialSenseTheme.Color.textOnInverse.withAlphaComponent(0.7)
        hintLabel.textAlignment = .center
        hintLabel.backgroundColor = SpatialSenseTheme.Color.overlayStrong
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            hintLabel.bottomAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            hintLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            hintLabel.widthAnchor.constraint(lessThanOrEqualTo: scrollView.widthAnchor, constant: -32)
        ])
    }

    private func show3DModel() {

        let sceneView = SCNView(frame: containerView.bounds)
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.backgroundColor = SpatialSenseTheme.Color.immersive
        sceneView.allowsCameraControl = true
        sceneView.autoenablesDefaultLighting = true
        sceneView.antialiasingMode = .multisampling4X

        // Create a scene from the room (convert USDZ)
        let usdzURL = RoomStorageManager.shared.getUsdzURL(for: savedRoom)
        if let scene = try? SCNScene(url: usdzURL, options: nil) {
            sceneView.scene = scene

            // Add a camera if none exists
            if scene.rootNode.childNodes(passingTest: { node, _ in node.camera != nil }).isEmpty {
                let cameraNode = SCNNode()
                cameraNode.camera = SCNCamera()
                cameraNode.position = SCNVector3(x: 0, y: 2, z: 5)
                cameraNode.look(at: SCNVector3(x: 0, y: 0, z: 0))
                scene.rootNode.addChildNode(cameraNode)
            }
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

    private func showWiFiHeatmap() {
        if wifiSamples.isEmpty {
            showMessage(L10n.Viewer.noWifiData.localized)
            return
        }

        // Load floor plan data to display WiFi heatmap
        guard let floorPlanData = RoomStorageManager.shared.loadFloorPlanData(for: savedRoom) else {
            showMessage(L10n.Viewer.noFloorPlan.localized)
            return
        }

        // Create FloorPlanView with WiFi samples
        let floorPlanView = FloorPlanView(frame: containerView.bounds)
        floorPlanView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        floorPlanView.configure(with: floorPlanData, wifiSamples: wifiSamples)
        floorPlanView.showWifiHeatmap = true
        floorPlanView.backgroundColor = FloorPlanConfig.backgroundColor

        // Wrap in scroll view for zooming
        let scrollView = UIScrollView(frame: containerView.bounds)
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.minimumZoomScale = 0.5
        scrollView.maximumZoomScale = 4.0
        scrollView.delegate = self
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = true

        floorPlanView.tag = 100 // Tag for zoom reference
        scrollView.addSubview(floorPlanView)
        containerView.addSubview(scrollView)

        // Add hint label
        let hintLabel = UILabel()
        hintLabel.text = L10n.Viewer.wifiSamplesCount.localized(wifiSamples.count)
        hintLabel.font = SpatialSenseTheme.Font.caption
        hintLabel.textColor = SpatialSenseTheme.Color.textOnInverse.withAlphaComponent(0.7)
        hintLabel.textAlignment = .center
        hintLabel.backgroundColor = SpatialSenseTheme.Color.overlayStrong
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            hintLabel.bottomAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            hintLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            hintLabel.widthAnchor.constraint(lessThanOrEqualTo: scrollView.widthAnchor, constant: -32)
        ])
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
        // TODO: Implementation for sharing OBJ format
        showMessage(L10n.Export.error.localized)
    }

    private func shareSTL() {
        // TODO: Implementation for sharing STL format
        showMessage(L10n.Export.error.localized)
    }

    private func shareFloorPlanDXF() {
        // TODO: Implementation for sharing floor plan DXF
        showMessage(L10n.Export.error.localized)
    }

    private func shareFloorPlanSVG() {
        // TODO: Implementation for sharing floor plan SVG
        showMessage(L10n.Export.error.localized)
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

        // Scroll view for zooming
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 4.0
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        // Image view
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)

        // Close button
        closeButton.setTitle("✕", for: .normal)
        closeButton.setTitleColor(SpatialSenseTheme.Color.textOnInverse, for: .normal)
        closeButton.titleLabel?.font = SpatialSenseTheme.Font.semibold(24)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        // Page label
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

            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            pageLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            pageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])

        // Add swipe gestures
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

// MARK: - UIScrollViewDelegate

extension RoomViewerViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return scrollView.viewWithTag(100) // The imageView
    }
}
