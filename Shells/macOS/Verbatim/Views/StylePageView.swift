import SwiftUI

struct StylePageView: View {
    @ObservedObject var model: AppModel
    @State private var selectedCategory: StyleCategory = .personalMessages
    @Namespace private var styleNamespace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                categoryStrip
                heroCard
                enableToggle
                presetGrid
                latestDecisionCard
                latestContextCard
                rolloutNote
            }
            .padding(28)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Style")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            Text("These settings now feed the main dictation pipeline in this shell. Enable a category to apply light formatting based on the app that was active when recording started.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)
        }
    }

    @ViewBuilder
    private var categoryStrip: some View {
        if #available(macOS 15.0, *) {
            GlassEffectContainer(spacing: 12) {
                categoryButtons
            }
        } else {
            categoryButtons
        }
    }

    private var categoryButtons: some View {
        HStack(spacing: 12) {
            ForEach(StyleCategory.allCases) { category in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        selectedCategory = category
                    }
                } label: {
                    Text(category.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(selectedCategory == category ? AppSectionAccent.violet.tint : VerbatimPalette.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .applySelectionPillStyle(selected: selectedCategory == category, accent: .violet, cornerRadius: 18)
                        .modifier(OptionalInteractiveGlassModifier(id: "category-\(category.rawValue)", namespace: styleNamespace))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(selectedCategory.heroTitle)
                .font(.system(size: 28, weight: .medium, design: .serif))
                .foregroundStyle(.white)

            Text(selectedCategory.heroSubtitle)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))

            HStack(spacing: 10) {
                ForEach(selectedCategory.sampleApps, id: \.self) { appName in
                    Text(appName)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.18), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.29, blue: 0.41),
                    Color(red: 0.28, green: 0.14, blue: 0.07),
                    Color(red: 0.17, green: 0.25, blue: 0.17)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
    }

    private var enableToggle: some View {
        Toggle(isOn: Binding(
            get: { model.styleEnabled(for: selectedCategory) },
            set: { model.updateStyleEnabled($0, for: selectedCategory) }
        )) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Enable formatting for \(selectedCategory.title.lowercased())")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("When enabled, Verbatim applies only light punctuation and capitalization changes for this category.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)
            }
        }
        .toggleStyle(.switch)
        .applyLiquidCardStyle(cornerRadius: 22, tone: .frost, padding: 18)
    }

    private var presetGrid: some View {
        let presets = selectedCategory.supportedPresets

        return VStack(alignment: .leading, spacing: 12) {
            Text("Preset")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 18)], spacing: 18) {
                ForEach(presets) { preset in
                    presetCard(for: preset)
                }
            }
        }
        .opacity(model.styleEnabled(for: selectedCategory) ? 1 : 0.65)
    }

    private func presetCard(for preset: StylePreset) -> some View {
        let isSelected = model.stylePreset(for: selectedCategory) == preset

        return Button {
            model.updateStylePreset(preset, for: selectedCategory)
        } label: {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(preset.title)
                        .font(.system(size: 20, weight: .medium, design: .serif))
                    Text(preset.summary)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                }

                Divider()

                Text(preset.preview(for: selectedCategory))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
            .applyLiquidCardStyle(cornerRadius: 24, tone: .frost, padding: 0)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(isSelected ? AppSectionAccent.violet.tint : Color.white.opacity(0.14), lineWidth: isSelected ? 2 : 1)
            )
            .modifier(OptionalInteractiveGlassModifier(id: "preset-\(selectedCategory.rawValue)-\(preset.rawValue)", namespace: styleNamespace))
        }
        .buttonStyle(.plain)
        .disabled(model.styleEnabled(for: selectedCategory) == false)
    }

    private var latestContextCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Latest captured context")
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            if let context = model.latestActiveAppContext {
                VStack(alignment: .leading, spacing: 8) {
                    contextRow(label: "App", value: context.appName)
                    contextRow(label: "Category", value: context.styleCategory.title)
                    if let windowTitle = context.windowTitle, windowTitle.isEmpty == false {
                        contextRow(label: "Window", value: windowTitle)
                    }
                    if let focusedRole = context.focusedElementRole, focusedRole.isEmpty == false {
                        contextRow(label: "Focused role", value: focusedRole)
                    }
                    if let subrole = context.focusedElementSubrole, subrole.isEmpty == false {
                        contextRow(label: "Subrole", value: subrole)
                    }
                    if let title = context.focusedElementTitle, title.isEmpty == false {
                        contextRow(label: "Field title", value: title)
                    }
                    if let placeholder = context.focusedElementPlaceholder, placeholder.isEmpty == false {
                        contextRow(label: "Placeholder", value: placeholder)
                    }
                    if let description = context.focusedElementDescription, description.isEmpty == false {
                        contextRow(label: "Description", value: description)
                    }
                    if let snippet = context.focusedValueSnippet, snippet.isEmpty == false {
                        contextRow(label: "Value", value: snippet)
                    }
                    if let insertion = model.latestPasteDiagnostic {
                        Divider()
                            .overlay(Color.white.opacity(0.14))
                        contextRow(label: "Insertion mode", value: insertion.requestedMode.title)
                        contextRow(label: "Insertion outcome", value: insertion.outcome.title)
                        if let appName = insertion.targetAppName, appName.isEmpty == false {
                            contextRow(label: "Target app", value: appName)
                        }
                        if let windowTitle = insertion.targetWindowTitle, windowTitle.isEmpty == false {
                            contextRow(label: "Target window", value: windowTitle)
                        }
                        if let fieldRole = insertion.targetFieldRole, fieldRole.isEmpty == false {
                            contextRow(label: "Target field role", value: fieldRole)
                        }
                        if let fieldTitle = insertion.targetFieldTitle, fieldTitle.isEmpty == false {
                            contextRow(label: "Target field title", value: fieldTitle)
                        }
                        if let placeholder = insertion.targetFieldPlaceholder, placeholder.isEmpty == false {
                            contextRow(label: "Target placeholder", value: placeholder)
                        }
                        if let fallbackReason = insertion.fallbackReason {
                            contextRow(label: "Fallback reason", value: fallbackReason.title)
                        }
                    }
                }
            } else {
                Text("Start a dictation to capture the current app, the focused field, and the latest context snapshot used by the shell.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)
            }
        }
        .applyLiquidCardStyle(cornerRadius: 24, tone: .frost, padding: 20)
    }

    private var latestDecisionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Latest style event")
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            if let event = model.latestStyleEvent {
                VStack(alignment: .leading, spacing: 8) {
                    contextRow(label: "Category", value: event.category.title)
                    contextRow(label: "Preset", value: event.preset.title)
                    contextRow(label: "Source", value: event.source.title)
                    contextRow(label: "Confidence", value: String(format: "%.0f%%", event.confidence * 100))
                    contextRow(label: "Formatting", value: event.formattingEnabled ? "Enabled" : "Disabled")
                    if let reason = event.reason, reason.isEmpty == false {
                        contextRow(label: "Reason", value: reason)
                    }
                    if let preview = event.outputPreview, preview.isEmpty == false {
                        contextRow(label: "Preview", value: preview)
                    }
                }
            } else {
                Text("The next dictation event will show the chosen category, preset, and the signal that drove the decision.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)
            }
        }
        .applyLiquidCardStyle(cornerRadius: 24, tone: .frost, padding: 20)
    }

    private func contextRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.ink)
            Spacer(minLength: 0)
        }
    }

    private var rolloutNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Behavior")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text("This mainline shell now restores category-aware style settings through the shared core contract. The formatting pass stays conservative: it only applies light cleanup, punctuation, and capitalization changes based on the detected app context.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)
        }
        .applyLiquidCardStyle(cornerRadius: 22, tone: .frost, padding: 18)
    }
}

private struct OptionalInteractiveGlassModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
                .glassEffectID(id, in: namespace)
        } else {
            content
        }
    }
}
