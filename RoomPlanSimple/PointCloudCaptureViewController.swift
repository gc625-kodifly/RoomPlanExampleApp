/*
See LICENSE folder for this sample's licensing information.

Abstract:
ARKit point-cloud capture with room-mode chrome parity and post-scan 3D review.
*/

import UIKit
import ARKit
import SceneKit

@MainActor
final class PointCloudCaptureViewController: UIViewController, ARSCNViewDelegate {

    private enum ScanState {
        case scanning
        case processing
        case review(PointCloudExporter.ExportResult)
        case saved(SavedPointCloud)
    }

    private let sceneView = ARSCNView(frame: .zero)
    /// Dedicated SceneKit view for post-scan review (ARSCNView keeps showing the camera feed when paused).
    private let reviewView = SCNView(frame: .zero)
    private let statusLabel = CaptureChrome.statusLabel()
    private let closeButton = CaptureChrome.circleButton(systemName: "xmark")
    private let pauseButton = CaptureChrome.circleButton(
        systemName: "pause.fill",
        diameter: CaptureChrome.controlSize
    )
    private let doneButton = UIButton(type: .system)
    private let configuration = ARWorldTrackingConfiguration()
    private let colorSampler = PointCloudColorSampler()

    private let reviewRoot = SCNNode()
    private let meshNode = SCNNode()
    private let pointNode = SCNNode()
    private let reviewCameraNode = SCNNode()

    private var vertexCounts: [UUID: Int] = [:]
    private var colorSamplingTimer: Timer?
    private var isPaused = false
    private var pendingResult: PointCloudExporter.ExportResult?
    private var reviewHasColor = false
    private var scanState: ScanState = .scanning {
        didSet { applyScanState() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupScene()
        setupOverlay()
        applyScanState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if case .scanning = scanState {
            startSession(reset: true)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed {
            sceneView.session.pause()
            colorSamplingTimer?.invalidate()
        }
    }

    private func setupScene() {
        view.backgroundColor = .black
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        sceneView.delegate = self
        sceneView.scene = SCNScene()
        sceneView.automaticallyUpdatesLighting = true
        sceneView.preferredFramesPerSecond = 60
        sceneView.allowsCameraControl = false
        view.addSubview(sceneView)

        reviewView.translatesAutoresizingMaskIntoConstraints = false
        reviewView.backgroundColor = UIColor(white: 0.07, alpha: 1)
        reviewView.autoenablesDefaultLighting = true
        reviewView.allowsCameraControl = true
        reviewView.antialiasingMode = .multisampling4X
        reviewView.isHidden = true
        let reviewScene = SCNScene()
        reviewScene.background.contents = UIColor(white: 0.07, alpha: 1)
        reviewView.scene = reviewScene
        reviewCameraNode.camera = SCNCamera()
        reviewCameraNode.camera?.fieldOfView = 50
        reviewCameraNode.camera?.zNear = 0.01
        reviewCameraNode.camera?.zFar = 80
        reviewScene.rootNode.addChildNode(reviewCameraNode)
        reviewScene.rootNode.addChildNode(reviewRoot)
        reviewRoot.addChildNode(meshNode)
        reviewRoot.addChildNode(pointNode)
        reviewView.pointOfView = reviewCameraNode
        view.addSubview(reviewView)

        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            reviewView.topAnchor.constraint(equalTo: view.topAnchor),
            reviewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            reviewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            reviewView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        configuration.sceneReconstruction = .meshWithClassification
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        }
    }

    private func setupOverlay() {
        closeButton.addTarget(self, action: #selector(cancelCapture), for: .touchUpInside)
        closeButton.accessibilityLabel = "Close point cloud scan"

        pauseButton.addTarget(self, action: #selector(togglePause), for: .touchUpInside)
        pauseButton.accessibilityIdentifier = "pointCloud.pause"
        pauseButton.accessibilityLabel = "Pause scan"

        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.configuration = SpatialSenseTheme.captureActionConfiguration(
            title: "Finish",
            systemName: "checkmark"
        )
        doneButton.accessibilityIdentifier = "pointCloud.finish"
        doneButton.addTarget(self, action: #selector(primaryAction), for: .touchUpInside)

        view.addSubview(closeButton)
        view.addSubview(statusLabel)
        view.addSubview(pauseButton)
        view.addSubview(doneButton)

        CaptureChrome.pin(close: closeButton, secondary: pauseButton, primary: doneButton, in: view)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: closeButton.trailingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 32)
        ])
    }

    private func applyScanState() {
        switch scanState {
        case .scanning:
            pauseButton.isHidden = false
            pauseButton.isEnabled = true
            doneButton.isEnabled = true
            doneButton.configuration = SpatialSenseTheme.captureActionConfiguration(
                title: "Finish",
                systemName: "checkmark"
            )
            doneButton.accessibilityLabel = "Finish point cloud scan"
            statusLabel.text = "  Building point cloud...  "
            statusLabel.isHidden = false
            showReviewSurface(false)

        case .processing:
            pauseButton.isHidden = true
            doneButton.isEnabled = false
            doneButton.configuration = SpatialSenseTheme.captureActionConfiguration(
                title: "Processing",
                systemName: "hourglass"
            )
            statusLabel.text = "  Processing capture...  "
            statusLabel.isHidden = false

        case .review:
            pauseButton.isHidden = true
            doneButton.isEnabled = true
            doneButton.configuration = SpatialSenseTheme.captureActionConfiguration(
                title: "Save",
                systemName: "checkmark"
            )
            doneButton.accessibilityLabel = "Save point cloud"
            statusLabel.text = "  Review capture · drag to orbit  "
            statusLabel.isHidden = false
            showReviewSurface(true)

        case .saved(let capture):
            pauseButton.isHidden = true
            doneButton.isEnabled = true
            doneButton.configuration = SpatialSenseTheme.captureActionConfiguration(
                title: "Close",
                systemName: "checkmark"
            )
            doneButton.accessibilityLabel = "Close saved point cloud"
            statusLabel.text = "  Saved · \(capture.pointCount.formatted()) points  "
            statusLabel.isHidden = false
            showReviewSurface(true)
        }
    }

    private func showReviewSurface(_ show: Bool) {
        reviewView.isHidden = !show
        sceneView.isHidden = show
        if show {
            view.bringSubviewToFront(reviewView)
            view.bringSubviewToFront(closeButton)
            view.bringSubviewToFront(statusLabel)
            view.bringSubviewToFront(doneButton)
        }
    }

    private func startSession(reset: Bool) {
        let options: ARSession.RunOptions = reset ? [.resetTracking, .removeExistingAnchors] : []
        sceneView.session.run(configuration, options: options)
        isPaused = false
        pauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        pauseButton.accessibilityLabel = "Pause scan"
        if reset {
            colorSampler.reset()
            vertexCounts.removeAll()
        }
        startColorSampling()
    }

    private func startColorSampling() {
        colorSamplingTimer?.invalidate()
        colorSamplingTimer = Timer.scheduledTimer(
            withTimeInterval: 0.35,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.sampleCurrentFrameColors()
            }
        }
    }

