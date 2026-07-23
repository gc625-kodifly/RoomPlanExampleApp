/*
See LICENSE folder for this sample's licensing information.

Abstract:
View controller for displaying the 2D floor plan (Issues #7, #9, #10).
*/

import UIKit
import RoomPlan

class FloorPlanViewController: UIViewController {

    // MARK: - Properties

    private let floorPlanView = FloorPlanView()
    private let statsLabel = UILabel()
    private let toggleDimensionsButton = UIButton(type: .system)
    private let toggleLabelsButton = UIButton(type: .system)

    private var capturedRoom: CapturedRoom?

    // MARK: - Initialization

    init(room: CapturedRoom) {
        self.capturedRoom = room
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        configureFloorPlan()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            capturedRoom = nil
            floorPlanView.clear()
        }
    }

    deinit {
        #if DEBUG
        print("FloorPlanViewController deallocated")
        #endif
    }

    // MARK: - Setup

    private func setupUI() {
        title = L10n.FloorPlan.title.localized
        view.backgroundColor = SpatialSenseTheme.Color.immersive
        overrideUserInterfaceStyle = .dark

        if let navBar = navigationController?.navigationBar {
            SpatialSenseTheme.configureNavigationBar(navBar, immersive: true)
        }

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissView)
        )

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(shareFloorPlan)
        )

        floorPlanView.translatesAutoresizingMaskIntoConstraints = false
        floorPlanView.layer.cornerRadius = SpatialSenseTheme.Radius.lg
        floorPlanView.clipsToBounds = true
        view.addSubview(floorPlanView)

        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        statsLabel.font = SpatialSenseTheme.Font.caption
        statsLabel.textColor = SpatialSenseTheme.Color.textOnInverse.withAlphaComponent(0.75)
        statsLabel.textAlignment = .center
        statsLabel.numberOfLines = 0
        view.addSubview(statsLabel)

        let buttonStack = UIStackView()
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .horizontal
        buttonStack.spacing = SpatialSenseTheme.Space.sm
        buttonStack.distribution = .fillEqually
        view.addSubview(buttonStack)

        styleToggleButton(toggleDimensionsButton, title: "Dimensions: On")
        toggleDimensionsButton.addTarget(self, action: #selector(toggleDimensions), for: .touchUpInside)
        buttonStack.addArrangedSubview(toggleDimensionsButton)

        styleToggleButton(toggleLabelsButton, title: "Labels: On")
        toggleLabelsButton.addTarget(self, action: #selector(toggleLabels), for: .touchUpInside)
        buttonStack.addArrangedSubview(toggleLabelsButton)

        NSLayoutConstraint.activate([
            floorPlanView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: SpatialSenseTheme.Space.sm),
            floorPlanView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SpatialSenseTheme.Space.md),
            floorPlanView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SpatialSenseTheme.Space.md),
            floorPlanView.bottomAnchor.constraint(equalTo: statsLabel.topAnchor, constant: -SpatialSenseTheme.Space.md),

            statsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SpatialSenseTheme.Space.md),
            statsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SpatialSenseTheme.Space.md),
            statsLabel.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -SpatialSenseTheme.Space.md),

            buttonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SpatialSenseTheme.Space.md),
            buttonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SpatialSenseTheme.Space.md),
            buttonStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -SpatialSenseTheme.Space.md),
            buttonStack.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func styleToggleButton(_ button: UIButton, title: String) {
        button.configuration = SpatialSenseTheme.secondaryButtonConfiguration(title: title)
        button.configuration?.baseForegroundColor = SpatialSenseTheme.Color.textOnInverse
        button.configuration?.background.backgroundColor = SpatialSenseTheme.Color.overlayStrong
        button.configuration?.background.strokeColor = UIColor.white.withAlphaComponent(0.12)
    }

    private func configureFloorPlan() {
        guard let room = capturedRoom else { return }

        floorPlanView.configure(with: room)
        statsLabel.text = ScanStatistics.from(room).detailedSummary
    }

    // MARK: - Actions

    @objc private func dismissView() {
        dismiss(animated: true)
    }

    @objc private func toggleDimensions() {
        floorPlanView.showDimensions.toggle()
        styleToggleButton(toggleDimensionsButton, title: "Dimensions: \(floorPlanView.showDimensions ? "On" : "Off")")
    }

    @objc private func toggleLabels() {
        floorPlanView.showLabels.toggle()
        styleToggleButton(toggleLabelsButton, title: "Labels: \(floorPlanView.showLabels ? "On" : "Off")")
    }

    @objc private func shareFloorPlan() {
        let alert = UIAlertController(
            title: L10n.FloorPlan.export.localized,
            message: L10n.Export.chooseFormat.localized,
            preferredStyle: .actionSheet
        )

        alert.addAction(UIAlertAction(title: L10n.Export.pngImage.localized, style: .default) { [weak self] _ in
            self?.exportAsPNG()
        })

        alert.addAction(UIAlertAction(title: L10n.Export.svgVector.localized, style: .default) { [weak self] _ in
            self?.exportAsSVG()
        })

        alert.addAction(UIAlertAction(title: L10n.Export.dxfCad.localized, style: .default) { [weak self] _ in
            self?.exportAsDXF()
        })

        alert.addAction(UIAlertAction(title: L10n.Common.cancel.localized, style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }

        present(alert, animated: true)
    }

    private func exportAsPNG() {
        guard let room = capturedRoom else { return }
        let image = FloorPlanDocumentRenderer.image(
            data: FloorPlanData.from(room),
            size: CGSize(width: 1600, height: 2000),
            options: FloorPlanRenderOptions(
                showDimensions: floorPlanView.showDimensions,
                showLabels: floorPlanView.showLabels
            )
        )

        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        activityVC.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(activityVC, animated: true)
    }

    private func exportAsSVG() {
        guard let room = capturedRoom else { return }

        let data = FloorPlanData.from(room)
        do {
            let fileURL = try FloorPlanExporter.export(
                data: data,
                format: .svg,
                includeDimensions: floorPlanView.showDimensions
            )
            shareFile(at: fileURL)
        } catch {
            showExportError(error)
        }
    }

    private func exportAsDXF() {
        guard let room = capturedRoom else { return }

        let data = FloorPlanData.from(room)
        do {
            let fileURL = try FloorPlanExporter.export(
                data: data,
                format: .dxf,
                includeDimensions: floorPlanView.showDimensions
            )
            shareFile(at: fileURL)
        } catch {
            showExportError(error)
        }
    }

    private func shareFile(at url: URL) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activityVC.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(activityVC, animated: true)
    }

    private func showExportError(_ error: Error) {
        let alert = UIAlertController(
            title: L10n.Export.error.localized,
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Common.ok.localized, style: .default))
        present(alert, animated: true)
    }

    func updateRoom(_ room: CapturedRoom) {
        self.capturedRoom = room
        configureFloorPlan()
    }
}
