/*
See LICENSE folder for this sample's licensing information.

Abstract:
Provides a live ARKit point-cloud capture experience backed by scene reconstruction.
*/

import UIKit
import ARKit
import SceneKit

@MainActor
final class PointCloudCaptureViewController: UIViewController, ARSCNViewDelegate {

    private let sceneView = ARSCNView(frame: .zero)
    private let statusLabel = UILabel()
    private let instructionLabel = UILabel()
    private let pauseButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)
    private let configuration = ARWorldTrackingConfiguration()
    private let colorSampler = PointCloudColorSampler()

    private var vertexCounts: [UUID: Int] = [:]
    private var colorSamplingTimer: Timer?
    private var isPaused = false
    private var isFinishing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupScene()
        setupOverlay()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSession(reset: true)
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
        sceneView.automaticallyUpdatesLighting = false
        sceneView.preferredFramesPerSecond = 60
        view.addSubview(sceneView)

        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        configuration.sceneReconstruction = .meshWithClassification
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        }
    }

    private func setupOverlay() {
        let closeButton = makeCircleButton(systemName: "xmark", diameter: 44)
        closeButton.addTarget(self, action: #selector(cancelCapture), for: .touchUpInside)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "  Building point cloud…  "
        statusLabel.font = SpatialSenseTheme.Font.semibold(13)
        statusLabel.textColor = .white
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        statusLabel.layer.cornerRadius = 18
        statusLabel.clipsToBounds = true
        statusLabel.textAlignment = .center

        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.text = "Move slowly and cover every visible surface"
        instructionLabel.font = SpatialSenseTheme.Font.medium(13)
        instructionLabel.textColor = .white
        instructionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.68)
        instructionLabel.layer.cornerRadius = 16
        instructionLabel.clipsToBounds = true
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 2

        configurePauseButton()
        configureDoneButton()

        view.addSubview(closeButton)
        view.addSubview(statusLabel)
        view.addSubview(instructionLabel)
        let trailingControls = UIStackView(arrangedSubviews: [pauseButton, doneButton])
        trailingControls.translatesAutoresizingMaskIntoConstraints = false
        trailingControls.axis = .vertical
        trailingControls.alignment = .trailing
        trailingControls.spacing = 12
        view.addSubview(trailingControls)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),

            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            statusLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),

            instructionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            instructionLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            instructionLabel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48),
            instructionLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 34),

            trailingControls.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            trailingControls.bottomAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -24
            ),
            trailingControls.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            pauseButton.widthAnchor.constraint(equalToConstant: 48),
            pauseButton.heightAnchor.constraint(equalToConstant: 48),
            doneButton.heightAnchor.constraint(equalToConstant: 48),
            doneButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 132)
        ])
    }

    private func makeCircleButton(systemName: String, diameter: CGFloat) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        button.layer.cornerRadius = diameter / 2
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        button.widthAnchor.constraint(equalToConstant: diameter).isActive = true
        button.heightAnchor.constraint(equalToConstant: diameter).isActive = true
        return button
    }

    private func configurePauseButton() {
        pauseButton.translatesAutoresizingMaskIntoConstraints = false
        pauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        pauseButton.tintColor = .white
        pauseButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        pauseButton.layer.cornerRadius = 24
        pauseButton.layer.cornerCurve = .continuous
        pauseButton.layer.borderWidth = 1
        pauseButton.layer.borderColor = UIColor.white.withAlphaComponent(0.45).cgColor
        pauseButton.addTarget(self, action: #selector(togglePause), for: .touchUpInside)
        pauseButton.accessibilityIdentifier = "pointCloud.pause"
        pauseButton.accessibilityLabel = "Pause scan"
    }

    private func configureDoneButton() {
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.configuration = SpatialSenseTheme.captureActionConfiguration(
            title: "Finish scan",
            systemName: "checkmark"
        )
        doneButton.accessibilityIdentifier = "pointCloud.finish"
        doneButton.accessibilityLabel = "Finish point cloud scan"
        doneButton.accessibilityHint = "Stops capture and saves the point cloud."
        doneButton.addTarget(self, action: #selector(finishCapture), for: .touchUpInside)
    }

    private func startSession(reset: Bool) {
        let options: ARSession.RunOptions = reset ? [.resetTracking, .removeExistingAnchors] : []
        sceneView.session.run(configuration, options: options)
        isPaused = false
        pauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        if reset {
            colorSampler.reset()
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
        if isPaused {
            startSession(reset: false)
            pauseButton.accessibilityLabel = "Pause scan"
            statusLabel.text = "  Building point cloud…  "
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

    @objc private func finishCapture() {
        guard !isFinishing else { return }
        sampleCurrentFrameColors()
        let anchors = sceneView.session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
        guard !anchors.isEmpty else {
            showError(PointCloudExporter.ExportError.noMeshVertices)
            return
        }

        isFinishing = true
        UIAccessibility.post(notification: .announcement, argument: "Saving point cloud")
        doneButton.isEnabled = false
        pauseButton.isEnabled = false
        instructionLabel.text = "Saving point cloud…"
        colorSamplingTimer?.invalidate()
        sceneView.session.pause()

        do {
            let capture = try PointCloudStorageManager.shared.save(
                anchors: anchors,
                colorsByAnchor: colorSampler.snapshot(alignedTo: anchors)
            )
            showSavedConfirmation(capture)
            UIAccessibility.post(notification: .announcement, argument: "Point cloud saved")
        } catch {
            isFinishing = false
            doneButton.isEnabled = true
            pauseButton.isEnabled = true
            instructionLabel.text = "Move slowly and cover every visible surface"
            showError(error)
        }
    }

    private func showSavedConfirmation(_ capture: SavedPointCloud) {
        let alert = UIAlertController(
            title: "Point Cloud Saved",
            message: "\(capture.pointCount.formatted()) points were saved and added to your capture library.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Share", style: .default) { [weak self] _ in
            guard let url = try? PointCloudStorageManager.shared.fileURL(for: capture) else { return }
            self?.share(url)
        })
        alert.addAction(UIAlertAction(title: "Done", style: .cancel) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    private func share(_ url: URL) {
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = doneButton
            popover.sourceRect = doneButton.bounds
        }
        present(activity, animated: true)
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
        node.geometry = Self.makePointGeometry(from: meshAnchor.geometry)
        Task { @MainActor in
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
        node.geometry = Self.makePointGeometry(from: meshAnchor.geometry)
        Task { @MainActor in
            self.vertexCounts[meshAnchor.identifier] = meshAnchor.geometry.vertices.count
            self.updatePointCount()
        }
    }

    nonisolated func renderer(
        _ renderer: any SCNSceneRenderer,
        didRemove node: SCNNode,
        for anchor: ARAnchor
    ) {
        Task { @MainActor in
            self.vertexCounts.removeValue(forKey: anchor.identifier)
            self.updatePointCount()
        }
    }

    nonisolated private static func makePointGeometry(from mesh: ARMeshGeometry) -> SCNGeometry {
        let vertices = mesh.vertices
        let source = SCNGeometrySource(
            buffer: vertices.buffer,
            vertexFormat: vertices.format,
            semantic: .vertex,
            vertexCount: vertices.count,
            dataOffset: vertices.offset,
            dataStride: vertices.stride
        )
        let element = SCNGeometryElement(
            data: nil,
            primitiveType: .point,
            primitiveCount: vertices.count,
            bytesPerIndex: 0
        )
        element.pointSize = 0.006
        element.minimumPointScreenSpaceRadius = 1.5
        element.maximumPointScreenSpaceRadius = 5

        let material = SCNMaterial()
        let pointColor = UIColor(red: 1, green: 0.49, blue: 0.16, alpha: 0.95)
        material.diffuse.contents = pointColor
        material.emission.contents = pointColor
        material.lightingModel = .constant
        material.blendMode = .add
        material.isDoubleSided = true

        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.materials = [material]
        return geometry
    }

    private func updatePointCount() {
        let count = vertexCounts.values.reduce(0, +)
        statusLabel.text = count == 0
            ? "  Building point cloud…  "
            : "  \(count.formatted()) live points  "
    }
}