    private func sampleCurrentFrameColors() {
        guard !isPaused,
              case .scanning = scanState,
              let frame = sceneView.session.currentFrame,
              let orientation = view.window?.windowScene?.interfaceOrientation else {
            return
        }
        let anchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
        colorSampler.sample(
            frame: frame,
            anchors: anchors,
            orientation: orientation,
            viewportSize: sceneView.bounds.size
        )
    }

    @objc private func togglePause() {
        guard case .scanning = scanState else { return }
        if isPaused {
            startSession(reset: false)
            statusLabel.text = "  Building point cloud...  "
        } else {
            sceneView.session.pause()
            colorSamplingTimer?.invalidate()
            isPaused = true
            pauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
            pauseButton.accessibilityLabel = "Resume scan"
            statusLabel.text = "  Scan paused  "
        }
    }

    @objc private func cancelCapture() {
        colorSamplingTimer?.invalidate()
        sceneView.session.pause()
        dismiss(animated: true)
    }

    @objc private func primaryAction() {
        switch scanState {
        case .scanning:
            finishCapture()
        case .review:
            saveReviewedCapture()
        case .saved:
            dismiss(animated: true)
        case .processing:
            break
        }
    }

    private func finishCapture() {
        sampleCurrentFrameColors()
        let anchors = sceneView.session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
        guard !anchors.isEmpty else {
            showError(PointCloudExporter.ExportError.noMeshVertices)
            return
        }

        scanState = .processing
        UIAccessibility.post(notification: .announcement, argument: "Processing point cloud")
        colorSamplingTimer?.invalidate()
        sceneView.session.pause()

        let colors = colorSampler.snapshot(alignedTo: anchors)
        reviewHasColor = !colors.isEmpty
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let result = try PointCloudExporter.makeExportResult(
                    from: anchors,
                    colorsByAnchor: colors
                )
                Task { @MainActor in
                    self?.enterReview(with: result)
                }
            } catch {
                Task { @MainActor in
                    self?.scanState = .scanning
                    self?.startSession(reset: false)
                    self?.showError(error)
                }
            }
        }
    }

    private func enterReview(with result: PointCloudExporter.ExportResult) {
        pendingResult = result
        sceneView.session.pause()
        installReviewGeometry(result)
        scanState = .review(result)
        UIAccessibility.post(notification: .announcement, argument: "Point cloud ready to save")
    }

    private func installReviewGeometry(_ result: PointCloudExporter.ExportResult) {
        meshNode.geometry = nil
        pointNode.geometry = nil

        if !result.mesh.faces.isEmpty {
            meshNode.geometry = PointCloudViewerViewController.makeMeshGeometry(result.mesh)
            meshNode.isHidden = false
            pointNode.isHidden = true
        } else if !result.points.isEmpty {
            pointNode.geometry = PointCloudViewerViewController.makePointGeometry(result.points)
            pointNode.isHidden = false
            meshNode.isHidden = true
        } else {
            meshNode.isHidden = true
            pointNode.isHidden = true
        }

        let framing = result.mesh.vertices.isEmpty ? result.points : result.mesh.vertices
        guard let first = framing.first else { return }
        var minimum = first.position
        var maximum = first.position
        for point in framing.dropFirst() {
            minimum = simd_min(minimum, point.position)
            maximum = simd_max(maximum, point.position)
        }
        let center = (minimum + maximum) / 2
        reviewRoot.simdPosition = -center

        let extent = maximum - minimum
        let radius = max(0.6, max(extent.x, max(extent.y, extent.z)) * 1.05)
        reviewCameraNode.simdPosition = SIMD3(radius * 0.75, radius * 0.55, radius * 1.15)
        reviewCameraNode.look(at: SCNVector3Zero, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        reviewView.pointOfView = reviewCameraNode
        reviewView.defaultCameraController.inertiaEnabled = true
        reviewView.defaultCameraController.interactionMode = .orbitTurntable
        reviewView.defaultCameraController.target = SCNVector3Zero
        reviewView.defaultCameraController.maximumVerticalAngle = 85
        reviewView.setNeedsDisplay()
    }

    private func saveReviewedCapture() {
        guard let result = pendingResult else { return }
        let suggested = PointCloudStorageManager.suggestedName(date: Date())
        let alert = UIAlertController(
            title: "Name Point Cloud",
            message: "Choose a name before saving.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = suggested
            field.placeholder = "Point cloud name"
            field.clearButtonMode = .whileEditing
            field.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: L10n.Common.cancel.localized, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.Common.save.localized, style: .default) { [weak self, weak alert] _ in
            let typed = alert?.textFields?.first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (typed?.isEmpty == false) ? typed! : suggested
            self?.commitPointCloudSave(result: result, name: name)
        })
        present(alert, animated: true)
    }

    private func commitPointCloudSave(result: PointCloudExporter.ExportResult, name: String) {
        scanState = .processing
        let preview = PointCloudPreviewRenderer.image(points: result.points, mesh: result.mesh)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let capture = try PointCloudStorageManager.shared.save(
                    exportResult: result,
                    hasColor: self?.reviewHasColor ?? false,
                    previewImage: preview,
                    name: name
                )
                Task { @MainActor in
                    self?.pendingResult = nil
                    self?.scanState = .saved(capture)
                    UIAccessibility.post(notification: .announcement, argument: "Point cloud saved")
                }
            } catch {
                Task { @MainActor in
                    if let result = self?.pendingResult {
                        self?.scanState = .review(result)
                    }
                    self?.showError(error)
                }
            }
        }
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(
            title: "Point Cloud Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Common.ok.localized, style: .default))
        present(alert, animated: true)
    }

    nonisolated func renderer(
        _ renderer: any SCNSceneRenderer,
        didAdd node: SCNNode,
        for anchor: ARAnchor
    ) {
        guard let meshAnchor = anchor as? ARMeshAnchor else { return }
        node.geometry = Self.makeLivePointGeometry(from: meshAnchor.geometry)
        Task { @MainActor in
            guard case .scanning = self.scanState else { return }
            self.vertexCounts[meshAnchor.identifier] = meshAnchor.geometry.vertices.count
            self.updatePointCount()
        }
    }

    nonisolated func renderer(
        _ renderer: any SCNSceneRenderer,
        didUpdate node: SCNNode,
        for anchor: ARAnchor
    ) {
        guard let meshAnchor = anchor as? ARMeshAnchor else { return }
        node.geometry = Self.makeLivePointGeometry(from: meshAnchor.geometry)
        Task { @MainActor in
            guard case .scanning = self.scanState else { return }
            self.vertexCounts[meshAnchor.identifier] = meshAnchor.geometry.vertices.count
            self.updatePointCount()
        }
    }

    private func updatePointCount() {
        let total = vertexCounts.values.reduce(0, +)
        if case .scanning = scanState, !isPaused {
            statusLabel.text = "  \(total.formatted()) points  "
        }
    }

    nonisolated private static func makeLivePointGeometry(from geometry: ARMeshGeometry) -> SCNGeometry {
        let vertices = geometry.vertices
        let vertexCount = vertices.count
        let stride = vertices.stride
        let offset = vertices.offset
        var positions: [SCNVector3] = []
        positions.reserveCapacity(vertexCount)
        for index in 0..<vertexCount {
            let pointer = vertices.buffer.contents().advanced(by: offset + index * stride)
            let value = pointer.assumingMemoryBound(to: (Float, Float, Float).self).pointee
            positions.append(SCNVector3(value.0, value.1, value.2))
        }
        let source = SCNGeometrySource(vertices: positions)
        let element = SCNGeometryElement(
            data: nil,
            primitiveType: .point,
            primitiveCount: vertexCount,
            bytesPerIndex: 0
        )
        element.pointSize = 0.008
        element.minimumPointScreenSpaceRadius = 1
        element.maximumPointScreenSpaceRadius = 4
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = SpatialSenseTheme.Color.primary
        material.lightingModel = .constant
        geometry.materials = [material]
        return geometry
    }
}

