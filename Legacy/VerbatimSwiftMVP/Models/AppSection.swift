import Foundation

enum AppSectionAccent: String {
    case cobalt
    case amber
    case mint
    case violet
}

enum AppSection: String, CaseIterable, Identifiable {
    case home

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "Home"
        }
    }

    var shortTitle: String {
        switch self {
        case .home:
            return "Home"
        }
    }

    var subtitle: String {
        switch self {
        case .home:
            return "Capture and review plain local transcripts."
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .home:
            return "Home"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            return "house"
        }
    }

    var accent: AppSectionAccent {
        switch self {
        case .home:
            return .cobalt
        }
    }
}
