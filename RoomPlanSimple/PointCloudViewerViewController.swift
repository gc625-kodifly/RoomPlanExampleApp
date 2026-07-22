/*
See LICENSE folder for this sample's licensing information.

Abstract:
Displays saved colored point clouds as a filled mesh or individual points.
*/

import UIKit
import SceneKit

@MainActor
final class PointCloudViewerViewController: UIViewController {
    private let capture: SavedPointCloud
    private let sceneView = SCNView(frame: .zero)
    private let modeControl = UISegmentedControl(items: ["Mesh", "Points"])
    private let statusLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)

    private let meshNode = SCNNode()
    private let pointNode = SCNNode()

    init(capture: SavedPointCloud) {
        self.capture = capture
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadGeometry()
    }

    private func setupUI() {
        title = capture.name
        view.backgroundColor = SpatialSenseTheme.Color.immersive
        overrideUserInterfaceStyle = .dark
        if let navBar = navigationController?.navigationBar {
            SpatialSenseTheme.configureNavigationBar(navBar, immersive: true)
        }

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(close)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(share)
        )

        sceneView.translatesAutoresizingMaskIntoConstraints = false
        sceneView.backgroundColor = SpatialSenseTheme.Color.studioBackground
        sceneView.allowsCameraControl = true
        sceneView.autoenablesDefaultLighting = true
        sceneView.antialiasingMode = .multisampling4X
        sceneView.rendersContinuously = true
        sceneView.scene = SCNScene()
        sceneView.scene?.rootNode.addChildNode(meshNode)
        sceneView.scene?.rootNode.addChildNode(pointNode)
        view.addSubview(sceneView)

        let controlContainer = UIView()
        controlContainer.translatesAutoresizingMaskIntoConstraints = false
        controlContainer.backgroundColor = SpatialSenseTheme.Color.overlayStrong
        controlContainer.layer.cornerRadius = SpatialSenseTheme.Radius.control
        controlContainer.layer.borderWidth = 1
        controlContainer.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        view.addSubview(controlContainer)

        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.selectedSegmentIndex = capture.meshFileName == nil ? 1 : 0
        modeControl.selectedSegmentTintColor = SpatialSenseTheme.Color.primary
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        controlContainer.addSubview(modeControl)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = SpatialSenseTheme.Font.caption
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.78)
        statusLabel.textAlignment = .center
        statusLabel.backgroundColor = SpatialSenseTheme.Color.overlayStrong
        statusLabel.layer.cornerRadius = 15
        statusLabel.clipsToBounds = true
        statusLabel.text = "  Loading capture…  "
        view.addSubview(statusLabel)

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.color = .white
        loadingIndicator.startAnimating()
        view.addSubview(loadingIndicator)

        let resetButton = UIButton(type: .system)
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.setImage(UIImage(systemName: "view.3d"), for: .normal)
        resetButton.tintColor = .white
        resetButton.backgroundColor = SpatialSenseTheme.Color.overlayStrong
        resetButton.layer.cornerRadius = 22
        resetButton.addTarget(self, action: #selector(resetCamera), for: .touchUpInside)
        view.addSubview(resetButton)

        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            controlContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            controlContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            controlContainer.widthAnchor.constraint(equalToConstant: 240),
            modeControl.topAnchor.constraint(equalTo: controlContainer.topAnchor, constant: 7),
            modeControl.leadingAnchor.constraint(equalTo: controlContainer.leadingAnchor, constant: 7),
            modeControl.trailingAnchor.constraint(equalTo: controlContainer.trailingAnchor, constant: -7),
            modeControl.bottomAnchor.constraint(equalTo: controlContainer.bottomAnchor, constant: -7),

            statusLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.heightAnchor.constraint(equalToConstant: 32),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            resetButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            resetButton.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -16),
            resetButton.widthAnchor.constraint(equalToConstant: 44),
            resetButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func loadGeometry() {
        guard let pcdURL = try? PointCloudStorageManager.shared.fileURL(for: capture) else {
            showLoadError(PointCloudFileLoader.LoaderError.malformedData)
            return
        }
        let plyURL = (try? PointCloudStorageManager.shared.meshFileURL(for: capture)) ?? nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let points = try PointCloudFileLoader.loadPCD(from: pcdURL)
                let mesh = try plyURL.map { try PointCloudFileLoader.loadPLY(from: $0) }
                Task { @MainActor in
                    self?.install(points: points, mesh: mesh)
                }
            } catch {
                Task { @MainActor in
                    self?.showLoadError(error)
                }
            }
        }
    }

    private func install(
        points: [PointCloudExporter.ColoredPoint],
        mesh: PointCloudExporter.ColoredMesh?
    ) {
        pointNode.geometry = Self.makePointGeometry(points)
        if let mesh, !mesh.faces.isEmpty {
            meshNode.geometry = Self.makeMeshGeometry(mesh)
            modeControl.setEnabled(true, forSegmentAt: 0)
        } else {
            modeControl.selectedSegmentIndex = 1
            modeControl.setEnabled(false, forSegmentAt: 0)
        }

        let framingPoints = mesh?.vertices ?? points
        centerGeometry(using: framingPoints)
        loadingIndicator.stopAnimating()
        statusLabel.text = "  \(points.count.formatted()) points · \(mesh?.faces.count.formatted() ?? "0") triangles  "
        modeChanged()
        resetCamera()
    }

    private static func makePointGeometry(
        _ points: [PointCloudExporter.ColoredPoint]
    ) -> SCNGeometry {
        let sources = geometrySources(points)
        let element = SCNGeometryElement(
            data: nil,
            primitiveType: .point,
            primitiveCount: points.count,
            bytesPerIndex: 0
        )
        element.pointSize = 0.006
        element.minimumPointScreenSpaceRadius = 1.5
        element.maximumPointScreenSpaceRadius = 5
        let geometry = SCNGeometry(sources: sources, elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.white
        geometry.materials = [material]
        return geometry
    }

    private static func makeMeshGeometry(
        _ mesh: PointCloudExporter.ColoredMesh
    ) -> SCNGeometry {
        let indices = mesh.faces.flatMap { [$0.x, $0.y, $0.z] }
        let indexData = indices.withUnsafeBytes { Data($0) }
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: mesh.faces.count,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        let geometry = SCNGeometry(sources: geometrySources(mesh.vertices), elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor.white
        material.roughness.contents = 0.92
        material.metalness.contents = 0
        material.isDoubleSided = true
        geometry.materials = [material]
        return geometry
    }

    private static func geometrySources(
        _ points: [PointCloudExporter.ColoredPoint]
    ) -> [SCNGeometrySource] {
        let vertices = points.map {
            SCNVector3($0.position.x, $0.position.y, $0.position.z)
        }
        let vertexSource = SCNGeometrySource(vertices: vertices)
        var colorComponents: [Float] = []
        colorComponents.reserveCapacity(points.count * 4)
        for point in points {
            colorComponents.append(Float(point.color.red) / 255)
            colorComponents.append(Float(point.color.green) / 255)
            colorComponents.append(Float(point.color.blue) / 255)
            colorComponents.append(1)
        }
        let colorData = colorComponents.withUnsafeBytes { Data($0) }
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: points.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 4
        )
        return [vertexSource, colorSource]
    }

    private func centerGeometry(using points: [PointCloudExporter.ColoredPoint]) {
        guard let first = points.first else { return }
        var minimum = first.position
        var maximum = first.position
        for point in points.dropFirst() {
            minimum = simd_min(minimum, point.position)
            maximum = simd_max(maximum, point.position)
        }
        let center = (minimum + maximum) / 2
        let offset = SCNVector3(-center.x, -center.y, -center.z)
        meshNode.position = offset
        pointNode.position = offset
    }

    @objc private func modeChanged() {
        let showMesh = modeControl.selectedSegmentIndex == 0
        meshNode.isHidden = !showMesh
        pointNode.isHidden = showMesh
    }

    @objc private func resetCamera() {
        sceneView.pointOfView = nil
        sceneView.defaultCameraController.stopInertia()
        sceneView.defaultCameraController.frameNodes([meshNode, pointNode])
    }

    private func showLoadError(_ error: Error) {
        loadingIndicator.stopAnimating()
        statusLabel.text = "  Unable to load capture  "
        let alert = UIAlertController(
            title: "Viewer Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Common.ok.localized, style: .default))
        present(alert, animated: true)
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func share() {
        var items: [URL] = []
        if let url = try? PointCloudStorageManager.shared.fileURL(for: capture) {
            items.append(url)
        }
        if let url = (try? PointCloudStorageManager.shared.meshFileURL(for: capture)) ?? nil {
            items.append(url)
        }
        guard !items.isEmpty else { return }
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activity.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(activity, animated: true)
    }
}
