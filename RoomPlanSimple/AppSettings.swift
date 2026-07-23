/*
See LICENSE folder for this sample's licensing information.

Abstract:
App settings manager using UserDefaults.
*/

import Foundation

/// Manages app settings using UserDefaults
final class AppSettings {

    // MARK: - Singleton

    static let shared = AppSettings()
    private init() {}

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let autoSaveScans = "autoSaveScans"
        static let defaultExportFormat = "defaultExportFormat"
        static let showPhotosInFloorPlan = "showPhotosInFloorPlan"
        static let iCloudSyncEnabled = "iCloudSyncEnabled"
        static let appLanguage = "appLanguage"
    }

    // MARK: - Settings Properties

    /// Automatically save scans when completed (default: true)
    var autoSaveScans: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.autoSaveScans) == nil {
                return true  // Default to true
            }
            return UserDefaults.standard.bool(forKey: Keys.autoSaveScans)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.autoSaveScans)
            NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        }
    }

    /// Default export format
    var defaultExportFormat: String {
        get { UserDefaults.standard.string(forKey: Keys.defaultExportFormat) ?? "parametric" }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.defaultExportFormat)
            NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        }
    }

    /// Show photos overlay in floor plan
    var showPhotosInFloorPlan: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.showPhotosInFloorPlan) }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.showPhotosInFloorPlan)
            NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        }
    }

    /// Enable iCloud sync for saved rooms (default: false)
    var iCloudSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.iCloudSyncEnabled) }
        set {
            let oldValue = UserDefaults.standard.bool(forKey: Keys.iCloudSyncEnabled)
            UserDefaults.standard.set(newValue, forKey: Keys.iCloudSyncEnabled)
            NotificationCenter.default.post(name: .settingsDidChange, object: nil)
            // When iCloud sync is toggled ON, migrate existing rooms
            if newValue && newValue != oldValue {
                Task {
                    await migrateRoomsToNewLocation()
                }
            }
        }
    }

    // MARK: - Language Settings

    /// Supported languages
    enum AppLanguage: String, CaseIterable {
        case system = "system"
        case english = "en"
        case chinese = "zh-Hans"
        case russian = "ru"
        case german = "de"
        case french = "fr"
        case spanish = "es"
        case portugueseBR = "pt-BR"

        var displayName: String {
            switch self {
            case .system:
                return "System Default".localized
            case .english:
                return "English"
            case .chinese:
                return "简体中文"
            case .russian:
                return "Русский"
            case .german:
                return "Deutsch"
            case .french:
                return "Français"
            case .spanish:
                return "Español"
            case .portugueseBR:
                return "Português (Brasil)"
            }
        }
    }

    /// Current app language preference
    var appLanguage: AppLanguage {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: Keys.appLanguage),
                  let language = AppLanguage(rawValue: rawValue) else {
                return .system
            }
            return language
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.appLanguage)
            applyLanguage(newValue)
            NotificationCenter.default.post(name: .languageDidChange, object: nil)
        }
    }

    /// Apply the language setting
    private func applyLanguage(_ language: AppLanguage) {
        switch language {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .english:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        case .chinese:
            UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        case .russian:
            UserDefaults.standard.set(["ru"], forKey: "AppleLanguages")
        case .german:
            UserDefaults.standard.set(["de"], forKey: "AppleLanguages")
        case .french:
            UserDefaults.standard.set(["fr"], forKey: "AppleLanguages")
        case .spanish:
            UserDefaults.standard.set(["es"], forKey: "AppleLanguages")
        case .portugueseBR:
            UserDefaults.standard.set(["pt-BR"], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }

    // MARK: - iCloud Availability

    /// Check if iCloud is available on this device
    var isICloudAvailable: Bool {
        return FileManager.default.ubiquityIdentityToken != nil
    }

    // MARK: - Migration

    /// Migrate saved rooms when iCloud sync is toggled
    @MainActor
    private func migrateRoomsToNewLocation() async {
        // Perform migration from local storage to iCloud
        do {
            let migratedCount = try RoomStorageManager.shared.migrateToICloud()
            if migratedCount > 0 {
                print("✅ Migrated \(migratedCount) rooms to iCloud")
            }
        } catch {
            print("⚠️  Failed to migrate rooms: \(error)")
        }

        // Post notification to trigger UI refresh
        NotificationCenter.default.post(name: .iCloudSyncToggled, object: nil)
    }

    // MARK: - Reset

    /// Reset all settings to defaults
    func resetToDefaults() {
        autoSaveScans = true
        defaultExportFormat = "parametric"
        showPhotosInFloorPlan = false
        iCloudSyncEnabled = false
        appLanguage = .system
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let settingsDidChange = Notification.Name("settingsDidChange")
    static let iCloudSyncToggled = Notification.Name("iCloudSyncToggled")
    static let languageDidChange = Notification.Name("languageDidChange")
}
