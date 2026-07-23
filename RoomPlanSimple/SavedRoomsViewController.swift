/*
See LICENSE folder for this sample's licensing information.

Abstract:
SpatialSense-styled browse workspace for saved room scans.
*/

import UIKit
import RoomPlan

struct RoomBatchDeletionResult {
    let deletedRoomIDs: Set<UUID>
    let failures: [(room: SavedRoom, error: Error)]

    var failedRoomIDs: Set<UUID> {
        Set(failures.map(\.room.id))
    }
}

enum RoomBatchDeletion {
    static func perform(
        rooms: [SavedRoom],
        delete: (SavedRoom) throws -> Void
    ) -> RoomBatchDeletionResult {
        var deletedRoomIDs: Set<UUID> = []
        var failures: [(room: SavedRoom, error: Error)] = []
        for room in rooms {
            do {
                try delete(room)
                deletedRoomIDs.insert(room.id)
            } catch {
                failures.append((room, error))
            }
        }
        return RoomBatchDeletionResult(
            deletedRoomIDs: deletedRoomIDs,
            failures: failures
        )
    }
}

class SavedRoomsViewController: UIViewController {

    // MARK: - Types

    private enum SortMode: Int {
        case newest
        case oldest
        case name
    }

    private enum ViewMode: Int {
        case list
        case grid
    }

    // MARK: - Properties

    private var allCaptures: [LibraryCaptureItem] = []
    private var filteredCaptures: [LibraryCaptureItem] = []
    private var selectedCaptureIDs: Set<UUID> = []
    private var isSelectMode = false
    private var sortMode: SortMode = .newest
    private var viewMode: ViewMode = .grid
    private var searchQuery = ""
    private var lastRenderedColumnCount = 0

    private let searchBar = UISearchBar()
    private let toolbarRow = UIStackView()
    private let sortButton = UIButton(type: .system)
    private let viewModeControl = UISegmentedControl(items: [
        UIImage(systemName: "list.bullet") ?? UIImage(),
        UIImage(systemName: "square.grid.2x2") ?? UIImage()
    ])
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let emptyLabel = UILabel()
    private let selectionToolbar = UIToolbar()
    private var selectionToolbarHeight: NSLayoutConstraint?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()

        if AppSettings.shared.iCloudSyncEnabled {
            Task {
                do {
                    let migratedCount = try RoomStorageManager.shared.migrateToICloud()
                    if migratedCount > 0 {
                        await MainActor.run { self.loadLibraryItems() }
                    }
                } catch {
                    print("⚠️ Auto-migration failed: \(error)")
                }
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let navBar = navigationController?.navigationBar {
            SpatialSenseTheme.configureNavigationBar(navBar, immersive: true)
        }
        loadLibraryItems()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let columns = preferredGridColumnCount
        if viewMode == .grid, columns != lastRenderedColumnCount, !filteredCaptures.isEmpty {
            renderCaptures()
        }
    }

    // MARK: - Setup

    private func setupUI() {
        title = L10n.SavedRooms.title.localized
        view.backgroundColor = SpatialSenseTheme.Color.studioBackground
        overrideUserInterfaceStyle = .dark
        navigationItem.largeTitleDisplayMode = .never

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissView)
        )
        updateNavigationButtons()

        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.placeholder = L10n.SavedRooms.searchPlaceholder.localized
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        searchBar.accessibilityIdentifier = "savedRooms.search"
        searchBar.searchTextField.backgroundColor = SpatialSenseTheme.Color.studioSurfaceRaised
        searchBar.searchTextField.textColor = .white
        searchBar.searchTextField.tintColor = SpatialSenseTheme.Color.primary
        searchBar.searchTextField.leftView?.tintColor = UIColor.white.withAlphaComponent(0.45)
        view.addSubview(searchBar)

