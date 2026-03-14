import Foundation
import Carbon

enum AppTab: String, CaseIterable, Identifiable, Codable, Sendable {
    case home
    case dictionary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .dictionary: return "Dictionary"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .dictionary: return "book.closed"
        }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable, Codable, Sendable {
    case preferences
    case transcription
    case hotkeys
    case privacyPermissions = "privacy_permissions"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preferences: return "Preferences"
        case .transcription: return "Transcription"
        case .hotkeys: return "Hotkeys"
        case .privacyPermissions: return "Privacy & Permissions"
        }
    }

    var systemImage: String {
        switch self {
        case .preferences: return "slider.horizontal.3"
        case .transcription: return "waveform.and.mic"
        case .hotkeys: return "keyboard"
        case .privacyPermissions: return "lock.shield"
        }
    }

    var railGroupTitle: String {
        switch self {
        case .preferences, .hotkeys:
            return "APP"
        case .transcription:
            return "SPEECH & AI"
        case .privacyPermissions:
            return "PRIVACY"
        }
    }
}

enum ProviderID: String, CaseIterable, Identifiable, Codable, Sendable {
    case appleSpeech = "apple_speech"
    case whisper
    case parakeet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleSpeech: return "Apple Speech"
        case .whisper: return "Whisper"
        case .parakeet: return "Parakeet"
        }
    }
}

struct LanguageSelection: Hashable, Codable, Identifiable, Sendable {
    let identifier: String

    var id: String { identifier }

    static let auto = LanguageSelection(identifier: "auto")

    var isAuto: Bool {
        identifier == Self.auto.identifier
    }

    var title: String {
        if isAuto { return "Auto-detect" }
        return Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }
}

struct KeyboardShortcut: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let defaultShortcut = KeyboardShortcut(
        keyCode: 49,
        modifiers: UInt32(cmdKey | optionKey)
    )

    var isEmpty: Bool {
        modifiers == 0 && keyCode == 0
    }
}

enum OverlayStatus: Equatable, Sendable {
    case idle
    case recording
    case processing
    case success(String)
    case error(String)
}

enum RuntimeState: String, Equatable, Sendable {
    case stopped
    case starting
    case ready
    case failed
}

struct ProviderAvailability: Equatable, Sendable {
    var isAvailable: Bool
    var reason: String?
}

enum ProviderReadinessKind: String, Equatable, Sendable {
    case ready
    case missingLanguage
    case missingModel
    case missingAsset
    case installing
    case unavailable
    case permissionRequired
    case binaryMissing
}

struct ProviderReadiness: Equatable, Sendable {
    var kind: ProviderReadinessKind
    var message: String
    var actionTitle: String?

    var isReady: Bool {
        kind == .ready
    }

    static let ready = ProviderReadiness(kind: .ready, message: "Ready.", actionTitle: nil)
}

enum OperatingSystemFamily: String, CaseIterable, Codable, Sendable {
    case macOS = "macos"
    case windows

    var title: String {
        switch self {
        case .macOS:
            return "macOS"
        case .windows:
            return "Windows"
        }
    }
}

enum CPUArchitecture: String, CaseIterable, Codable, Sendable {
    case arm64
    case x86_64

    var title: String {
        rawValue
    }
}

enum AcceleratorClass: String, CaseIterable, Codable, Sendable {
    case none
    case appleSilicon = "apple_silicon"
    case nvidiaCUDA = "nvidia_cuda"

    var title: String {
        switch self {
        case .none:
            return "None"
        case .appleSilicon:
            return "Apple Silicon"
        case .nvidiaCUDA:
            return "NVIDIA CUDA"
        }
    }
}

struct SystemVersionInfo: Equatable, Codable, Sendable {
    var major: Int
    var minor: Int
    var patch: Int

    var title: String {
        "\(major).\(minor).\(patch)"
    }
}

struct SystemProfile: Equatable, Codable, Sendable {
    var osFamily: OperatingSystemFamily
    var osVersion: SystemVersionInfo
    var architecture: CPUArchitecture
    var accelerator: AcceleratorClass

    static var current: SystemProfile {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #if os(macOS)
        let osFamily: OperatingSystemFamily = .macOS
        #elseif os(Windows)
        let osFamily: OperatingSystemFamily = .windows
        #else
        let osFamily: OperatingSystemFamily = .macOS
        #endif

        #if arch(arm64)
        let architecture: CPUArchitecture = .arm64
        let accelerator: AcceleratorClass = .appleSilicon
        #elseif arch(x86_64)
        let architecture: CPUArchitecture = .x86_64
        let accelerator: AcceleratorClass = .none
        #else
        let architecture: CPUArchitecture = .x86_64
        let accelerator: AcceleratorClass = .none
        #endif

        return SystemProfile(
            osFamily: osFamily,
            osVersion: SystemVersionInfo(major: version.majorVersion, minor: version.minorVersion, patch: version.patchVersion),
            architecture: architecture,
            accelerator: accelerator
        )
    }

    var summary: String {
        "\(osFamily.title) \(osVersion.title) • \(architecture.title) • \(accelerator.title)"
    }
}

