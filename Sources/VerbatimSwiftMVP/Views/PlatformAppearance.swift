import SwiftUI

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
        case .cobalt:
            return Color(red: 0.33, green: 0.49, blue: 0.95)
        case .amber:
            return Color(red: 0.83, green: 0.62, blue: 0.27)
        case .mint:
            return Color(red: 0.31, green: 0.67, blue: 0.56)
        case .violet:
            return Color(red: 0.56, green: 0.42, blue: 0.90)
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

private struct PlatformShellModifier: ViewModifier {
    let cornerRadius: CGFloat
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .modifier(PlatformLiquidSurfaceModifier(cornerRadius: cornerRadius, tone: .shell))
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
        if #available(macOS 26.0, iOS 26.0, *) {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

            content
                .background(
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(nativeHighlightOpacity),
                                nativeFillColor.opacity(nativeFillOpacity)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .overlay(
                    shape.strokeBorder(strokeColor, lineWidth: strokeWidth)
                )
                .glassEffect(nativeGlass, in: .rect(cornerRadius: cornerRadius))
                .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowYOffset)
        } else {
            content.background(VerbatimPanelBackground(cornerRadius: cornerRadius, tone: tone))
        }
    }

    @available(macOS 26.0, iOS 26.0, *)
    private var nativeGlass: Glass {
        .regular.tint(nativeTint.opacity(nativeTintOpacity))
    }

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var nativeTint: Color {
        if isDarkMode {
            switch tone {
            case .shell:
                return Color(red: 0.30, green: 0.34, blue: 0.42)
            case .frost:
                return Color(red: 0.34, green: 0.38, blue: 0.46)
            case .rail:
                return Color(red: 0.28, green: 0.32, blue: 0.40)
            case .cream:
                return Color(red: 0.42, green: 0.39, blue: 0.33)
            case .inset:
                return Color(red: 0.24, green: 0.26, blue: 0.30)
            }
        } else {
            switch tone {
            case .frost, .shell, .rail:
                return Color(red: 0.78, green: 0.84, blue: 0.96)
            case .cream:
                return Color(red: 0.99, green: 0.92, blue: 0.74)
            case .inset:
                return Color.white
            }
        }
    }

    private var nativeFillColor: Color {
        if isDarkMode {
            switch tone {
            case .shell:
                return Color(red: 0.08, green: 0.09, blue: 0.12)
            case .frost:
                return Color(red: 0.11, green: 0.12, blue: 0.16)
            case .rail:
                return Color(red: 0.10, green: 0.11, blue: 0.15)
            case .cream:
                return Color(red: 0.18, green: 0.16, blue: 0.13)
            case .inset:
                return Color(red: 0.09, green: 0.10, blue: 0.14)
            }
        } else {
            switch tone {
            case .frost, .shell, .rail:
                return Color.white
            case .cream:
                return Color(red: 0.99, green: 0.95, blue: 0.84)
            case .inset:
                return Color.white
            }
        }
    }

    private var nativeTintOpacity: Double {
        if isDarkMode {
            switch tone {
            case .shell:
                return 0.34
            case .cream:
                return 0.24
            case .frost:
                return 0.28
            case .rail:
                return 0.24
            case .inset:
                return 0.18
            }
        } else {
            switch tone {
            case .shell:
                return 0.22
            case .cream:
                return 0.22
            case .frost:
                return 0.14
            case .rail:
                return 0.12
            case .inset:
                return 0.08
            }
        }
    }

    private var nativeFillOpacity: Double {
        if isDarkMode {
            switch tone {
            case .shell:
                return 0.36
            case .cream:
                return 0.28
            case .frost:
                return 0.30
            case .rail:
                return 0.26
            case .inset:
                return 0.20
            }
        } else {
            switch tone {
            case .shell:
                return 0.26
            case .cream:
                return 0.28
            case .frost:
                return 0.22
            case .rail:
                return 0.18
            case .inset:
                return 0.12
            }
        }
    }

    private var nativeHighlightOpacity: Double {
        if isDarkMode {
            switch tone {
            case .shell:
                return 0.16
            case .cream:
                return 0.14
            case .frost, .rail:
                return 0.12
            case .inset:
                return 0.08
            }
        } else {
            switch tone {
            case .shell:
                return 0.34
            case .cream:
                return 0.30
            case .frost, .rail:
                return 0.24
            case .inset:
                return 0.14
            }
        }
    }

    private var strokeColor: Color {
        if isDarkMode {
            switch tone {
            case .cream:
                return Color.white.opacity(0.20)
            case .shell:
                return Color.white.opacity(0.18)
            case .inset:
                return Color.white.opacity(0.10)
            case .frost, .rail:
                return Color.white.opacity(0.14)
            }
        } else {
            switch tone {
            case .cream:
                return Color.white.opacity(0.82)
            case .shell:
                return Color.white.opacity(0.44)
            case .inset:
                return Color.white.opacity(0.24)
            case .frost, .rail:
                return Color.white.opacity(0.34)
            }
        }
    }

    private var strokeWidth: CGFloat {
        switch tone {
        case .shell:
            return 1.2
        case .frost, .cream, .rail:
            return 1
        case .inset:
            return 0.8
        }
    }

    private var shadowColor: Color {
        if isDarkMode {
            switch tone {
            case .shell:
                return Color.black.opacity(0.30)
            case .cream:
                return Color.black.opacity(0.22)
            case .frost, .rail:
                return Color.black.opacity(0.18)
            case .inset:
                return Color.clear
            }
        } else {
            switch tone {
            case .shell:
                return Color.black.opacity(0.12)
            case .cream:
                return Color.black.opacity(0.08)
            case .frost, .rail:
                return Color.black.opacity(0.07)
            case .inset:
                return Color.clear
            }
        }
    }

    private var shadowRadius: CGFloat {
        switch tone {
        case .shell:
            return 18
        case .cream:
            return 12
        case .frost, .rail:
            return 8
        case .inset:
            return 0
        }
    }

    private var shadowYOffset: CGFloat {
        switch tone {
        case .shell:
            return 8
        case .cream:
            return 5
        case .frost, .rail:
            return 3
        case .inset:
            return 0
        }
    }
}

