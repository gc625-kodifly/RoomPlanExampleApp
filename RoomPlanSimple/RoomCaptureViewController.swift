/*
See LICENSE folder for this sample's licensing information.

Abstract:
The sample app's main view controller that manages the scanning process.
*/

import UIKit
import RoomPlan
import AudioToolbox
import ARKit
import SceneKit

// MARK: - RoomCaptureViewController

@MainActor
class RoomCaptureViewController: UIViewController, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {

    private enum ScanState {
        case scanning
        case processing
        case review(CapturedRoom)
        case saved(CapturedRoom, SavedRoom)
        case error(String, CapturedRoom?)
    }

    // MARK: - IBOutlets

    @IBOutlet var exportButton: UIButton?
    @IBOutlet var doneButton: UIBarButtonItem?
    @IBOutlet var cancelButton: UIBarButtonItem?

    // MARK: - Private Properties

    private var hasStartedSession = false
    private var roomCaptureView: RoomCaptureView!
    private var roomCaptureSessionConfig: RoomCaptureSession.Configuration = RoomCaptureSession.Configuration()

    // Statistics tracking
    private var scanStatistics = ScanStatistics()
    private var lastObjectCount = 0

    // Status UI
    private var statusLabel: UILabel?
    private let bottomCancelButton = UIButton(type: .system)
    private let bottomDoneButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
    private var scanState: ScanState = .scanning {
        didSet { applyScanState() }
    }
    private var isScanning: Bool {
        if case .scanning = scanState { return true }
        return false
    }
    private var isProcessingScan: Bool {
        if case .processing = scanState { return true }
        return false
    }
    private var finalResults: CapturedRoom? {
        switch scanState {
        case .review(let room), .saved(let room, _): return room
        case .error(_, let room): return room
        case .scanning, .processing: return nil
        }
    }
    private var savedRoom: SavedRoom? {
        if case .saved(_, let savedRoom) = scanState { return savedRoom }
        return nil
    }

    // Photo capture
    private let photoCaptureManager = PhotoCaptureManager()
    private let photoButton = UIButton(type: .system)
    private let photoCountLabel = UILabel()

    // Export manager (Issue #14 refactoring)
    private lazy var exportManager = RoomExportManager(
        presentingViewController: self,
        sourceView: moreButton
    )

    // MARK: - Lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupRoomCaptureView()
        setupStatusLabel()
        setupPhotoButton()
        setupCaptureControls()
        styleExportButton()
        HapticFeedbackManager.shared.prepareGenerators()