struct CapabilityRequirement: Equatable, Codable, Sendable {
    var allowedOSFamilies: [OperatingSystemFamily]
    var allowedArchitectures: [CPUArchitecture]
    var requiredAccelerators: [AcceleratorClass]

    func supports(_ profile: SystemProfile) -> Bool {
        let osSupported = allowedOSFamilies.isEmpty || allowedOSFamilies.contains(profile.osFamily)
        let architectureSupported = allowedArchitectures.isEmpty || allowedArchitectures.contains(profile.architecture)
        let acceleratorSupported = requiredAccelerators.isEmpty || requiredAccelerators.contains(profile.accelerator)
        return osSupported && architectureSupported && acceleratorSupported
    }
}

enum CapabilityStatusKind: String, Codable, Sendable {
    case available
    case unsupported
    case supportedButNotReady = "supported_but_not_ready"

    var title: String {
        switch self {
        case .available:
            return "Available"
        case .unsupported:
            return "Unsupported"
        case .supportedButNotReady:
            return "Needs Setup"
        }
    }
}

struct CapabilityStatus: Equatable, Codable, Sendable {
    var kind: CapabilityStatusKind
    var reason: String?
    var actionTitle: String?

    static let available = CapabilityStatus(kind: .available, reason: nil, actionTitle: nil)

    var isAvailable: Bool {
        kind == .available
    }

    var isSupported: Bool {
        kind != .unsupported
    }

    var supportsSetupAction: Bool {
        kind == .supportedButNotReady && actionTitle != nil
    }

    var detail: String {
        reason ?? kind.title
    }
}

struct ProviderCapabilityDescriptor: Equatable, Codable, Sendable {
    var provider: ProviderID
    var title: String
    var requirements: CapabilityRequirement
    var unsupportedReason: String
}

enum FeatureID: String, CaseIterable, Identifiable, Codable, Sendable {
    case providerSelection = "provider_selection"
    case autoPaste = "auto_paste"
    case hotkeyCapture = "hotkey_capture"
    case modelManagement = "model_management"
    case appleSpeechAssets = "apple_speech_assets"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .providerSelection:
            return "Provider Selection"
        case .autoPaste:
            return "Auto-paste"
        case .hotkeyCapture:
            return "Hotkey Capture"
        case .modelManagement:
            return "Model Management"
        case .appleSpeechAssets:
            return "Apple Speech Assets"
        }
    }
}

struct FeatureCapabilityDescriptor: Equatable, Codable, Sendable {
    var feature: FeatureID
    var title: String
    var requirements: CapabilityRequirement
    var unsupportedReason: String
}

struct CapabilityManifest: Equatable, Codable, Sendable {
    var providers: [ProviderCapabilityDescriptor]
    var features: [FeatureCapabilityDescriptor]
}

struct DictionaryEntry: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var phrase: String
    var hint: String

    init(id: UUID = UUID(), phrase: String, hint: String = "") {
        self.id = id
        self.phrase = phrase
        self.hint = hint
    }
}

struct HistoryItem: Identifiable, Equatable, Sendable {
    var id: Int64
    var timestamp: Date
    var provider: String
    var language: String
    var originalText: String
    var finalPastedText: String
    var error: String?
}

struct HistoryDaySection: Identifiable, Equatable, Sendable {
    var bucketDate: Date
    var title: String
    var items: [HistoryItem]

    var id: Date { bucketDate }
}

enum HistorySectionBuilder {
    static func build(
        items: [HistoryItem],
        searchText: String,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [HistoryDaySection] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredItems: [HistoryItem]
        if trimmedSearch.isEmpty {
            filteredItems = items
        } else {
            let needle = trimmedSearch.localizedLowercase
            filteredItems = items.filter { item in
                let haystacks = [item.originalText, item.finalPastedText]
                return haystacks.contains { $0.localizedLowercase.contains(needle) }
            }
        }

        let grouped = Dictionary(grouping: filteredItems) { item in
            calendar.startOfDay(for: item.timestamp)
        }

        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        return grouped
            .map { bucketDate, bucketItems in
                let title: String
                if calendar.isDate(bucketDate, inSameDayAs: today) {
                    title = "Today"
                } else if calendar.isDate(bucketDate, inSameDayAs: yesterday) {
                    title = "Yesterday"
                } else {
                    title = bucketDate.formatted(date: .abbreviated, time: .omitted)
                }

                return HistoryDaySection(
                    bucketDate: bucketDate,
                    title: title,
                    items: bucketItems.sorted { $0.timestamp > $1.timestamp }
                )
            }
            .sorted { $0.bucketDate > $1.bucketDate }
    }
}

enum PasteMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case autoPaste = "auto_paste"
    case clipboardOnly = "clipboard_only"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .autoPaste: return "Auto-paste"
        case .clipboardOnly: return "Copy only"
        }
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var selectedProvider: ProviderID = .appleSpeech
    var preferredLanguageID: String = "en-US"
    var selectedWhisperModelID: String = "base"
    var selectedParakeetModelID: String = "parakeet-tdt-0.6b-v3"
    var hotkey: KeyboardShortcut = .defaultShortcut
    var pasteMode: PasteMode = .autoPaste
    var menuBarEnabled: Bool = true
    var showOverlay: Bool = true
    var onboardingCompleted: Bool = false
    var lastAppTab: AppTab = .home
    var lastSettingsTab: SettingsTab = .preferences

    var preferredLanguage: LanguageSelection {
        get { LanguageSelection(identifier: preferredLanguageID) }
        set { preferredLanguageID = newValue.identifier }
    }
}

