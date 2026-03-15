import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct AppRootView: View {
    private enum Layout {
        static let shellSpacing: CGFloat = 14
        static let shellPadding: CGFloat = 14
        static let pagePadding: CGFloat = 18
        static let panePadding: CGFloat = 18
        static let sectionSpacing: CGFloat = 18
        static let cardPadding: CGFloat = 16
        static let cardRadius: CGFloat = 24
        static let sidebarMinWidth: CGFloat = 232
        static let sidebarIdealWidth: CGFloat = 244
        static let sidebarMaxWidth: CGFloat = 260
        static let contentMinWidth: CGFloat = 620
        static let shellMinWidth: CGFloat = 900
        static let rowTimeWidth: CGFloat = 80
        static let rowMinHeight: CGFloat = 48
        static let overlayMinWidth: CGFloat = 860
        static let overlayIdealWidth: CGFloat = 900
        static let overlayMinHeight: CGFloat = 580
    }

    @EnvironmentObject private var model: AppModel
    @State private var dictionaryPhrase = ""
    @State private var dictionaryHint = ""

    var body: some View {
        Group {
            if model.settings.onboardingCompleted {
                mainView
            } else {
                onboardingView
            }
        }
        .overlay(alignment: .top) {
            if let status = model.inlineStatusMessage {
                InlineStatusBanner(status: status) {
                    model.inlineStatusMessage = nil
                }
                    .padding(.top, 18)
            }
        }
    }

    private var onboardingView: some View {
        ZStack {
            shellBackground

            ScrollView {
                VerbatimGlassGroup(spacing: Layout.sectionSpacing) {
                    VStack(spacing: 14) {
                        VerbatimBrandMark(size: 88)
                            .padding(18)
                            .applyInsetWellStyle(cornerRadius: 24, padding: 14)

                        Text("Welcome to Verbatim")
                            .font(.system(size: 42, weight: .semibold, design: .rounded))
                            .foregroundStyle(VerbatimPalette.ink)

                        Text("Keep the same Verbatim experience, now fully local. Grant permissions, choose a provider, pick a language, and set your dictation hotkey.")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(VerbatimPalette.mutedInk)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 620)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)

                    onboardingCard(
                        title: "1. Microphone",
                        subtitle: model.permissionsManager.microphoneAuthorized ? "Ready to record." : "Required for dictation.",
                        actionTitle: model.permissionsManager.microphoneAuthorized ? "Granted" : "Grant Microphone",
                        content: { EmptyView() },
                        action: {
                            Task { await model.requestMicrophone() }
                        }
                    )

                    onboardingCard(
                        title: "2. Accessibility",
                        subtitle: model.permissionsManager.accessibilityAuthorized ? "Auto-paste is ready." : "Optional, but required for auto-paste.",
                        actionTitle: model.permissionsManager.accessibilityAuthorized ? "Granted" : "Grant Accessibility",
                        content: { EmptyView() },
                        action: {
                            model.promptAccessibility()
                        }
                    )

                    onboardingCard(
                        title: "3. Provider",
                        subtitle: "Choose the local transcription engine Verbatim should use.",
                        actionTitle: nil
                    ) {
                        ProviderSelectionButtonsView()

                        if let message = model.effectiveProviderMessage {
                            Text(message)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AppSectionAccent.amber.tint)
                        }
                    }

                    onboardingCard(
                        title: "4. Language",
                        subtitle: "Apple Speech needs an explicit language. Whisper and Parakeet can use auto-detect where supported.",
                        actionTitle: nil
                    ) {
                        Picker("", selection: Binding(
                            get: { model.settings.preferredLanguage },
                            set: { model.settings.preferredLanguage = $0 }
                        )) {
                            ForEach(model.currentLanguageOptions) { language in
                                Text(language.title).tag(language)
                            }
                        }
                        .labelsHidden()
                    }

                    onboardingCard(
                        title: "5. Hotkey",
                        subtitle: "Tap-to-toggle dictation is the default in this build.",
                        actionTitle: nil
                    ) {
                        HStack(spacing: 10) {
                            HotkeyRecorderField(shortcut: Binding(
                                get: { model.settings.hotkeyBinding },
                                set: { model.updateHotkeyBinding($0) }
                            ))
                            .frame(width: 220, height: 36)

                            Button(model.isCapturingHotkey ? "Capturing…" : "Capture") {
                                model.beginHotkeyCapture()
                            }
                            .applyGlassButtonStyle(prominent: true)
                            .disabled(model.isCapturingHotkey)
                        }
                    }

                    HStack(spacing: 10) {
                        Button("Open System Settings") {
                            model.permissionsManager.openMicrophoneSettings()
                        }
                        .applyGlassButtonStyle()

                        Button("Continue") {
                            model.completeOnboarding()
                        }
                        .applyGlassButtonStyle(prominent: true)
                    }
                    .padding(.bottom, 18)
                }
                .padding(22)
            }
        }
    }

    private var mainView: some View {
        ZStack {
            shellBackground

            shellContainer
                .padding(Layout.shellPadding)
                .frame(minWidth: Layout.shellMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if model.showSettingsPanel || model.showSupportPanel {
                overlayBackdrop
            }

            if model.showSettingsPanel {
                settingsOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if model.showSupportPanel {
                supportOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: model.showSettingsPanel)
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: model.showSupportPanel)
    }

    private var shellBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.97, green: 0.98, blue: 0.995),
                Color(red: 0.91, green: 0.94, blue: 0.98),
                Color(red: 0.84, green: 0.88, blue: 0.94)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var shellContainer: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: Layout.shellSpacing) {
                shellContent
            }
        } else {
            shellContent
        }
    }

    private var shellContent: some View {
        HStack(spacing: Layout.shellSpacing) {
            sidebar
            contentPane
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            brandHeader
            searchField
            navigationRail
            Spacer(minLength: 24)
            dictationButton
            footerUtilities
        }
        .frame(
            minWidth: Layout.sidebarMinWidth,
            idealWidth: Layout.sidebarIdealWidth,
            maxWidth: Layout.sidebarMaxWidth,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .applyLiquidCardStyle(cornerRadius: 30, tone: .rail, padding: Layout.panePadding)
    }

    private var brandHeader: some View {
        HStack(spacing: 12) {
            VerbatimBrandMark(size: 34)
                .padding(8)
                .applyInsetWellStyle(cornerRadius: 14, padding: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text("Verbatim")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("Local Dictation")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)
            }

            Spacer()
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(VerbatimPalette.mutedInk)

            TextField("Search history", text: $model.homeSearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .rounded))

            Text("⌘K")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .applyInsetWellStyle(cornerRadius: 10, padding: 0)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .applyInsetWellStyle(cornerRadius: 18, padding: 0)
    }

    private var navigationRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    model.selectAppTab(tab)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 15, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Spacer()
                    }
                    .foregroundStyle(model.selectedAppTab == tab ? AppSectionAccent.cobalt.tint : VerbatimPalette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .applySelectionPillStyle(selected: model.selectedAppTab == tab, accent: .cobalt, cornerRadius: 18)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dictationButton: some View {
        Button {
            Task { await model.toggleRecording() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: dictationButtonImageName)
                    .font(.system(size: 14, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(dictationButtonTitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text(dictationButtonSubtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .applyGlassButtonStyle(prominent: model.overlayStatus != .recording)
    }

    private var dictationButtonTitle: String {
        switch model.overlayStatus {
        case .recording:
            return "Stop Dictation"
        case .processing:
            return "Processing…"
        case .idle, .success, .error:
            return "Start Dictation"
        }
    }

    private var dictationButtonSubtitle: String {
        switch model.overlayStatus {
        case .recording:
            return "Tap to stop and transcribe."
        case .processing:
            return "Verbatim is transcribing locally."
        case .success:
            return "Last result inserted."
        case .error:
            return "Review the latest error message."
        case .idle:
            return "Uses your global shortcut too."
        }
    }

    private var dictationButtonImageName: String {
        switch model.overlayStatus {
        case .recording:
            return "stop.circle.fill"
        case .processing:
            return "sparkle.magnifyingglass"
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        case .idle:
            return "mic.fill"
        }
    }

    private var footerUtilities: some View {
        VStack(alignment: .leading, spacing: 8) {
            footerButton(
                title: "Settings",
                systemImage: "gearshape",
                isActive: model.showSettingsPanel
            ) {
                model.openSettings()
            }

            footerButton(
                title: "Support",
                systemImage: "questionmark.circle",
                isActive: model.showSupportPanel
            ) {
                model.toggleSupport()
            }
        }
        .padding(.top, 4)
    }

    private func footerButton(
        title: String,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .applySelectionPillStyle(selected: isActive, accent: .violet, cornerRadius: 18)
        }
        .buttonStyle(.plain)
    }

    private var contentPane: some View {
        Group {
            switch model.selectedAppTab {
            case .home:
                homePage
            case .style:
                StylePageView(model: model)
            case .dictionary:
                dictionaryPage
            }
        }
        .frame(minWidth: Layout.contentMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .applyLiquidCardStyle(cornerRadius: 32, tone: .shell, padding: Layout.panePadding)
    }

    private var homePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Home")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text(homeSubtitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                }

                Spacer()

                if model.historyItems.isEmpty == false {
                    Button("Clear All") {
                        model.clearHistory()
                    }
                    .applyGlassButtonStyle()
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if model.filteredHistorySections.isEmpty {
                        emptyHomeState
                    } else {
                        ForEach(model.filteredHistorySections) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(section.title.uppercased())
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(VerbatimPalette.mutedInk)

                                LazyVStack(alignment: .leading, spacing: 10) {
                                    ForEach(section.items) { item in
                                        historyRow(item)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var homeSubtitle: String {
        if model.homeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return model.historyItems.isEmpty ? "Your local dictation history will appear here." : "Browse and re-use your recent local transcriptions."
        }
        return "Filtering local history for “\(model.homeSearchText)”."
    }

    private var emptyHomeState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.historyItems.isEmpty ? "No local transcriptions yet." : "No matching transcriptions.")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(model.historyItems.isEmpty ? "Start dictating from the sidebar or with your hotkey to build your local history." : "Try a broader search or clear the current search to see all history.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .applyLiquidCardStyle(cornerRadius: Layout.cardRadius, tone: .frost, padding: Layout.cardPadding)
    }

    private func historyRow(_ item: HistoryItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(item.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)
                .frame(width: Layout.rowTimeWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                Text(historyRowText(for: item))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(VerbatimPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                HStack(spacing: 10) {
                    Text(historyProviderTitle(for: item.provider))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppSectionAccent.cobalt.tint)
                        .applyStatusBadgeEffect()

                    if let error = item.error, error.isEmpty == false {
                        Text(error)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.red)
                            .lineLimit(2)
                    }

                    Spacer()

                    Button("Copy") {
                        model.copyHistoryText(item)
                    }
                    .applyGlassButtonStyle()

                    Button("Delete") {
                        model.deleteHistoryItem(item.id)
                    }
                    .applyGlassButtonStyle()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: Layout.rowMinHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.32))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.42), lineWidth: 1)
        )
    }

    private func historyRowText(for item: HistoryItem) -> String {
        let candidate = item.finalPastedText.isEmpty ? item.originalText : item.finalPastedText
        if candidate.isEmpty == false {
            return candidate
        }
        return item.error ?? "No transcription text available."
    }

    private func historyProviderTitle(for rawValue: String) -> String {
        ProviderID(rawValue: rawValue)?.title ?? rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var dictionaryPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dictionary")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("Manage vocabulary hints for providers that support them.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                }

                SettingsPanelCard(title: "Add Vocabulary") {
                    Text("Whisper uses these hints as prompt context. Apple Speech may ignore them in v1, and Parakeet ignores them in v1.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)

                    TextField("Word or phrase", text: $dictionaryPhrase)
                        .textFieldStyle(.roundedBorder)

                    TextField("Optional spoken hint", text: $dictionaryHint)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Spacer()
                        Button("Add") {
                            model.addDictionaryEntry(phrase: dictionaryPhrase, hint: dictionaryHint)
                            dictionaryPhrase = ""
                            dictionaryHint = ""
                        }
                        .applyGlassButtonStyle(prominent: true)
                        .disabled(dictionaryPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                SettingsPanelCard(title: "Saved Entries") {
                    if model.dictionaryEntries.isEmpty {
                        Text("No dictionary entries yet.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(VerbatimPalette.mutedInk)
                    } else {
                        ForEach(model.dictionaryEntries) { entry in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.phrase)
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    if entry.hint.isEmpty == false {
                                        Text(entry.hint)
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(VerbatimPalette.mutedInk)
                                    }
                                }
                                Spacer()
                                Button("Remove") {
                                    model.removeDictionaryEntry(entry.id)
                                }
                                .applyGlassButtonStyle()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
    }

    private var overlayBackdrop: some View {
        Color.black.opacity(0.14)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                model.dismissPresentedPanels()
            }
    }

    private var settingsOverlay: some View {
        HStack(spacing: 0) {
            settingsRail
            Divider()
                .overlay(Color.white.opacity(0.35))
            settingsDetail
        }
        .frame(
            minWidth: Layout.overlayMinWidth,
            idealWidth: Layout.overlayIdealWidth,
            maxWidth: 980,
            minHeight: Layout.overlayMinHeight,
            maxHeight: 720
        )
        .applyLiquidCardStyle(cornerRadius: 30, tone: .shell, padding: 0)
        .shadow(color: Color.black.opacity(0.16), radius: 30, x: 0, y: 18)
    }

    private var settingsRail: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("SETTINGS")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)

            ForEach(["APP", "SPEECH & AI", "PRIVACY"], id: \.self) { groupTitle in
                VStack(alignment: .leading, spacing: 8) {
                    Text(groupTitle)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)

                    ForEach(settingsTabs(for: groupTitle)) { tab in
                        Button {
                            model.setSelectedSettingsTab(tab)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: tab.systemImage)
                                    .font(.system(size: 14, weight: .semibold))
                                Text(tab.title)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                Spacer()
                            }
                            .foregroundStyle(model.selectedSettingsTab == tab ? AppSectionAccent.cobalt.tint : VerbatimPalette.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .applySelectionPillStyle(selected: model.selectedSettingsTab == tab, accent: .cobalt, cornerRadius: 18)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()
        }
        .padding(18)
        .frame(minWidth: 250, idealWidth: 250, maxWidth: 250, maxHeight: .infinity, alignment: .topLeading)
    }

    private func settingsTabs(for groupTitle: String) -> [SettingsTab] {
        SettingsTab.allCases.filter { $0.railGroupTitle == groupTitle }
    }

    private var settingsDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.selectedSettingsTab.title)
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                        Text(settingsSubtitle(for: model.selectedSettingsTab))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(VerbatimPalette.mutedInk)
                    }

                    Spacer()

                    Button {
                        model.closeSettings()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(VerbatimPalette.mutedInk)
                            .padding(10)
                            .applySelectionPillStyle(selected: false, accent: .violet, cornerRadius: 14)
                    }
                    .buttonStyle(.plain)
                }

                settingsTabContent
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func settingsSubtitle(for tab: SettingsTab) -> String {
        switch tab {
        case .preferences:
            return "Appearance, insertion behavior, and local utilities."
        case .transcription:
            return "Choose your speech-to-text engine, language, and local model setup."
        case .hotkeys:
            return "Capture and manage your global dictation shortcut."
        case .privacyPermissions:
            return "Local-only permissions and privacy controls."
        }
    }

    @ViewBuilder
    private var settingsTabContent: some View {
        switch model.selectedSettingsTab {
        case .preferences:
            PreferencesSettingsPanelView()
        case .transcription:
            TranscriptionSettingsPanelView()
        case .hotkeys:
            HotkeysPanelView()
        case .privacyPermissions:
            PrivacySettingsPanelView()
        }
    }

    private var supportOverlay: some View {
        SupportOverlayView()
    }

    private func onboardingCard<Content: View>(
        title: String,
        subtitle: String,
        actionTitle: String?,
        @ViewBuilder content: () -> Content,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)
            content()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .applyGlassButtonStyle(prominent: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .applyLiquidCardStyle(cornerRadius: Layout.cardRadius, tone: .frost, padding: Layout.cardPadding)
    }
}

struct HotkeyRecorderField: NSViewRepresentable {
    @Binding var shortcut: HotkeyBinding

    func makeCoordinator() -> Coordinator {
        Coordinator(shortcut: $shortcut)
    }

    func makeNSView(context: Context) -> ShortcutCaptureField {
        let field = ShortcutCaptureField()
        field.onShortcut = { event in
            guard let shortcut = HotkeyBinding.from(event: event) else { return }
            context.coordinator.shortcut.wrappedValue = shortcut
            field.stringValue = shortcut.displayTitle
        }
        field.stringValue = shortcut.displayTitle
        return field
    }

    func updateNSView(_ nsView: ShortcutCaptureField, context: Context) {
        nsView.stringValue = shortcut.displayTitle
    }

    final class Coordinator {
        var shortcut: Binding<HotkeyBinding>

        init(shortcut: Binding<HotkeyBinding>) {
            self.shortcut = shortcut
        }
    }
}

final class ShortcutCaptureField: NSTextField {
    var onShortcut: ((NSEvent) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = false
        isSelectable = false
        isBordered = false
        backgroundColor = .clear
        font = .systemFont(ofSize: 13, weight: .semibold)
        alignment = .center
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        onShortcut?(event)
    }

    override func flagsChanged(with event: NSEvent) {
        onShortcut?(event)
    }
}
