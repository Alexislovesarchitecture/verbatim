import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case workspace
    case transcriptionSettings
    case logicSettings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace:
            return "Workspace"
        case .transcriptionSettings:
            return "Transcription Model"
        case .logicSettings:
            return "Logic Model"
        }
    }

    var systemImage: String {
        switch self {
        case .workspace:
            return "waveform.and.mic"
        case .transcriptionSettings:
            return "waveform"
        case .logicSettings:
            return "brain"
        }
    }
}