struct PasteTarget: Sendable, Equatable {
    var appName: String?
    var bundleIdentifier: String?
    var processIdentifier: pid_t?
}

enum PasteResult: Equatable, Sendable {
    case pasted
    case copiedOnly(String)
    case failed(String)

    var message: String {
        switch self {
        case .pasted:
            return "Inserted."
        case .copiedOnly(let message), .failed(let message):
            return message
        }
    }
}

struct ModelDescriptor: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var provider: ProviderID
    var name: String
    var detail: String
    var sizeLabel: String
    var downloadURL: String
    var expectedSizeBytes: Int64?
    var fileName: String?
    var extractDirectory: String?
    var supportedLanguageIDs: [String]
    var recommended: Bool
}

enum ModelInstallState: Equatable, Sendable {
    case notInstalled
    case downloading(Double?)
    case installing
    case ready
    case failed(String)
}

struct ModelStatus: Identifiable, Equatable, Sendable {
    var descriptor: ModelDescriptor
    var state: ModelInstallState
    var location: URL?

    var id: String { descriptor.id }
}

enum InstalledAssetSource: String, Codable, Equatable, Sendable {
    case importedFromOpenWhisprCache = "imported_openwhispr_cache"
    case downloadedByVerbatim = "downloaded_by_verbatim"

    var title: String {
        switch self {
        case .importedFromOpenWhisprCache:
            return "Imported from OpenWhispr cache"
        case .downloadedByVerbatim:
            return "Downloaded by Verbatim"
        }
    }
}

struct RuntimeHealthSnapshot: Equatable, Sendable {
    var binaryName: String
    var binaryPresent: Bool
    var state: RuntimeState
    var endpoint: String?
    var lastCheck: Date?
    var lastError: String?
    var logFileName: String
}

struct ProviderDiagnosticStatus: Identifiable, Equatable, Sendable {
    var provider: ProviderID
    var capability: CapabilityStatus
    var availability: ProviderAvailability
    var readiness: ProviderReadiness
    var selectionDescription: String
    var selectionInstalled: Bool
    var selectionSource: InstalledAssetSource?
    var runtimeSnapshot: RuntimeHealthSnapshot?
    var lastCheck: Date?
    var lastError: String?

    var id: ProviderID { provider }
}

struct DiagnosticEvent: Identifiable, Equatable, Sendable {
    var id: UUID
    var timestamp: Date
    var category: String
    var message: String

    init(id: UUID = UUID(), timestamp: Date = .now, category: String, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.message = message
    }
}

struct TranscriptionResult: Equatable, Sendable {
    var originalText: String
    var finalText: String
    var provider: ProviderID
    var language: LanguageSelection
}

protocol TranscriptionProvider: Sendable {
    var id: ProviderID { get }
    func availability() async -> ProviderAvailability
    func readiness(for language: LanguageSelection) async -> ProviderReadiness
    func transcribe(
        audioFileURL: URL,
        language: LanguageSelection,
        dictionaryHints: [DictionaryEntry]
    ) async throws -> TranscriptionResult
}

protocol DownloadableModelProvider: Sendable {
    func modelStatuses() async -> [ModelStatus]
    func downloadModel(id: String) async throws
    func deleteModel(id: String) async throws
}

protocol LocaleAssetProvider: Sendable {
    func installedLanguages() async -> [LanguageSelection]
    func installAssets(for language: LanguageSelection) async throws
}

protocol RecordingManagerProtocol: AnyObject, Sendable {
    func startRecording() async throws
    func stopRecording() async throws -> URL
    func cancel()
}

protocol AudioNormalizationServiceProtocol: Sendable {
    func normalizeAudioFile(at sourceURL: URL) async throws -> URL
}

protocol PasteServiceProtocol: Sendable {
    func captureTarget() -> PasteTarget?
    func paste(
        text: String,
        to target: PasteTarget?,
        pasteMode: PasteMode,
        accessibilityGranted: Bool
    ) -> PasteResult
}

protocol HistoryStoreProtocol: AnyObject, Sendable {
    func fetchHistory(limit: Int) -> [HistoryItem]
    func save(
        provider: ProviderID,
        language: LanguageSelection,
        originalText: String,
        finalText: String,
        error: String?
    ) -> HistoryItem
    func deleteHistory(id: Int64)
    func clearHistory()
    func fetchDictionary() -> [DictionaryEntry]
    func upsertDictionary(entry: DictionaryEntry)
    func deleteDictionary(id: UUID)
    func resetAll()
}

protocol SettingsStoreProtocol: AnyObject, Sendable {
    var settings: AppSettings { get }
    func replace(_ settings: AppSettings)
}
