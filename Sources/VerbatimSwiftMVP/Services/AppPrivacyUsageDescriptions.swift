import Foundation

enum AppPrivacyUsageDescription: String {
    case microphone = "NSMicrophoneUsageDescription"
    case speechRecognition = "NSSpeechRecognitionUsageDescription"

    var missingMessage: String {
        switch self {
        case .microphone:
            return "This build is missing NSMicrophoneUsageDescription. Launch Verbatim from the Xcode app target instead of `swift run` when testing microphone capture."
        case .speechRecognition:
            return "This build is missing NSSpeechRecognitionUsageDescription. Launch Verbatim from the Xcode app target instead of `swift run` when testing Apple Speech."
        }
    }
}

enum AppPrivacyUsageDescriptionValidator {
    static func missingUsageDescription(_ usageDescription: AppPrivacyUsageDescription, bundle: Bundle = .main) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: usageDescription.rawValue) as? String,
              value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return usageDescription.missingMessage
        }
        return nil
    }
}