        #if DEBUG
        // Only log on significant events, not continuously (reduces debug slowdown)
        MemoryMonitor.shared.checkpoint("RoomCaptureViewController loaded")
        #endif
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !hasStartedSession, isScanning {
            startSession()
        }
    }

    override func viewWillDisappear(_ flag: Bool) {
        super.viewWillDisappear(flag)
        let isLeavingCapture = isBeingDismissed
            || isMovingFromParent
            || navigationController?.isBeingDismissed == true
        if isLeavingCapture {
            stopSession()
            cleanupResources()
            roomCaptureView?.captureSession.delegate = nil
            roomCaptureView?.delegate = nil
        }
    }

    // MARK: - Setup

    private func setupRoomCaptureView() {
        roomCaptureView = RoomCaptureView(frame: view.bounds)
        roomCaptureView.captureSession.delegate = self
        roomCaptureView.delegate = self
        roomCaptureView.isModelEnabled = true
        roomCaptureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        roomCaptureView.accessibilityLabel = "Live room scan and model preview"
        roomCaptureView.accessibilityHint = "Move around the room to capture walls, openings, and objects."

        view.insertSubview(roomCaptureView, at: 0)
    }

    private func setupStatusLabel() {
        let label = SpatialSenseTheme.statusPillLabel()
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: AppConstants.UI.statusLabelTopOffset),
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.heightAnchor.constraint(greaterThanOrEqualToConstant: AppConstants.UI.statusLabelMinHeight),
            label.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48)
        ])

        statusLabel = label
    }

    private func setupCaptureControls() {
        bottomCancelButton.translatesAutoresizingMaskIntoConstraints = false
        bottomCancelButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        bottomCancelButton.tintColor = .white
        bottomCancelButton.backgroundColor = SpatialSenseTheme.Color.overlayStrong
        bottomCancelButton.layer.cornerRadius = 24
        bottomCancelButton.layer.cornerCurve = .continuous
        bottomCancelButton.layer.borderWidth = 1
        bottomCancelButton.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        bottomCancelButton.accessibilityLabel = "Close room scan"
        bottomCancelButton.accessibilityHint = "Stops scanning and returns to the capture library."
        bottomCancelButton.addTarget(self, action: #selector(cancelScanning(_:)), for: .touchUpInside)

        bottomDoneButton.translatesAutoresizingMaskIntoConstraints = false
        bottomDoneButton.configuration = SpatialSenseTheme.captureActionConfiguration(
            title: "Finish",
            systemName: "checkmark"
        )
        bottomDoneButton.accessibilityIdentifier = "roomScan.finish"
        bottomDoneButton.accessibilityLabel = "Finish room scan"
        bottomDoneButton.accessibilityHint = "Stops capture and processes the room model."
        bottomDoneButton.addTarget(self, action: #selector(doneScanning(_:)), for: .touchUpInside)

        moreButton.translatesAutoresizingMaskIntoConstraints = false
        moreButton.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        moreButton.tintColor = .white
        moreButton.backgroundColor = SpatialSenseTheme.Color.overlayStrong
        moreButton.layer.cornerRadius = 24
        moreButton.layer.cornerCurve = .continuous
        moreButton.layer.borderWidth = 1
        moreButton.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.accessibilityIdentifier = "roomScan.more"
        moreButton.accessibilityLabel = "Share or export"
        moreButton.isHidden = true

        exportButton?.removeFromSuperview()

        // Top: dismiss only. Bottom: photo + primary action. No dead ellipsis.
        view.addSubview(bottomCancelButton)
        view.addSubview(photoButton)
        view.addSubview(moreButton)
        view.addSubview(bottomDoneButton)

        NSLayoutConstraint.activate([
            bottomCancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            bottomCancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            bottomCancelButton.widthAnchor.constraint(equalToConstant: 48),
            bottomCancelButton.heightAnchor.constraint(equalToConstant: 48),

            photoButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            photoButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            photoButton.widthAnchor.constraint(equalToConstant: 56),
            photoButton.heightAnchor.constraint(equalToConstant: 56),

            bottomDoneButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            bottomDoneButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            bottomDoneButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            bottomDoneButton.heightAnchor.constraint(equalToConstant: 56),

            moreButton.trailingAnchor.constraint(equalTo: bottomDoneButton.leadingAnchor, constant: -12),
            moreButton.centerYAnchor.constraint(equalTo: bottomDoneButton.centerYAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 48),
            moreButton.heightAnchor.constraint(equalToConstant: 48)
        ])
        updateMoreMenu()
        applyScanState()
    }

    private func setupPhotoButton() {
        photoButton.translatesAutoresizingMaskIntoConstraints = false
        photoButton.setImage(UIImage(systemName: "camera.fill"), for: .normal)
        photoButton.tintColor = .white
        photoButton.backgroundColor = SpatialSenseTheme.Color.overlayStrong
        photoButton.layer.cornerRadius = 28
        photoButton.layer.cornerCurve = .continuous
        photoButton.layer.borderWidth = 1
        photoButton.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        photoButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        photoButton.accessibilityIdentifier = "roomScan.photo"
        photoButton.accessibilityLabel = L10n.Feature.photoCaptureTitle.localized
        photoButton.accessibilityHint = "Captures a photo of the current scan view."

        photoCountLabel.translatesAutoresizingMaskIntoConstraints = false
        photoCountLabel.font = SpatialSenseTheme.Font.micro
        photoCountLabel.textColor = .white
        photoCountLabel.backgroundColor = SpatialSenseTheme.Color.primary
        photoCountLabel.layer.cornerRadius = 8
        photoCountLabel.clipsToBounds = true
        photoCountLabel.textAlignment = .center
        photoCountLabel.isHidden = true
        photoButton.addSubview(photoCountLabel)
        NSLayoutConstraint.activate([
            photoCountLabel.topAnchor.constraint(equalTo: photoButton.topAnchor, constant: -4),
            photoCountLabel.trailingAnchor.constraint(equalTo: photoButton.trailingAnchor, constant: 4),
            photoCountLabel.heightAnchor.constraint(equalToConstant: 16),
            photoCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 16)
        ])
    }

    private func cleanupResources() {
        scanStatistics = ScanStatistics()
        lastObjectCount = 0
        photoCaptureManager.clearPhotos()
        photoCaptureManager.stopSession()
    }

    private func updatePhotoCount() {
        let count = photoCaptureManager.photoCount
        if count > 0 {
            photoCountLabel.text = " \(count) "
            photoCountLabel.isHidden = false
        } else {
            photoCountLabel.isHidden = true
        }
    }

    deinit {
        #if DEBUG
        Task { @MainActor in
            MemoryMonitor.shared.checkpoint("RoomCaptureViewController deinit")
            _ = MemoryMonitor.shared.checkForLeaks(threshold: 20_000_000)
        }
        print("RoomCaptureViewController deallocated")
        #endif
    }

    // MARK: - Status Label

    private func updateStatusLabel(_ text: String, isError: Bool = false) {
        statusLabel?.text = "  \(text)  "
        statusLabel?.backgroundColor = isError
            ? AppConstants.Colors.errorBackground
            : SpatialSenseTheme.Color.statusPill
        statusLabel?.isHidden = false
    }

    private func hideStatusLabel() {
        UIView.animate(withDuration: AppConstants.UI.animationDuration) { [weak self] in
            self?.statusLabel?.alpha = 0
        } completion: { [weak self] _ in
            self?.statusLabel?.isHidden = true
            self?.statusLabel?.alpha = 1
        }
    }

    // MARK: - Session Management

    private func startSession() {
        hasStartedSession = true
        scanState = .scanning
        roomCaptureView?.captureSession.run(configuration: roomCaptureSessionConfig)
        photoCaptureManager.startSession()

        updateNavBar(isScanning: true)
    }

    private func stopSession() {
        roomCaptureView?.captureSession.stop()
        photoCaptureManager.stopSession()
        updateNavBar(isScanning: false)
    }

    // MARK: - RoomCaptureViewDelegate

    nonisolated func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        if let error = error {
            Task { @MainActor in
                self.scanState = .error(error.localizedDescription, nil)
            }
        }
        return true
    }

    nonisolated func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        Task { @MainActor in
            if let error {
                self.showError(RoomCaptureError.processingFailed(underlying: error))
                HapticFeedbackManager.shared.scanError()
                self.scanState = .error(error.localizedDescription, processedResult)
            } else {
                HapticFeedbackManager.shared.scanComplete()
                self.scanState = .review(processedResult)
            }
            self.scanStatistics = ScanStatistics.from(processedResult)

            // Auto-save if enabled in settings
            if AppSettings.shared.autoSaveScans && error == nil {
                self.performAutoSave(processedResult)
            }
        }
    }

    private func performAutoSave(_ room: CapturedRoom) {
        do {
            let savedRoom = try RoomStorageManager.shared.saveRoom(room, photoManager: photoCaptureManager)
            scanState = .saved(room, savedRoom)
            showAutoSaveConfirmation(savedRoom)
        } catch {
            print("Auto-save failed: \(error)")
            showError(RoomCaptureError.exportFailed(underlying: error))
        }
    }

    private func showAutoSaveConfirmation(_ savedRoom: SavedRoom) {
        let toast = UILabel()
        toast.text = "  Saved: \(savedRoom.name)  "
        toast.font = SpatialSenseTheme.Font.medium(14)
        toast.textColor = SpatialSenseTheme.Color.successText
        toast.backgroundColor = SpatialSenseTheme.Color.successMuted
        toast.layer.cornerRadius = SpatialSenseTheme.Radius.md
        toast.clipsToBounds = true
        toast.textAlignment = .center
        toast.translatesAutoresizingMaskIntoConstraints = false
        toast.adjustsFontForContentSizeCategory = true
        toast.accessibilityTraits = .staticText
        view.addSubview(toast)

        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            toast.heightAnchor.constraint(equalToConstant: 32)
        ])

        toast.alpha = 0
        UIView.animate(withDuration: 0.3, animations: {
            toast.alpha = 1
        }) { _ in
            UIView.animate(withDuration: 0.3, delay: 2.0, options: [], animations: {
                toast.alpha = 0
            }) { _ in
                toast.removeFromSuperview()
            }
        }
    }

    // MARK: - RoomCaptureSessionDelegate

    nonisolated func captureSession(_ session: RoomCaptureSession, didFailWithError error: Error) {
        Task { @MainActor in
            HapticFeedbackManager.shared.scanError()
            self.showError(RoomCaptureError.sessionFailed(underlying: error))
            self.updateStatusLabel(AppConstants.Strings.scanningFailed, isError: true)
            self.scanState = .error(AppConstants.Strings.scanningFailed, nil)
        }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        let totalObjects = room.walls.count + room.doors.count + room.windows.count + room.objects.count
        let stats = ScanStatistics.from(room)

        Task { @MainActor in
            // Haptic feedback when new objects detected
            if totalObjects > self.lastObjectCount {
                HapticFeedbackManager.shared.objectDetected()
                self.lastObjectCount = totalObjects
            }
            self.scanStatistics = stats

        }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession, didStartWith configuration: RoomCaptureSession.Configuration) {
        Task { @MainActor in
            UIAccessibility.post(notification: .announcement, argument: "Room scan started")
        }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        Task { @MainActor in
            if error != nil {
                HapticFeedbackManager.shared.scanError()
                self.updateStatusLabel(AppConstants.Strings.scanEndedWithError, isError: true)
                self.scanState = .error(AppConstants.Strings.scanEndedWithError, self.finalResults)
            } else {
                HapticFeedbackManager.shared.scanComplete()
                self.hideStatusLabel()
            }
        }
    }

    // MARK: - Actions

    @IBAction func doneScanning(_ sender: Any) {
        if isScanning {
            scanState = .processing
            stopSession()
        } else if isProcessingScan {
            return
        } else if savedRoom == nil, let results = finalResults {
            saveRoom(results)
        } else {
            cancelScanning(sender)
        }
    }

    @IBAction func cancelScanning(_ sender: Any) {
        navigationController?.dismiss(animated: true)
    }

    @objc private func capturePhoto() {
        guard isScanning, let captureView = roomCaptureView else { return }

        // Visual feedback - flash effect
        photoButton.alpha = 0.5
        HapticFeedbackManager.shared.objectDetected()

        // Play shutter sound
        AudioServicesPlaySystemSound(1108)  // Camera shutter sound

        // Create flash effect
        let flashView = UIView(frame: view.bounds)
        flashView.backgroundColor = .white
        flashView.alpha = 0
        view.addSubview(flashView)

        UIView.animate(withDuration: 0.1, animations: {
            flashView.alpha = 0.8
        }) { _ in
            UIView.animate(withDuration: 0.2, animations: {
                flashView.alpha = 0
            }) { _ in
                flashView.removeFromSuperview()
            }
        }

        // Capture screenshot of the RoomCaptureView (includes camera + AR overlay)
        let renderer = UIGraphicsImageRenderer(bounds: captureView.bounds)
        let image = renderer.image { context in
            captureView.drawHierarchy(in: captureView.bounds, afterScreenUpdates: false)
        }

        // Save the captured image
        photoCaptureManager.addPhoto(image)

        UIView.animate(withDuration: 0.2) {
            self.photoButton.alpha = 1.0
        }

        updatePhotoCount()
        showPhotoCapturedFeedback()
    }

    private func showPhotoCapturedFeedback() {
        let feedbackLabel = UILabel()
        feedbackLabel.text = L10n.Scan.photoCaptured.localized
        feedbackLabel.font = SpatialSenseTheme.Font.medium(14)
        feedbackLabel.textColor = SpatialSenseTheme.Color.textOnInverse
        feedbackLabel.backgroundColor = SpatialSenseTheme.Color.overlayStrong
        feedbackLabel.textAlignment = .center
        feedbackLabel.layer.cornerRadius = SpatialSenseTheme.Radius.md
        feedbackLabel.clipsToBounds = true
        feedbackLabel.translatesAutoresizingMaskIntoConstraints = false
        feedbackLabel.adjustsFontForContentSizeCategory = true

        view.addSubview(feedbackLabel)
        NSLayoutConstraint.activate([
            feedbackLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            feedbackLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 72),
            feedbackLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
            feedbackLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 32)
        ])

        UIView.animate(withDuration: 0.3, delay: 1.0, options: [], animations: {
            feedbackLabel.alpha = 0
        }) { _ in
            feedbackLabel.removeFromSuperview()
        }
    }

    @IBAction func exportResults(_ sender: UIButton) {
        guard let results = finalResults else {
            showError(RoomCaptureError.noScanData)
            return
        }

        exportManager.showExportOptions(
            statistics: scanStatistics,
            onFloorPlan: { [weak self] in self?.showFloorPlan() },
            onSave: { [weak self] in self?.saveRoom(results) },
            onExport: { [weak self] format in
                guard let self = self else { return }
                self.exportManager.performExport(
                    results: results,
                    format: format,
                    onError: { self.showError($0) }
                )
            }
        )
    }

    // MARK: - Save Room

    private func saveRoom(_ room: CapturedRoom) {
        if let savedRoom {
            showSaveSuccess(savedRoom)
            return
        }
        let suggested = RoomStorageManager.suggestedName(for: room)
        let alert = UIAlertController(
            title: "Name Scan",
            message: "Name this scan before saving.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = suggested
            field.placeholder = L10n.SavedRooms.roomNamePlaceholder.localized
            field.clearButtonMode = .whileEditing
            field.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: L10n.Common.cancel.localized, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.Common.save.localized, style: .default) { [weak self, weak alert] _ in
            let typed = alert?.textFields?.first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (typed?.isEmpty == false) ? typed! : suggested
            self?.commitRoomSave(room, name: name)
        })
        present(alert, animated: true)
    }

    private func commitRoomSave(_ room: CapturedRoom, name: String) {
        do {
            let savedRoom = try RoomStorageManager.shared.saveRoom(
                room,
                name: name,
                photoManager: photoCaptureManager
            )
            scanState = .saved(room, savedRoom)
            showSaveSuccess(savedRoom)
            HapticFeedbackManager.shared.scanComplete()
        } catch {
            showError(RoomCaptureError.exportFailed(underlying: error))
        }
    }

    private func showSaveSuccess(_ savedRoom: SavedRoom) {
        let alert = UIAlertController(
            title: L10n.Scan.roomSaved.localized,
            message: L10n.Scan.roomSavedMessage.localized(savedRoom.name, savedRoom.summary),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: AppConstants.Strings.okButton, style: .default))
        present(alert, animated: true)
    }

    // MARK: - Floor Plan

    private func showFloorPlan() {
        guard let room = finalResults else {
            showError(RoomCaptureError.noScanData)
            return
        }

        let floorPlanVC = FloorPlanViewController(room: room)
        let navController = UINavigationController(rootViewController: floorPlanVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }

    // MARK: - Error Handling

    private func showError(_ error: RoomCaptureError) {
        let message = [error.errorDescription, error.recoverySuggestion]
            .compactMap { $0 }
            .joined(separator: "\n\n")

        let alert = UIAlertController(title: AppConstants.Strings.errorTitle, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: AppConstants.Strings.okButton, style: .default))

        if case .exportFailed = error {
            alert.addAction(UIAlertAction(title: AppConstants.Strings.tryAgainButton, style: .default) { [weak self] _ in
                if let button = self?.exportButton { self?.exportResults(button) }
            })
        }
        present(alert, animated: true)
    }

    // MARK: - UI State Management

    private func updateMoreMenu() {
        guard isViewLoaded else { return }
        var actions: [UIMenuElement] = []

        if finalResults != nil {
            actions.append(UIAction(
                title: "Share or export",
                image: UIImage(systemName: "square.and.arrow.up")
            ) { [weak self] _ in
                guard let self else { return }
                self.exportResults(self.moreButton)
            })
        }

        moreButton.menu = UIMenu(children: actions)
        moreButton.isHidden = actions.isEmpty
        moreButton.accessibilityValue = actions.isEmpty ? nil : "Available"
    }

    private func applyScanState() {
        guard isViewLoaded else { return }

        switch scanState {
        case .scanning:
            bottomCancelButton.isEnabled = true
            bottomDoneButton.isEnabled = true
            bottomDoneButton.configuration = SpatialSenseTheme.captureActionConfiguration(
                title: "Finish",
                systemName: "checkmark"
            )
            bottomDoneButton.accessibilityLabel = "Finish room scan"
            bottomDoneButton.accessibilityHint = "Stops capture and processes the room model."
            photoButton.isHidden = false
            hideStatusLabel()

        case .processing:
            bottomCancelButton.isEnabled = false
            bottomDoneButton.isEnabled = false
            bottomDoneButton.configuration = SpatialSenseTheme.captureActionConfiguration(
                title: "Processing",
                systemName: "hourglass"
            )
            bottomDoneButton.accessibilityLabel = "Processing room scan"
            photoButton.isHidden = true
            updateStatusLabel("Processing room model")
            UIAccessibility.post(notification: .announcement, argument: "Processing room model")

        case .review:
            bottomCancelButton.isEnabled = true
            bottomDoneButton.isEnabled = true
            bottomDoneButton.configuration = SpatialSenseTheme.captureActionConfiguration(
                title: "Save",
                systemName: "checkmark"
            )
            bottomDoneButton.accessibilityLabel = "Save room and close"
            bottomDoneButton.accessibilityHint = "Saves this room to the capture library."
            photoButton.isHidden = true
            hideStatusLabel()
            UIAccessibility.post(notification: .announcement, argument: "Room model ready to save")

        case .saved:
            bottomCancelButton.isEnabled = true
            bottomDoneButton.isEnabled = true
            bottomDoneButton.configuration = SpatialSenseTheme.captureActionConfiguration(
                title: "Close",
                systemName: "checkmark"
            )
            bottomDoneButton.accessibilityLabel = "Close saved room"
            photoButton.isHidden = true
            hideStatusLabel()
            UIAccessibility.post(notification: .announcement, argument: "Room saved")

        case .error(let message, _):
            bottomCancelButton.isEnabled = true
            bottomDoneButton.isEnabled = false
            photoButton.isHidden = true
            updateStatusLabel(message, isError: true)
            UIAccessibility.post(notification: .announcement, argument: message)
        }

        updateMoreMenu()
    }

    private func updateNavBar(isScanning: Bool) {
        let tintColor = isScanning ? AppConstants.Colors.activeNavBarTint : AppConstants.Colors.completeNavBarTint
        exportButton?.isHidden = isScanning || isProcessingScan

        UIView.animate(withDuration: AppConstants.UI.animationDuration) { [weak self] in
            self?.cancelButton?.tintColor = tintColor
            self?.doneButton?.tintColor = tintColor
            self?.bottomCancelButton.tintColor = .white
            self?.exportButton?.alpha = isScanning ? 0.0 : 1.0
        }
    }

    private func styleExportButton() {
        guard let exportButton else { return }
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = SpatialSenseTheme.Color.primary
        config.baseForegroundColor = SpatialSenseTheme.Color.textOnInverse
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
        var title = AttributedString(exportButton.title(for: .normal) ?? L10n.Common.share.localized)
        title.font = SpatialSenseTheme.Font.semibold(16)
        config.attributedTitle = title
        exportButton.configuration = config
    }
}
