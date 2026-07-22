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

    // MARK: - IBOutlets

    @IBOutlet var exportButton: UIButton?
    @IBOutlet var doneButton: UIBarButtonItem?
    @IBOutlet var cancelButton: UIBarButtonItem?

    // MARK: - Private Properties

    private var isScanning: Bool = false
    private var isProcessingScan: Bool = false
    private var didSaveCurrentScan: Bool = false
    private var roomCaptureView: RoomCaptureView!
    private var roomCaptureSessionConfig: RoomCaptureSession.Configuration = RoomCaptureSession.Configuration()
    private var finalResults: CapturedRoom?
    private var captureError: Error?

    // Statistics tracking
    private var scanStatistics = ScanStatistics()
    private var lastObjectCount = 0

    // Status UI
    private var statusLabel: UILabel?
    private let captureControls = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemUltraThinMaterialDark)
    )
    private let bottomCancelButton = UIButton(type: .system)
    private let bottomDoneButton = UIButton(type: .system)

    // Photo capture
    private let photoCaptureManager = PhotoCaptureManager()
    private var photoButton: UIButton?
    private var photoCountLabel: UILabel?

    // WiFi signal tracking
    private let wifiSignalManager = WiFiSignalManager()
    private var wifiToggleButton: UIButton?
    private var wifiStatusLabel: UILabel?
    private var wifiOverlayView: WiFiOverlayView?

    // Export manager (Issue #14 refactoring)
    private lazy var exportManager = RoomExportManager(
        presentingViewController: self,
        sourceView: exportButton
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
        setupWifiToggle()
        setupCaptureControls()
        styleExportButton()
        HapticFeedbackManager.shared.prepareGenerators()

        // Listen for WiFi permission granted notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(wifiTrackingDidEnable),
            name: .wifiTrackingDidEnable,
            object: nil
        )

        #if DEBUG
        // Only log on significant events, not continuously (reduces debug slowdown)
        MemoryMonitor.shared.checkpoint("RoomCaptureViewController loaded")
        #endif
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSession()
    }

    override func viewWillDisappear(_ flag: Bool) {
        super.viewWillDisappear(flag)
        stopSession()
        cleanupResources()

        // Clear delegates to prevent retain cycles (Issue #15)
        if isBeingDismissed || isMovingFromParent {
            roomCaptureView?.captureSession.delegate = nil
            roomCaptureView?.delegate = nil
        }
    }

    // MARK: - Setup

    private func setupRoomCaptureView() {
        roomCaptureView = RoomCaptureView(frame: view.bounds)
        roomCaptureView.captureSession.delegate = self
        roomCaptureView.delegate = self
        roomCaptureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

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
        captureControls.translatesAutoresizingMaskIntoConstraints = false
        captureControls.layer.cornerRadius = 28
        captureControls.layer.cornerCurve = .continuous
        captureControls.clipsToBounds = true
        view.addSubview(captureControls)

        bottomCancelButton.translatesAutoresizingMaskIntoConstraints = false
        bottomCancelButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        bottomCancelButton.tintColor = .white
        bottomCancelButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        bottomCancelButton.layer.cornerRadius = 29
        bottomCancelButton.layer.borderWidth = 1
        bottomCancelButton.layer.borderColor = UIColor.white.withAlphaComponent(0.45).cgColor
        bottomCancelButton.accessibilityLabel = L10n.Common.cancel.localized
        bottomCancelButton.addTarget(self, action: #selector(cancelScanning(_:)), for: .touchUpInside)

        bottomDoneButton.translatesAutoresizingMaskIntoConstraints = false
        var doneConfiguration = UIButton.Configuration.filled()
        doneConfiguration.title = L10n.Common.done.localized
        doneConfiguration.image = UIImage(systemName: "checkmark")
        doneConfiguration.imagePadding = 8
        doneConfiguration.baseBackgroundColor = SpatialSenseTheme.Color.primary
        doneConfiguration.baseForegroundColor = .white
        doneConfiguration.cornerStyle = .capsule
        bottomDoneButton.configuration = doneConfiguration
        bottomDoneButton.addTarget(self, action: #selector(doneScanning(_:)), for: .touchUpInside)

        guard let exportButton else { return }
        exportButton.removeFromSuperview()
        exportButton.translatesAutoresizingMaskIntoConstraints = false

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let controls = UIStackView(arrangedSubviews: [
            bottomCancelButton,
            spacer,
            exportButton,
            bottomDoneButton
        ])
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.axis = .horizontal
        controls.alignment = .center
        controls.spacing = 12
        captureControls.contentView.addSubview(controls)

        NSLayoutConstraint.activate([
            captureControls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            captureControls.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            captureControls.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -14
            ),
            captureControls.heightAnchor.constraint(equalToConstant: 94),

            controls.leadingAnchor.constraint(equalTo: captureControls.contentView.leadingAnchor, constant: 18),
            controls.trailingAnchor.constraint(equalTo: captureControls.contentView.trailingAnchor, constant: -18),
            controls.centerYAnchor.constraint(equalTo: captureControls.contentView.centerYAnchor),

            bottomCancelButton.widthAnchor.constraint(equalToConstant: 58),
            bottomCancelButton.heightAnchor.constraint(equalToConstant: 58),
            exportButton.heightAnchor.constraint(equalToConstant: 48),
            bottomDoneButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            bottomDoneButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    private func setupPhotoButton() {
        let button = SpatialSenseTheme.circularControlButton(
            systemName: "camera.fill",
            diameter: SpatialSenseTheme.Size.photoButton
        )
        button.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        button.accessibilityLabel = L10n.Feature.photoCaptureTitle.localized
        view.addSubview(button)

        let countLabel = UILabel()
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = SpatialSenseTheme.Font.micro
        countLabel.textColor = SpatialSenseTheme.Color.textOnInverse
        countLabel.backgroundColor = SpatialSenseTheme.Color.primary
        countLabel.textAlignment = .center
        countLabel.layer.cornerRadius = 10
        countLabel.clipsToBounds = true
        countLabel.isHidden = true

        view.addSubview(countLabel)

        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            button.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            countLabel.topAnchor.constraint(equalTo: button.topAnchor, constant: -5),
            countLabel.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: 5),
            countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
            countLabel.heightAnchor.constraint(equalToConstant: 20)
        ])

        photoButton = button
        photoCountLabel = countLabel
    }

    private func setupWifiToggle() {
        let button = SpatialSenseTheme.circularControlButton(
            systemName: "wifi",
            diameter: SpatialSenseTheme.Size.controlButton
        )
        button.addTarget(self, action: #selector(toggleWifi), for: .touchUpInside)
        button.accessibilityLabel = L10n.Scan.wifiTracking.localized
        view.addSubview(button)

        let statusLabel = UILabel()
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = SpatialSenseTheme.Font.micro
        statusLabel.textColor = SpatialSenseTheme.Color.textOnInverse
        statusLabel.backgroundColor = SpatialSenseTheme.Color.overlay
        statusLabel.textAlignment = .center
        statusLabel.layer.cornerRadius = SpatialSenseTheme.Radius.sm
        statusLabel.clipsToBounds = true
        statusLabel.isHidden = true

        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            button.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            statusLabel.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 8),
            statusLabel.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 50),
            statusLabel.heightAnchor.constraint(equalToConstant: 20)
        ])

        wifiToggleButton = button
        wifiStatusLabel = statusLabel
        updateWifiButtonState()

        setupWifiOverlay()
    }

    private func setupWifiOverlay() {
        let overlayView = WiFiOverlayView(frame: view.bounds)
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlayView.isHidden = true // Only show when WiFi tracking enabled
        view.addSubview(overlayView)
        wifiOverlayView = overlayView

        // Connect WiFi sample callback to overlay
        wifiSignalManager.onSampleCaptured = { [weak self] sample in
            guard let self = self, let overlayView = self.wifiOverlayView else { return }

            // Convert WiFiSample.Position to SIMD3<Float>
            let position = SIMD3<Float>(
                sample.position.x,
                sample.position.y,
                sample.position.z
            )

            overlayView.addWiFiSample(
                id: sample.id,
                position: position,
                rssi: sample.rssi
            )

            // Also add coverage point
            overlayView.addCoveragePoint(position: position)
        }
    }

    @objc private func toggleWifi() {
        if !wifiSignalManager.isAuthorized {
            // Request permission first
            showWifiPermissionAlert()
            return
        }

        wifiSignalManager.isEnabled.toggle()
        updateWifiButtonState()

        // Show/hide overlay
        wifiOverlayView?.isHidden = !wifiSignalManager.isEnabled

        if wifiSignalManager.isEnabled && isScanning {
            wifiSignalManager.startSampling()
        } else {
            wifiSignalManager.stopSampling()
        }

        HapticFeedbackManager.shared.objectDetected()
    }

    private func showWifiPermissionAlert() {
        let alert = UIAlertController(
            title: L10n.WiFi.trackingTitle.localized,
            message: L10n.WiFi.trackingMessage.localized,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: L10n.WiFi.enable.localized, style: .default) { [weak self] _ in
            self?.wifiSignalManager.requestPermission()
        })
        alert.addAction(UIAlertAction(title: L10n.Common.cancel.localized, style: .cancel))

        present(alert, animated: true)
    }

    private func updateWifiButtonState() {
        let isOn = wifiSignalManager.isEnabled && wifiSignalManager.isAuthorized

        UIView.animate(withDuration: 0.2) { [weak self] in
            self?.wifiToggleButton?.backgroundColor = isOn
                ? SpatialSenseTheme.Color.primary.withAlphaComponent(0.9)
                : SpatialSenseTheme.Color.overlay
            self?.wifiToggleButton?.setImage(
                UIImage(systemName: isOn ? "wifi" : "wifi.slash"),
                for: .normal
            )
            self?.wifiToggleButton?.layer.borderColor = (isOn
                ? SpatialSenseTheme.Color.primary
                : UIColor.white.withAlphaComponent(0.12)).cgColor
        }

        wifiStatusLabel?.isHidden = !isOn
    }

    private func updateWifiStatus() {
        guard wifiSignalManager.isEnabled else { return }

        let count = wifiSignalManager.sampleCount
        if let rssi = wifiSignalManager.currentRSSI {
            wifiStatusLabel?.text = " \(rssi)dB (\(count)) "
        } else {
            wifiStatusLabel?.text = " " + L10n.WiFi.samples.localized(count) + " "
        }
        wifiStatusLabel?.isHidden = false
    }

    @objc private func wifiTrackingDidEnable() {
        // WiFi permission was granted and tracking is now enabled
        updateWifiButtonState()
        HapticFeedbackManager.shared.scanComplete()

        // Start sampling if we're already scanning
        if isScanning {
            wifiSignalManager.startSampling()
        }
    }

    private func cleanupResources() {
        finalResults = nil
        captureError = nil
        scanStatistics = ScanStatistics()
        lastObjectCount = 0
        photoCaptureManager.clearPhotos()
        photoCaptureManager.stopSession()
        wifiSignalManager.stopSampling()
        wifiSignalManager.clearSamples()
    }

    private func updatePhotoCount() {
        let count = photoCaptureManager.photoCount
        if count > 0 {
            photoCountLabel?.text = " \(count) "
            photoCountLabel?.isHidden = false
        } else {
            photoCountLabel?.isHidden = true
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
        isScanning = true
        isProcessingScan = false
        didSaveCurrentScan = false
        captureError = nil
        roomCaptureView?.captureSession.run(configuration: roomCaptureSessionConfig)
        photoCaptureManager.startSession()

        // Clear WiFi overlay from previous scans
        wifiOverlayView?.clear()

        // Apply default WiFi tracking setting
        if AppSettings.shared.defaultWifiTracking && wifiSignalManager.isAuthorized {
            wifiSignalManager.isEnabled = true
            updateWifiButtonState()
            wifiOverlayView?.isHidden = false
        }

        // Start WiFi sampling if enabled
        if wifiSignalManager.isEnabled && wifiSignalManager.isAuthorized {
            wifiSignalManager.startSampling()
        }

        updateNavBar(isScanning: true)
    }

    private func stopSession() {
        isScanning = false
        roomCaptureView?.captureSession.stop()
        photoCaptureManager.stopSession()
        wifiSignalManager.stopSampling()
        updateNavBar(isScanning: false)
    }

    // MARK: - RoomCaptureViewDelegate

    nonisolated func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        if let error = error {
            Task { @MainActor in
                self.captureError = error
            }
        }
        return true
    }

    nonisolated func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        Task { @MainActor in
            if let error = error {
                self.captureError = error
                self.showError(RoomCaptureError.processingFailed(underlying: error))
                HapticFeedbackManager.shared.scanError()
                self.finishProcessingWithoutSave()
            } else {
                HapticFeedbackManager.shared.scanComplete()
            }
            self.finalResults = processedResult
            self.scanStatistics = ScanStatistics.from(processedResult)

            // Auto-save if enabled in settings
            if AppSettings.shared.autoSaveScans && error == nil {
                self.performAutoSave(processedResult)
            } else if error == nil {
                self.finishProcessingWithoutSave()
            }
        }
    }

    private func performAutoSave(_ room: CapturedRoom) {
        do {
            let savedRoom = try RoomStorageManager.shared.saveRoom(room, photoManager: photoCaptureManager, wifiManager: wifiSignalManager)
            didSaveCurrentScan = true
            showAutoSaveConfirmation(savedRoom)
            finishProcessingAfterSave()
        } catch {
            print("Auto-save failed: \(error)")
            showError(RoomCaptureError.exportFailed(underlying: error))
            finishProcessingWithoutSave()
        }
    }

    private func finishProcessingAfterSave() {
        isProcessingScan = false
        doneButton?.title = L10n.Common.done.localized
        setBottomDoneTitle(L10n.Common.done.localized)
        doneButton?.isEnabled = true
        bottomDoneButton.isEnabled = true
        cancelButton?.isEnabled = true
        bottomCancelButton.isEnabled = true
        exportButton?.isHidden = false
    }

    private func finishProcessingWithoutSave() {
        isProcessingScan = false
        let title = didSaveCurrentScan ? L10n.Common.done.localized : "Save & Close"
        doneButton?.title = title
        setBottomDoneTitle(title)
        doneButton?.isEnabled = true
        bottomDoneButton.isEnabled = true
        cancelButton?.isEnabled = true
        bottomCancelButton.isEnabled = true
        exportButton?.isHidden = false
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
            self.captureError = error
            HapticFeedbackManager.shared.scanError()
            self.showError(RoomCaptureError.sessionFailed(underlying: error))
            self.updateStatusLabel(AppConstants.Strings.scanningFailed, isError: true)
        }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        let totalObjects = room.walls.count + room.doors.count + room.windows.count + room.objects.count
        let stats = ScanStatistics.from(room)

        // Get approximate position from room center (device is likely near edges during scan)
        let roomCenter = RoomGeometry.getRoomCenter(from: room)

        Task { @MainActor in
            // Haptic feedback when new objects detected
            if totalObjects > self.lastObjectCount {
                HapticFeedbackManager.shared.objectDetected()
                self.lastObjectCount = totalObjects
            }
            self.scanStatistics = stats

            // Update WiFi position tracking (use room center as reference)
            if let center = roomCenter {
                self.wifiSignalManager.updatePosition(center)

                // Update overlay camera transform
                // For the forward vector, assume user is scanning from edges toward center
                // Use a default forward vector pointing into the room
                let forward = SIMD3<Float>(0, 0, -1)
                self.wifiOverlayView?.updateCameraTransform(position: center, forward: forward)
            }
            self.updateWifiStatus()
        }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession, didStartWith configuration: RoomCaptureSession.Configuration) {
        Task { @MainActor in
            self.updateStatusLabel(AppConstants.Strings.scanningStarted)
            try? await Task.sleep(nanoseconds: UInt64(AppConstants.UI.statusLabelAutoHideDelay * 1_000_000_000))
            self.hideStatusLabel()
        }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        Task { @MainActor in
            if let error = error {
                self.captureError = error
                HapticFeedbackManager.shared.scanError()
                self.updateStatusLabel(AppConstants.Strings.scanEndedWithError, isError: true)
            } else {
                HapticFeedbackManager.shared.scanComplete()
                self.hideStatusLabel()
            }
        }
    }

    // MARK: - Actions

    @IBAction func doneScanning(_ sender: Any) {
        if isScanning {
            isProcessingScan = true
            doneButton?.title = L10n.Scan.processing.localized
            setBottomDoneTitle(L10n.Scan.processing.localized)
            doneButton?.isEnabled = false
            bottomDoneButton.isEnabled = false
            cancelButton?.isEnabled = false
            bottomCancelButton.isEnabled = false
            exportButton?.isHidden = true
            stopSession()
        } else if isProcessingScan {
            return
        } else if !didSaveCurrentScan, let results = finalResults {
            doneButton?.title = L10n.Scan.saving.localized
            setBottomDoneTitle(L10n.Scan.saving.localized)
            doneButton?.isEnabled = false
            bottomDoneButton.isEnabled = false
            cancelButton?.isEnabled = false
            bottomCancelButton.isEnabled = false
            performAutoSave(results)
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
        photoButton?.alpha = 0.5
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
            self.photoButton?.alpha = 1.0
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

        view.addSubview(feedbackLabel)
        NSLayoutConstraint.activate([
            feedbackLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            feedbackLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -100),
            feedbackLabel.widthAnchor.constraint(equalToConstant: 140),
            feedbackLabel.heightAnchor.constraint(equalToConstant: 32)
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
        do {
            let savedRoom = try RoomStorageManager.shared.saveRoom(room, photoManager: photoCaptureManager, wifiManager: wifiSignalManager)
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

        let samples = wifiSignalManager.collectedSamples
        let floorPlanVC = FloorPlanViewController(room: room, wifiSamples: samples)
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

    private func setBottomDoneTitle(_ title: String) {
        var configuration = bottomDoneButton.configuration
        configuration?.title = title
        bottomDoneButton.configuration = configuration
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