        configureToolbarRow()
        view.addSubview(toolbarRow)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = SpatialSenseTheme.Space.md
        scrollView.addSubview(contentStack)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = SpatialSenseTheme.Font.body
        emptyLabel.textColor = UIColor.white.withAlphaComponent(0.48)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)

        selectionToolbar.translatesAutoresizingMaskIntoConstraints = false
        selectionToolbar.isHidden = true
        selectionToolbar.barStyle = .black
        view.addSubview(selectionToolbar)

        let toolbarHeight = selectionToolbar.heightAnchor.constraint(equalToConstant: 0)
        selectionToolbarHeight = toolbarHeight

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SpatialSenseTheme.Space.sm),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SpatialSenseTheme.Space.sm),

            toolbarRow.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: SpatialSenseTheme.Space.sm),
            toolbarRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SpatialSenseTheme.Space.md),
            toolbarRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SpatialSenseTheme.Space.md),
            toolbarRow.heightAnchor.constraint(equalToConstant: SpatialSenseTheme.Size.toolbarControl),

            scrollView.topAnchor.constraint(equalTo: toolbarRow.bottomAnchor, constant: SpatialSenseTheme.Space.md),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: selectionToolbar.topAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: SpatialSenseTheme.Space.md),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -SpatialSenseTheme.Space.md),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -SpatialSenseTheme.Space.lg),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -SpatialSenseTheme.Space.xl),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SpatialSenseTheme.Space.xl),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SpatialSenseTheme.Space.xl),

            selectionToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            selectionToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            selectionToolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            toolbarHeight
        ])
    }

    private func configureToolbarRow() {
        toolbarRow.translatesAutoresizingMaskIntoConstraints = false
        toolbarRow.axis = .horizontal
        toolbarRow.alignment = .center
        toolbarRow.spacing = SpatialSenseTheme.Space.sm
        toolbarRow.distribution = .fill

        sortButton.configuration = SpatialSenseTheme.secondaryButtonConfiguration(
            title: L10n.SavedRooms.sortNewest.localized,
            icon: "arrow.up.arrow.down"
        )
        sortButton.configuration?.baseForegroundColor = .white
        sortButton.configuration?.background.backgroundColor = SpatialSenseTheme.Color.studioSurfaceRaised
        sortButton.configuration?.background.strokeColor = SpatialSenseTheme.Color.studioBorder
        sortButton.menu = UIMenu(children: [
            UIAction(title: L10n.SavedRooms.sortNewest.localized) { [weak self] _ in
                self?.sortMode = .newest
                self?.applyFiltersAndReload()
            },
            UIAction(title: L10n.SavedRooms.sortOldest.localized) { [weak self] _ in
                self?.sortMode = .oldest
                self?.applyFiltersAndReload()
            },
            UIAction(title: L10n.SavedRooms.sortName.localized) { [weak self] _ in
                self?.sortMode = .name
                self?.applyFiltersAndReload()
            }
        ])
        sortButton.showsMenuAsPrimaryAction = true

        viewModeControl.selectedSegmentIndex = 1
        viewModeControl.addTarget(self, action: #selector(viewModeChanged), for: .valueChanged)
        viewModeControl.backgroundColor = SpatialSenseTheme.Color.studioSurfaceRaised
        viewModeControl.selectedSegmentTintColor = SpatialSenseTheme.Color.primary
        viewModeControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        viewModeControl.setContentHuggingPriority(.required, for: .horizontal)
        viewModeControl.accessibilityLabel = L10n.SavedRooms.listView.localized

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        toolbarRow.addArrangedSubview(sortButton)
        toolbarRow.addArrangedSubview(spacer)
        toolbarRow.addArrangedSubview(viewModeControl)
    }

    private func updateNavigationButtons() {
        if isSelectMode {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: L10n.Common.cancel.localized,
                style: .plain,
                target: self,
                action: #selector(toggleSelectMode)
            )
        } else {
            let selectButton = UIBarButtonItem(
                title: L10n.Common.edit.localized,
                style: .plain,
                target: self,
                action: #selector(toggleSelectMode)
            )
            selectButton.isEnabled = !allCaptures.isEmpty
            let addButton = UIBarButtonItem(
                image: UIImage(systemName: "plus.circle.fill"),
                style: .plain,
                target: self,
                action: #selector(startNewScan)
            )
            addButton.accessibilityLabel = L10n.Home.NewScan.title.localized
            navigationItem.rightBarButtonItems = [addButton, selectButton]
        }
    }

    private func updateSelectionToolbar() {
        let selectedCount = selectedCaptureIDs.count
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        let countLabel = UILabel()
        countLabel.text = L10n.SavedRooms.selectedCount.localized(selectedCount)
        countLabel.font = SpatialSenseTheme.Font.caption
        countLabel.textColor = SpatialSenseTheme.Color.adaptiveSecondaryText
        let countItem = UIBarButtonItem(customView: countLabel)

        let deleteButton = UIBarButtonItem(
            title: L10n.SavedRooms.deleteSelected.localized,
            style: .plain,
            target: self,
            action: #selector(deleteSelectedRooms)
        )
        deleteButton.tintColor = SpatialSenseTheme.Color.destructive
        deleteButton.isEnabled = selectedCount > 0

        let exportButton = UIBarButtonItem(
            title: L10n.SavedRooms.exportSelected.localized,
            style: .plain,
            target: self,
            action: #selector(exportSelectedRooms)
        )
        exportButton.isEnabled = allCaptures.contains {
            guard selectedCaptureIDs.contains($0.id) else { return false }
            if case .room = $0 { return true }
            return false
        }

        selectionToolbar.setItems([deleteButton, flexSpace, countItem, flexSpace, exportButton], animated: true)
    }

    // MARK: - Data

    private func loadLibraryItems() {
        let rooms = RoomStorageManager.shared.getSavedRooms().map(LibraryCaptureItem.room)
        let pointClouds = PointCloudStorageManager.shared.getSavedPointClouds().map(LibraryCaptureItem.pointCloud)
        allCaptures = rooms + pointClouds
        applyFiltersAndReload()
        updateNavigationButtons()
    }

    private func applyFiltersAndReload() {
        var captures = allCaptures

        if !searchQuery.isEmpty {
            captures = captures.filter { item in
                switch item {
                case .room(let room):
                    return room.name.localizedCaseInsensitiveContains(searchQuery)
                        || room.summary.localizedCaseInsensitiveContains(searchQuery)
                        || (room.notes?.localizedCaseInsensitiveContains(searchQuery) ?? false)
                case .pointCloud(let pointCloud):
                    return pointCloud.name.localizedCaseInsensitiveContains(searchQuery)
                }
            }
        }

        switch sortMode {
        case .newest:
            captures.sort { $0.date > $1.date }
        case .oldest:
            captures.sort { $0.date < $1.date }
        case .name:
            captures.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        filteredCaptures = captures
        updateSortButtonTitle()
        renderCaptures()
    }

    private func updateSortButtonTitle() {
        let title: String
        switch sortMode {
        case .newest: title = L10n.SavedRooms.sortNewest.localized
        case .oldest: title = L10n.SavedRooms.sortOldest.localized
        case .name: title = L10n.SavedRooms.sortName.localized
        }
        let existingMenu = sortButton.menu
        sortButton.configuration = SpatialSenseTheme.secondaryButtonConfiguration(
            title: title,
            icon: "arrow.up.arrow.down"
        )
        sortButton.configuration?.baseForegroundColor = .white
        sortButton.configuration?.background.backgroundColor = SpatialSenseTheme.Color.studioSurfaceRaised
        sortButton.configuration?.background.strokeColor = SpatialSenseTheme.Color.studioBorder
        sortButton.menu = existingMenu
        sortButton.showsMenuAsPrimaryAction = true
    }

    private func renderCaptures() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if filteredCaptures.isEmpty {
            emptyLabel.isHidden = false
            emptyLabel.text = allCaptures.isEmpty
                ? "\(L10n.SavedRooms.emptyTitle.localized)\n\(L10n.SavedRooms.empty.localized)"
                : L10n.SavedRooms.noResults.localized
            return
        }

        emptyLabel.isHidden = true

        if viewMode == .list {
            lastRenderedColumnCount = 1
            for capture in filteredCaptures {
                contentStack.addArrangedSubview(makeCard(for: capture))
            }
        } else {
            let columnCount = preferredGridColumnCount
            lastRenderedColumnCount = columnCount
            var index = 0
            while index < filteredCaptures.count {
                let row = UIStackView()
                row.axis = .horizontal
                row.spacing = SpatialSenseTheme.Space.md
                row.distribution = .fillEqually

                let first = makeCard(for: filteredCaptures[index])
                row.addArrangedSubview(first)

                if columnCount == 2, index + 1 < filteredCaptures.count {
                    row.addArrangedSubview(makeCard(for: filteredCaptures[index + 1]))
                } else if columnCount == 2 {
                    let spacer = UIView()
                    row.addArrangedSubview(spacer)
                }

                contentStack.addArrangedSubview(row)
                index += columnCount
            }
        }
    }

    private var preferredGridColumnCount: Int {
        view.bounds.width >= 700 ? 2 : 1
    }

    private func makeCard(for capture: LibraryCaptureItem) -> ScanCardView {
        switch capture {
        case .room(let room):
            return makeCard(for: room)
        case .pointCloud(let pointCloud):
            let card = ScanCardView()
            card.configure(with: pointCloud, showsOverflow: !isSelectMode)
            card.setSelectedStyle(selectedCaptureIDs.contains(pointCloud.id))
            card.onTap = { [weak self] in
                guard let self else { return }
                if self.isSelectMode {
                    if self.selectedCaptureIDs.contains(pointCloud.id) {
                        self.selectedCaptureIDs.remove(pointCloud.id)
                    } else {
                        self.selectedCaptureIDs.insert(pointCloud.id)
                    }
                    self.updateSelectionToolbar()
                    self.renderCaptures()
                } else {
                    self.openPointCloud(pointCloud)
                }
            }
            card.onOverflow = { [weak self] in
                self?.showPointCloudMenu(for: pointCloud)
            }
            return card
        }
    }

    private func makeCard(for room: SavedRoom) -> ScanCardView {
        let card = ScanCardView()
        card.configure(
            with: room,
            statusText: L10n.Home.ScanStatus.local.localized,
            showsOverflow: !isSelectMode
        )
        card.setSelectedStyle(selectedCaptureIDs.contains(room.id))

        card.onTap = { [weak self] in
            guard let self else { return }
            if self.isSelectMode {
                if self.selectedCaptureIDs.contains(room.id) {
                    self.selectedCaptureIDs.remove(room.id)
                } else {
                    self.selectedCaptureIDs.insert(room.id)
                }
                self.updateSelectionToolbar()
                self.renderCaptures()
            } else {
                self.openRoom(room)
            }
        }

        card.onOverflow = { [weak self] in
            self?.showRoomMenu(for: room)
        }

        return card
    }

    // MARK: - Actions

    @objc private func startNewScan() {
        guard RoomCaptureSession.isSupported else { return }
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let controller = storyboard.instantiateViewController(
            withIdentifier: "RoomCaptureViewNavigationController"
        ) as? UINavigationController else { return }
        SpatialSenseTheme.configureNavigationBar(controller.navigationBar, immersive: true)
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }

    @objc private func dismissView() {
        if isSelectMode {
            toggleSelectMode()
        } else {
            dismiss(animated: true)
        }
    }

    @objc private func toggleSelectMode() {
        isSelectMode.toggle()
        selectedCaptureIDs.removeAll()
        selectionToolbar.isHidden = !isSelectMode
        selectionToolbarHeight?.constant = isSelectMode ? 44 : 0
        updateNavigationButtons()
        updateSelectionToolbar()
        renderCaptures()
    }

    @objc private func viewModeChanged() {
        viewMode = viewModeControl.selectedSegmentIndex == 0 ? .list : .grid
        viewModeControl.accessibilityLabel = viewMode == .list
            ? L10n.SavedRooms.listView.localized
            : L10n.SavedRooms.gridView.localized
        renderCaptures()
    }

    @objc private func deleteSelectedRooms() {
        guard !selectedCaptureIDs.isEmpty else { return }
        let count = selectedCaptureIDs.count
        let alert = UIAlertController(
            title: L10n.SavedRooms.DeleteSelected.title.localized,
            message: L10n.SavedRooms.DeleteSelected.message.localized(count),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Common.cancel.localized, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.Common.delete.localized, style: .destructive) { [weak self] _ in
            self?.performBatchDelete()
        })
        present(alert, animated: true)
    }

    private func performBatchDelete() {
        let capturesToDelete = allCaptures.filter { selectedCaptureIDs.contains($0.id) }
        var failedCaptureIDs = Set<UUID>()
        var failures: [(name: String, error: Error)] = []

        for capture in capturesToDelete {
            do {
                switch capture {
                case .room(let room):
                    try RoomStorageManager.shared.deleteRoom(room)
                case .pointCloud(let pointCloud):
                    try PointCloudStorageManager.shared.delete(pointCloud)
                }
            } catch {
                failedCaptureIDs.insert(capture.id)
                failures.append((capture.name, error))
            }
        }

        selectedCaptureIDs = failedCaptureIDs
        loadLibraryItems()
        if !failures.isEmpty {
            updateSelectionToolbar()
            let details = failures.map { "\($0.name): \($0.error.localizedDescription)" }.joined(separator: "\n")
            showError(
                "\(L10n.SavedRooms.deleteError.localized) "
                    + "(\(failures.count)/\(capturesToDelete.count))\n\(details)"
            )
        } else if allCaptures.isEmpty && isSelectMode {
            toggleSelectMode()
        } else {
            updateSelectionToolbar()
        }
    }

    @objc private func exportSelectedRooms() {
        let roomsToExport = allCaptures.compactMap { item -> SavedRoom? in
            guard selectedCaptureIDs.contains(item.id) else { return nil }
            if case .room(let room) = item { return room }
            return nil
        }
        guard !roomsToExport.isEmpty else { return }
        do {
            let exportURL = try RoomStorageManager.shared.exportMultipleRooms(roomsToExport)
            shareItems([exportURL])
        } catch {
            showError("Failed to export rooms: \(error.localizedDescription)")
        }
    }

    private func openRoom(_ room: SavedRoom) {
        let viewerVC = RoomViewerViewController(savedRoom: room)
        let navController = UINavigationController(rootViewController: viewerVC)
        SpatialSenseTheme.configureNavigationBar(navController.navigationBar, immersive: true)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }

    private func showRoomMenu(for room: SavedRoom) {
        let alert = UIAlertController(title: room.name, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: L10n.FloorPlan.view.localized, style: .default) { [weak self] _ in
            self?.openRoom(room)
        })
        alert.addAction(UIAlertAction(title: L10n.Common.edit.localized, style: .default) { [weak self] _ in
            self?.editRoom(room)
        })
        alert.addAction(UIAlertAction(title: L10n.Common.share.localized, style: .default) { [weak self] _ in
            self?.showExportOptions(for: room)
        })
        alert.addAction(UIAlertAction(title: L10n.Common.delete.localized, style: .destructive) { [weak self] _ in
            self?.confirmDelete(room)
        })
        alert.addAction(UIAlertAction(title: L10n.Common.cancel.localized, style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    private func confirmDelete(_ room: SavedRoom) {
        let alert = UIAlertController(
            title: L10n.SavedRooms.DeleteConfirm.title.localized,
            message: L10n.SavedRooms.DeleteConfirm.message.localized(room.name),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Common.cancel.localized, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.Common.delete.localized, style: .destructive) { [weak self] _ in
            guard let self else { return }
            do {
                try RoomStorageManager.shared.deleteRoom(room)
                self.loadLibraryItems()
            } catch {
                self.showError(
                    "\(L10n.SavedRooms.deleteError.localized): \(error.localizedDescription)"
                )
            }
        })
        present(alert, animated: true)
    }

    private func editRoom(_ room: SavedRoom) {
        let alert = UIAlertController(title: L10n.Common.edit.localized, message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = room.name
            textField.placeholder = L10n.SavedRooms.roomNamePlaceholder.localized
        }
        alert.addTextField { textField in
            textField.text = room.notes
            textField.placeholder = "Notes (optional)"
        }
        alert.addAction(UIAlertAction(title: L10n.Common.save.localized, style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let nameField = alert?.textFields?[0],
                  let notesField = alert?.textFields?[1] else { return }
            var updatedRoom = room
            updatedRoom.name = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? room.name
            updatedRoom.notes = notesField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            if updatedRoom.notes?.isEmpty == true { updatedRoom.notes = nil }
            do {
                try RoomStorageManager.shared.updateRoom(updatedRoom)
                self.loadLibraryItems()
            } catch {
                self.showError("Failed to update room: \(error.localizedDescription)")
            }
        })
        alert.addAction(UIAlertAction(title: L10n.Common.cancel.localized, style: .cancel))
        present(alert, animated: true)
    }

    private func openPointCloud(_ pointCloud: SavedPointCloud) {
        let controller = PointCloudViewerViewController(capture: pointCloud)
        let navController = UINavigationController(rootViewController: controller)
        SpatialSenseTheme.configureNavigationBar(navController.navigationBar, immersive: true)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }

    private func showPointCloudMenu(for pointCloud: SavedPointCloud) {
        let alert = UIAlertController(title: pointCloud.name, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "View Point Cloud", style: .default) { [weak self] _ in
            self?.openPointCloud(pointCloud)
        })
        alert.addAction(UIAlertAction(title: "Share PCD", style: .default) { [weak self] _ in
            self?.sharePointCloud(pointCloud)
        })
        alert.addAction(UIAlertAction(title: L10n.Common.delete.localized, style: .destructive) { [weak self] _ in
            self?.confirmDeletePointCloud(pointCloud)
        })
        alert.addAction(UIAlertAction(title: L10n.Common.cancel.localized, style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    private func confirmDeletePointCloud(_ pointCloud: SavedPointCloud) {
        let alert = UIAlertController(
            title: L10n.SavedRooms.DeleteConfirm.title.localized,
            message: L10n.SavedRooms.DeleteConfirm.message.localized(pointCloud.name),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Common.cancel.localized, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.Common.delete.localized, style: .destructive) { [weak self] _ in
            guard let self else { return }
            do {
                try PointCloudStorageManager.shared.delete(pointCloud)
                self.loadLibraryItems()
            } catch {
                self.showError(
                    "\(L10n.SavedRooms.deleteError.localized): \(error.localizedDescription)"
                )
            }
        })
        present(alert, animated: true)
    }

    private func sharePointCloud(_ pointCloud: SavedPointCloud) {
        guard let url = try? PointCloudStorageManager.shared.fileURL(for: pointCloud) else { return }
        shareItems([url])
    }

    private func showExportOptions(for room: SavedRoom) {
        let alert = UIAlertController(
            title: room.name,
            message: L10n.Export.chooseExport.localized,
            preferredStyle: .actionSheet
        )

        let usdzURL = RoomStorageManager.shared.getUsdzURL(for: room)
        if FileManager.default.fileExists(atPath: usdzURL.path) {
            alert.addAction(UIAlertAction(title: L10n.Export.usdz.localized, style: .default) { [weak self] _ in
                self?.shareItems([usdzURL])
            })
            alert.addAction(UIAlertAction(title: L10n.Export.obj.localized, style: .default) { [weak self] _ in
                self?.exportAndShare(room: room, format: .obj)
            })
            alert.addAction(UIAlertAction(title: L10n.Export.stl.localized, style: .default) { [weak self] _ in
                self?.exportAndShare(room: room, format: .stl)
            })
            alert.addAction(UIAlertAction(title: L10n.Export.ifc.localized, style: .default) { [weak self] _ in
                self?.exportAndShare(room: room, format: .ifc)
            })
        }

        if RoomStorageManager.shared.loadFloorPlanData(for: room) != nil {
            alert.addAction(UIAlertAction(title: L10n.Export.svg.localized, style: .default) { [weak self] _ in
                self?.exportAndShare(room: room, format: .svg)
            })
            alert.addAction(UIAlertAction(title: L10n.Export.dxf.localized, style: .default) { [weak self] _ in
                self?.exportAndShare(room: room, format: .dxf)
            })
        }

        if let floorPlanImage = RoomStorageManager.shared.getFloorPlanImage(for: room) {
            alert.addAction(UIAlertAction(title: L10n.Export.png.localized, style: .default) { [weak self] _ in
                self?.shareItems([floorPlanImage])
            })
        }

        if FileManager.default.fileExists(atPath: usdzURL.path),
           let floorPlanImage = RoomStorageManager.shared.getFloorPlanImage(for: room) {
            alert.addAction(UIAlertAction(title: L10n.Export.both.localized, style: .default) { [weak self] _ in
                self?.shareItems([usdzURL, floorPlanImage])
            })
        }

        if room.hasFloorPlan {
            alert.addAction(UIAlertAction(title: L10n.FloorPlan.view.localized, style: .default) { [weak self] _ in
                self?.showFloorPlanPreview(for: room)
            })
        }

        alert.addAction(UIAlertAction(title: L10n.Common.cancel.localized, style: .cancel))
        alert.popoverPresentationController?.sourceView = view
        present(alert, animated: true)
    }

    private enum ExportFormat {
        case obj, stl, svg, dxf, ifc
    }

    private func exportAndShare(room: SavedRoom, format: ExportFormat) {
        let loadingAlert = UIAlertController(title: L10n.Export.processing.localized, message: nil, preferredStyle: .alert)
        present(loadingAlert, animated: true)

        Task { @MainActor in
            do {
                let fileURL: URL
                switch format {
                case .obj: fileURL = try RoomStorageManager.shared.exportToOBJ(for: room)
                case .stl: fileURL = try RoomStorageManager.shared.exportToSTL(for: room)
                case .svg: fileURL = try RoomStorageManager.shared.exportToSVG(for: room)
                case .dxf: fileURL = try RoomStorageManager.shared.exportToDXF(for: room)
                case .ifc: fileURL = try RoomStorageManager.shared.exportToIFC(for: room)
                }
                loadingAlert.dismiss(animated: true) {
                    self.shareItems([fileURL])
                }
            } catch {
                loadingAlert.dismiss(animated: true) {
                    self.showError(L10n.Export.error.localized)
                }
            }
        }
    }

    private func shareItems(_ items: [Any]) {
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = view
        present(activityVC, animated: true)
    }

    private func showFloorPlanPreview(for room: SavedRoom) {
        guard let image = RoomStorageManager.shared.getFloorPlanImage(for: room) else {
            showError(L10n.FloorPlan.notFound.localized)
            return
        }
        let previewVC = FloorPlanPreviewViewController(image: image, roomName: room.name)
        let navController = UINavigationController(rootViewController: previewVC)
        SpatialSenseTheme.configureNavigationBar(navController.navigationBar, immersive: true)
        present(navController, animated: true)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: L10n.Common.error.localized, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.Common.ok.localized, style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UISearchBarDelegate

extension SavedRoomsViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        applyFiltersAndReload()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - FloorPlanPreviewViewController

class FloorPlanPreviewViewController: UIViewController {

    private let imageView = UIImageView()
    private let image: UIImage
    private let roomName: String

    init(image: UIImage, roomName: String) {
        self.image = image
        self.roomName = roomName
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        title = roomName
        view.backgroundColor = SpatialSenseTheme.Color.immersive

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissView)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(shareImage)
        )

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.image = image
        imageView.backgroundColor = SpatialSenseTheme.Color.surfaceElevated
        imageView.layer.cornerRadius = SpatialSenseTheme.Radius.md
        imageView.clipsToBounds = true
        view.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: SpatialSenseTheme.Space.md),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SpatialSenseTheme.Space.md),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SpatialSenseTheme.Space.md),
            imageView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -SpatialSenseTheme.Space.md)
        ])
    }

    @objc private func dismissView() {
        dismiss(animated: true)
    }

    @objc private func shareImage() {
        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        activityVC.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(activityVC, animated: true)
    }
}
