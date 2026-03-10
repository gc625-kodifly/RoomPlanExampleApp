//
//  HelpViewController.swift
//  RoomPlanSimple
//
//  Comprehensive help and feature documentation
//

import UIKit

class HelpViewController: UITableViewController {

    // MARK: - Types

    private enum Section: Int, CaseIterable {
        case gettingStarted
        case icloudSetup
        case scanning
        case features
        case export
        case tips
        case troubleshooting

        var title: String {
            switch self {
            case .gettingStarted: return L10n.Help.gettingStarted.localized
            case .icloudSetup: return L10n.Help.icloudSetup.localized
            case .scanning: return L10n.Help.scanning.localized
            case .features: return L10n.Home.features.localized
            case .export: return L10n.Help.exporting.localized
            case .tips: return L10n.Help.tips.localized
            case .troubleshooting: return L10n.Help.troubleshooting.localized
            }
        }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.Help.title.localized

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismiss(_:))
        )

        tableView.register(HelpCell.self, forCellReuseIdentifier: "HelpCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.estimatedRowHeight = 100
        tableView.rowHeight = UITableView.automaticDimension
    }

    @objc private func dismiss(_ sender: Any) {
        dismiss(animated: true)
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionType = Section(rawValue: section) else { return 0 }

        switch sectionType {
        case .gettingStarted: return 1
        case .icloudSetup: return 1
        case .scanning: return 1
        case .features: return 5
        case .export: return 1
        case .tips: return 5
        case .troubleshooting: return 4
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.title
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch section {
        case .gettingStarted:
            return getGettingStartedCell(at: indexPath)
        case .icloudSetup:
            return getICloudSetupCell(at: indexPath)
        case .scanning:
            return getScanningCell(at: indexPath)
        case .features:
            return getFeaturesCell(at: indexPath)
        case .export:
            return getExportCell(at: indexPath)
        case .tips:
            return getTipsCell(at: indexPath)
        case .troubleshooting:
            return getTroubleshootingCell(at: indexPath)
        }
    }

    // MARK: - Cell Configuration

    private func getGettingStartedCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HelpCell", for: indexPath) as! HelpCell
        cell.configure(
            icon: "play.circle.fill",
            title: L10n.Onboarding.welcome.localized,
            description: L10n.Help.gettingStartedContent.localized
        )
        return cell
    }

    private func getICloudSetupCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HelpCell", for: indexPath) as! HelpCell
        cell.configure(
            icon: "icloud.circle.fill",
            title: L10n.Help.icloudSetup.localized,
            description: L10n.Help.icloudSetupContent.localized
        )
        return cell
    }

    private func getScanningCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HelpCell", for: indexPath) as! HelpCell
        cell.configure(
            icon: "camera.viewfinder",
            title: L10n.Help.scanning.localized,
            description: L10n.Help.scanningContent.localized
        )
        return cell
    }

    private func getFeaturesCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HelpCell", for: indexPath) as! HelpCell

        let features = [
            ("cube.transparent.fill", L10n.Help.feature3DTitle.localized, L10n.Help.feature3DDesc.localized),
            ("wifi", L10n.Help.featureWiFiTitle.localized, L10n.Help.featureWiFiDesc.localized),
            ("camera.fill", L10n.Help.featurePhotoTitle.localized, L10n.Help.featurePhotoDesc.localized),
            ("square.and.arrow.up", L10n.Help.featureExportTitle.localized, L10n.Help.featureExportDesc.localized),
            ("icloud.fill", L10n.Help.featureICloudTitle.localized, L10n.Help.featureICloudDesc.localized)
        ]

        let feature = features[indexPath.row]
        cell.configure(icon: feature.0, title: feature.1, description: feature.2)
        return cell
    }

    private func getExportCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HelpCell", for: indexPath) as! HelpCell
        cell.configure(
            icon: "square.and.arrow.up.fill",
            title: L10n.Help.exporting.localized,
            description: L10n.Help.exportingContent.localized
        )
        return cell
    }

    private func getTipsCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HelpCell", for: indexPath) as! HelpCell

        let tips = [
            ("lightbulb.fill", L10n.Help.tipLightingTitle.localized, L10n.Help.tipLightingDesc.localized),
            ("tortoise.fill", L10n.Help.tipSlowTitle.localized, L10n.Help.tipSlowDesc.localized),
            ("arrow.triangle.2.circlepath", L10n.Help.tipRetryTitle.localized, L10n.Help.tipRetryDesc.localized),
            ("square.stack.3d.up.fill", L10n.Help.tipSaveTitle.localized, L10n.Help.tipSaveDesc.localized),
            ("chart.xyaxis.line", L10n.Help.tipMeasureTitle.localized, L10n.Help.tipMeasureDesc.localized)
        ]

        let tip = tips[indexPath.row]
        cell.configure(icon: tip.0, title: tip.1, description: tip.2)
        return cell
    }

    private func getTroubleshootingCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HelpCell", for: indexPath) as! HelpCell

        let issues = [
            ("exclamationmark.triangle.fill", L10n.Help.troubleNotStartingTitle.localized, L10n.Help.troubleNotStartingDesc.localized),
            ("camera.metering.partial", L10n.Help.troublePoorQualityTitle.localized, L10n.Help.troublePoorQualityDesc.localized),
            ("internaldrive.fill", L10n.Help.troubleDisappearedTitle.localized, L10n.Help.troubleDisappearedDesc.localized),
            ("wifi.slash", L10n.Help.troubleWiFiTitle.localized, L10n.Help.troubleWiFiDesc.localized)
        ]

        let issue = issues[indexPath.row]
        cell.configure(icon: issue.0, title: issue.1, description: issue.2)
        return cell
    }
}

// MARK: - HelpCell

private class HelpCell: UITableViewCell {

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        selectionStyle = .none

        iconView.tintColor = .systemBlue
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        descriptionLabel.font = .systemFont(ofSize: 15)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.numberOfLines = 0
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(descriptionLabel)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            descriptionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            descriptionLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    func configure(icon: String, title: String, description: String) {
        iconView.image = UIImage(systemName: icon)
        titleLabel.text = title
        descriptionLabel.text = description
    }
}
