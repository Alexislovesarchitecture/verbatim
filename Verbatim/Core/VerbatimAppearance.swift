import SwiftUI

enum AppSectionAccent {
    case cobalt
    case amber
    case mint
    case violet
}

enum VerbatimPanelTone {
    case frost
    case cream
    case inset
    case shell
    case rail
}

enum VerbatimPalette {
    static let ink = Color.primary
    static let mutedInk = Color.secondary
    static let shellTop = Color(red: 0.95, green: 0.96, blue: 0.99)
    static let shellBottom = Color(red: 0.82, green: 0.86, blue: 0.93)
    static let frostTop = Color.white.opacity(0.62)
    static let frostBottom = Color(red: 0.82, green: 0.86, blue: 0.93).opacity(0.20)
    static let creamTop = Color(red: 0.99, green: 0.98, blue: 0.94).opacity(0.82)
    static let creamBottom = Color(red: 0.95, green: 0.93, blue: 0.86).opacity(0.52)
    static let insetTop = Color.white.opacity(0.20)
    static let insetBottom = Color(red: 0.76, green: 0.81, blue: 0.89).opacity(0.10)
    static let railTop = Color.white.opacity(0.42)
    static let railBottom = Color(red: 0.83, green: 0.87, blue: 0.93).opacity(0.18)
}

extension AppSectionAccent {
    var tint: Color {
        switch self {
        case .cobalt: return Color(red: 0.33, green: 0.49, blue: 0.95)
        case .amber: return Color(red: 0.83, green: 0.62, blue: 0.27)
        case .mint: return Color(red: 0.31, green: 0.67, blue: 0.56)
        case .violet: return Color(red: 0.56, green: 0.42, blue: 0.90)
        }
    }

    var glow: Color {
        tint.opacity(0.22)
    }
}

private struct PlatformGlassButtonModifier: ViewModifier {
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if prominent {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.glass)
        }
    }
}

private struct PlatformLiquidCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tone: VerbatimPanelTone
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .modifier(PlatformLiquidSurfaceModifier(cornerRadius: cornerRadius, tone: tone))
    }
}

private struct PlatformInsetWellModifier: ViewModifier {
    let cornerRadius: CGFloat
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .modifier(PlatformLiquidSurfaceModifier(cornerRadius: cornerRadius, tone: .inset))
    }
}

private struct PlatformBadgeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .modifier(PlatformLiquidSurfaceModifier(cornerRadius: 999, tone: .inset))
    }
}

private struct PlatformSelectionPillModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let selected: Bool
    let accent: AppSectionAccent
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26.0, *) {
            content
                .background(
                    shape.fill(
                        selected
                        ? accent.glow.opacity(colorScheme == .dark ? 0.46 : 0.90)
                        : Color.white.opacity(colorScheme == .dark ? 0.04 : 0.12)
                    )
                )
                .overlay(
                    shape.strokeBorder(
                        selected ? accent.tint.opacity(0.35) : Color.white.opacity(colorScheme == .dark ? 0.08 : 0.16),
                        lineWidth: 1
                    )
                )
                .glassEffect(
                    .regular
                        .tint((selected ? accent.tint : Color.white).opacity(colorScheme == .dark ? 0.20 : 0.11))
                        .interactive(),
                    in: .rect(cornerRadius: cornerRadius)
                )
        } else {
            content
                .background(
                    shape.fill(selected ? accent.glow : Color.white.opacity(colorScheme == .dark ? 0.06 : 0.14))
                )
                .overlay(
                    shape.strokeBorder(
                        selected ? accent.tint.opacity(0.28) : Color.white.opacity(colorScheme == .dark ? 0.10 : 0.18),
                        lineWidth: 1
                    )
                )
        }
    }
}

private struct PlatformWindowChromeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content.containerBackground(.regularMaterial.opacity(0.90), for: .window)
        } else {
            content.containerBackground(.ultraThinMaterial.opacity(0.82), for: .window)
        }
    }
}

private struct PlatformLiquidSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let tone: VerbatimPanelTone

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            content
                .background(
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.18 : 0.26),
                                toneColor.opacity(colorScheme == .dark ? 0.30 : 0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .overlay(shape.strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.24), lineWidth: 1))
                .glassEffect(.regular.tint(toneColor.opacity(colorScheme == .dark ? 0.24 : 0.12)), in: .rect(cornerRadius: cornerRadius))
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 16, x: 0, y: 8)
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: legacyColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        }
    }

    private var toneColor: Color {
        switch tone {
        case .shell, .frost, .rail:
            return Color(red: 0.78, green: 0.84, blue: 0.96)
        case .cream:
            return Color(red: 0.99, green: 0.92, blue: 0.74)
        case .inset:
            return .white
        }
    }

    private var legacyColors: [Color] {
        switch tone {
        case .shell: return [VerbatimPalette.shellTop, VerbatimPalette.shellBottom]
        case .frost: return [VerbatimPalette.frostTop, VerbatimPalette.frostBottom]
        case .cream: return [VerbatimPalette.creamTop, VerbatimPalette.creamBottom]
        case .inset: return [VerbatimPalette.insetTop, VerbatimPalette.insetBottom]
        case .rail: return [VerbatimPalette.railTop, VerbatimPalette.railBottom]
        }
    }
}

extension View {
    func applyGlassButtonStyle(prominent: Bool = false) -> some View {
        modifier(PlatformGlassButtonModifier(prominent: prominent))
    }

    func applyLiquidCardStyle(
        cornerRadius: CGFloat = 30,
        tone: VerbatimPanelTone = .frost,
        padding: CGFloat = 20
    ) -> some View {
        modifier(PlatformLiquidCardModifier(cornerRadius: cornerRadius, tone: tone, padding: padding))
    }

    func applyInsetWellStyle(cornerRadius: CGFloat = 22, padding: CGFloat = 14) -> some View {
        modifier(PlatformInsetWellModifier(cornerRadius: cornerRadius, padding: padding))
    }

    func applyStatusBadgeEffect() -> some View {
        modifier(PlatformBadgeModifier())
    }

    func applySelectionPillStyle(
        selected: Bool,
        accent: AppSectionAccent = .cobalt,
        cornerRadius: CGFloat = 18
    ) -> some View {
        modifier(PlatformSelectionPillModifier(selected: selected, accent: accent, cornerRadius: cornerRadius))
    }

    func applyWindowChrome() -> some View {
        modifier(PlatformWindowChromeModifier())
    }
}

struct VerbatimGlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: Content

    init(spacing: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                stack
            }
        } else {
            stack
        }
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: spacing, content: { content })
    }
}
