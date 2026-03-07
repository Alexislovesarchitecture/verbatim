import Foundation

enum AppSectionAccent: String {
    case cobalt
    case amber
    case mint
    case violet
}

enum AppSection: String, CaseIterable, Identifiable {
    case home
    case dictionary
    case style

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .dictionary:
            return "Dictionary"
        case .style:
            return "Style"
        }
    }

    var shortTitle: String {
        switch self {
        case .home:
            return "Home"
        case .dictionary:
            return "Dictionary"
        case .style:
            return "Style"
        }
    }

    var subtitle: String {
        switch self {
        case .home:
            return "Capture, refine, and review transcripts in one place."
        case .dictionary:
            return "Teach Verbatim names, terms, and preferred replacements."
        case .style:
            return "Control cleanup style, prompt profiles, and routing rules."
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .home:
            return "Home"
        case .dictionary:
            return "Dictionary"
        case .style:
            return "Style"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            return "house"
        case .dictionary:
            return "book.closed"
        case .style:
            return "textformat"
        }
    }

    var accent: AppSectionAccent {
        switch self {
        case .home:
            return .cobalt
        case .dictionary:
            return .amber
        case .style:
            return .violet
        }
    }
}