private struct VerbatimPanelBackground: View {
    let cornerRadius: CGFloat
    let tone: VerbatimPanelTone

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        shape
            .fill(gradient)
            .background(.ultraThinMaterial, in: shape)
            .overlay(
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(highlightOpacity),
                                Color.white.opacity(0.05),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)
            )
            .overlay(
                shape
                    .strokeBorder(strokeColor, lineWidth: strokeWidth)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowYOffset)
    }

    private var gradient: LinearGradient {
        switch tone {
        case .frost:
            return LinearGradient(
                colors: [VerbatimPalette.frostTop, VerbatimPalette.frostBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .cream:
            return LinearGradient(
                colors: [VerbatimPalette.creamTop, VerbatimPalette.creamBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .inset:
            return LinearGradient(
                colors: [VerbatimPalette.insetTop, VerbatimPalette.insetBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .shell:
            return LinearGradient(
                colors: [VerbatimPalette.shellTop.opacity(0.82), VerbatimPalette.shellBottom.opacity(0.60)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .rail:
            return LinearGradient(
                colors: [VerbatimPalette.railTop, VerbatimPalette.railBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var highlightOpacity: Double {
        switch tone {
        case .shell:
            return 0.44
        case .cream:
            return 0.40
        case .frost, .rail:
            return 0.34
        case .inset:
            return 0.18
        }
    }

    private var strokeColor: Color {
        switch tone {
        case .cream:
            return Color.white.opacity(0.82)
        case .shell:
            return Color.white.opacity(0.44)
        case .inset:
            return Color.white.opacity(0.24)
        case .frost, .rail:
            return Color.white.opacity(0.34)
        }
    }

    private var strokeWidth: CGFloat {
        switch tone {
        case .shell:
            return 1.2
        case .frost, .cream, .rail:
            return 1
        case .inset:
            return 0.8
        }
    }

    private var shadowColor: Color {
        switch tone {
        case .shell:
            return Color.black.opacity(0.12)
        case .cream:
            return Color.black.opacity(0.08)
        case .frost, .rail:
            return Color.black.opacity(0.07)
        case .inset:
            return Color.clear
        }
    }

    private var shadowRadius: CGFloat {
        switch tone {
        case .shell:
            return 18
        case .cream:
            return 12
        case .frost, .rail:
            return 8
        case .inset:
            return 0
        }
    }

    private var shadowYOffset: CGFloat {
        switch tone {
        case .shell:
            return 8
        case .cream:
            return 5
        case .frost, .rail:
            return 3
        case .inset:
            return 0
        }
    }
}

struct VerbatimRailButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    let isActive: Bool
    let accent: AppSectionAccent

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        if #available(macOS 26.0, iOS 26.0, *) {
            configuration.label
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    shape.fill(
                        isActive
                            ? accent.tint.opacity(configuration.isPressed ? 0.16 : 0.12)
                            : (colorScheme == .dark
                                ? Color.black.opacity(configuration.isPressed ? 0.24 : 0.18)
                                : Color.white.opacity(configuration.isPressed ? 0.10 : 0.04))
                    )
                )
                .overlay(
                    shape.strokeBorder(
                        isActive
                            ? accent.tint.opacity(0.42)
                            : (colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.22)),
                        lineWidth: 1
                    )
                )
                .glassEffect(railGlass(isPressed: configuration.isPressed), in: .rect(cornerRadius: 22))
                .shadow(
                    color: isActive ? accent.glow.opacity(0.92) : Color.black.opacity(colorScheme == .dark ? 0.18 : 0.06),
                    radius: isActive ? 20 : 10,
                    x: 0,
                    y: isActive ? 10 : 4
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
        } else {
            configuration.label
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    shape
                        .fill(isActive ? accent.glow : Color.white.opacity(configuration.isPressed ? 0.12 : 0.06))
                        .overlay(
                            shape.stroke(
                                isActive ? accent.tint.opacity(0.65) : Color.white.opacity(0.20),
                                lineWidth: 1
                            )
                        )
                        .shadow(
                            color: isActive ? accent.glow : Color.clear,
                            radius: isActive ? 18 : 0,
                            x: 0,
                            y: 8
                        )
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
        }
    }

    @available(macOS 26.0, iOS 26.0, *)
    private func railGlass(isPressed: Bool) -> Glass {
        let tint = isActive ? accent.tint : (colorScheme == .dark ? Color(red: 0.30, green: 0.33, blue: 0.40) : Color.white)
        let opacity = isActive
            ? (isPressed ? 0.28 : 0.22)
            : (colorScheme == .dark ? (isPressed ? 0.18 : 0.14) : (isPressed ? 0.10 : 0.06))
        return .regular.tint(tint.opacity(opacity)).interactive()
    }
}

struct VerbatimGlassGroup<Content: View>: View {
    let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat = 24, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

extension View {
    func applyWindowChrome() -> some View {
        modifier(PlatformWindowChromeModifier())
    }

    func applyGlassButtonStyle(prominent: Bool = false) -> some View {
        modifier(PlatformGlassButtonModifier(prominent: prominent))
    }

    func applyLiquidCardStyle(
        cornerRadius: CGFloat,
        tone: VerbatimPanelTone = .frost,
        padding: CGFloat = 18
    ) -> some View {
        modifier(PlatformLiquidCardModifier(cornerRadius: cornerRadius, tone: tone, padding: padding))
    }

    func applyInsetWellStyle(cornerRadius: CGFloat, padding: CGFloat = 14) -> some View {
        modifier(PlatformInsetWellModifier(cornerRadius: cornerRadius, padding: padding))
    }

    func applyShellFrameStyle(cornerRadius: CGFloat, padding: CGFloat = 18) -> some View {
        modifier(PlatformShellModifier(cornerRadius: cornerRadius, padding: padding))
    }

    func applyStatusBadgeEffect() -> some View {
        modifier(PlatformBadgeModifier())
    }
}
