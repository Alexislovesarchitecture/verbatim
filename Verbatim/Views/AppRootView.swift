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
        static let supportWidth: CGFloat = 560
    }

    @EnvironmentObject private var model: AppModel
    @State private var dictionaryPhrase = ""
    @State private var dictionaryHint = ""

    private let providerOrder: [ProviderID] = [.whisper, .parakeet, .appleSpeech]

    var body: some View {
        Group {
            if model.settings.onboardingCompleted {
                mainView
            } else {
                onboardingView
            }
        }
        .alert("Verbatim", isPresented: Binding(
            get: { model.transientMessage != nil },
            set: { if !$0 { model.transientMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.transientMessage = nil }
        } message: {
            Text(model.transientMessage ?? "")
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
                        providerSelectionButtons

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

                settingsCard("Add Vocabulary") {
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

                settingsCard("Saved Entries") {
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
                guard model.transientMessage == nil else { return }
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
            preferencesPanel
        case .transcription:
            transcriptionPanel
        case .hotkeys:
            hotkeysPanel
        case .privacyPermissions:
            privacyPanel
        }
    }

    private var preferencesPanel: some View {
        VerbatimGlassGroup(spacing: Layout.sectionSpacing) {
            settingsCard("Behavior") {
                Toggle("Show floating overlay", isOn: Binding(
                    get: { model.settings.showOverlay },
                    set: { model.settings.showOverlay = $0 }
                ))

                Picker("After transcription", selection: Binding(
                    get: { model.settings.pasteMode },
                    set: { model.settings.pasteMode = $0 }
                )) {
                    ForEach(PasteMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .disabled(model.featureCapability(for: .autoPaste).isSupported == false)

                if model.featureCapability(for: .autoPaste).isSupported == false {
                    Text(model.featureCapability(for: .autoPaste).detail)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppSectionAccent.amber.tint)
                }

                Toggle("Show menu bar item", isOn: Binding(
                    get: { model.settings.menuBarEnabled },
                    set: { model.settings.menuBarEnabled = $0 }
                ))
            }

            settingsCard("Utilities") {
                Text("Local storage")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(model.paths.rootURL.path)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(VerbatimPalette.mutedInk)

                HStack(spacing: 10) {
                    Button("Reveal Application Support") {
                        model.revealAppSupport()
                    }
                    .applyGlassButtonStyle()

                    Button("Replay Onboarding") {
                        model.resetOnboarding()
                    }
                    .applyGlassButtonStyle()
                }

                Button("Reset Local Data") {
                    model.resetAppData()
                }
                .applyGlassButtonStyle(prominent: true)
            }
        }
    }

    private var transcriptionPanel: some View {
        VerbatimGlassGroup(spacing: Layout.sectionSpacing) {
            settingsCard("Speech to Text") {
                providerSelectionButtons

                if let message = model.effectiveProviderMessage {
                    Text(message)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppSectionAccent.amber.tint)
                }

                providerSettingsContent
            }

            settingsCard("Preferred Language") {
                Picker("Language", selection: Binding(
                    get: { model.settings.preferredLanguage },
                    set: { model.settings.preferredLanguage = $0 }
                )) {
                    ForEach(model.currentLanguageOptions) { language in
                        Text(language.title).tag(language)
                    }
                }
            }

            settingsCard("Dictionary") {
                Text("Manage vocabulary hints in Dictionary. Whisper uses these as prompt context when possible. Apple Speech may ignore them in v1, and Parakeet ignores them in v1.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)

                Button("Open Dictionary") {
                    model.selectAppTab(.dictionary)
                    model.closeSettings()
                }
                .applyGlassButtonStyle()
            }
        }
    }

    @ViewBuilder
    private var providerSettingsContent: some View {
        switch model.settings.selectedProvider {
        case .whisper:
            providerStatusHeader(for: .whisper)
            if model.providerCapability(for: .whisper).isSupported {
                ForEach(model.whisperModelStatuses) { status in
                    modelRow(
                        status,
                        selected: model.settings.selectedWhisperModelID == status.id,
                        onSelect: { model.settings.selectedWhisperModelID = status.id },
                        onDownload: { Task { await model.downloadWhisperModel(status.id) } },
                        onDelete: { Task { await model.deleteWhisperModel(status.id) } }
                    )
                }
            }
        case .parakeet:
            providerStatusHeader(for: .parakeet)
            if model.providerCapability(for: .parakeet).isSupported {
                ForEach(model.parakeetModelStatuses) { status in
                    modelRow(
                        status,
                        selected: model.settings.selectedParakeetModelID == status.id,
                        onSelect: { model.settings.selectedParakeetModelID = status.id },
                        onDownload: { Task { await model.downloadParakeetModel(status.id) } },
                        onDelete: { Task { await model.deleteParakeetModel(status.id) } }
                    )
                }
            }
        case .appleSpeech:
            providerStatusHeader(for: .appleSpeech)
            if model.providerCapability(for: .appleSpeech).isSupported,
               model.providerStatus(for: .appleSpeech).actionTitle == "Install" {
                Button("Install Apple Speech Assets") {
                    Task { await model.installAppleAssets() }
                }
                .applyGlassButtonStyle(prominent: true)
            }
            if model.providerCapability(for: .appleSpeech).isSupported {
                Text("\(model.appleInstalledLanguages.count) Apple speech languages are currently installed on this Mac.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)
            }
        }
    }

    private func providerStatusHeader(for provider: ProviderID) -> some View {
        let capability = model.providerCapability(for: provider)
        let statusMessage = capability.kind == .unsupported ? capability.detail : model.providerStatus(for: provider).message

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(provider.title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))

                Text(capability.kind.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(capability.isAvailable ? AppSectionAccent.mint.tint : AppSectionAccent.amber.tint)
                    .applyStatusBadgeEffect()
            }

            Text(statusMessage)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)
        }
    }

    private func providerSystemImage(_ provider: ProviderID) -> String {
        switch provider {
        case .whisper:
            return "waveform"
        case .parakeet:
            return "antenna.radiowaves.left.and.right"
        case .appleSpeech:
            return "apple.logo"
        }
    }

    private var hotkeysPanel: some View {
        settingsCard("Global Hotkey") {
            Toggle(isOn: Binding(
                get: { model.settings.hotkeyEnabled },
                set: { model.updateHotkeyEnabled($0) }
            )) {
                Text("Enable global activation")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .toggleStyle(.switch)
            .disabled(model.featureCapability(for: .hotkeyCapture).isSupported == false)

            Picker("Trigger mode", selection: Binding(
                get: { model.settings.hotkeyTriggerMode },
                set: { model.updateHotkeyTriggerMode($0) }
            )) {
                ForEach(HotkeyTriggerMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.settings.hotkeyEnabled == false || model.featureCapability(for: .hotkeyCapture).isSupported == false)

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
                .disabled(model.isCapturingHotkey || model.settings.hotkeyEnabled == false)

                Button("Use Fn / Globe") {
                    model.resetHotkeyBindingToDefault()
                }
                .applyGlassButtonStyle()
                .disabled(model.settings.hotkeyEnabled == false)
            }
            .disabled(model.featureCapability(for: .hotkeyCapture).isSupported == false)

            if model.settings.hotkeyBinding.usesFn {
                Picker("Fn / Globe fallback", selection: Binding(
                    get: { model.settings.functionKeyFallbackMode },
                    set: { model.updateFunctionKeyFallbackMode($0) }
                )) {
                    ForEach(FunctionKeyFallbackMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.settings.hotkeyEnabled == false || model.featureCapability(for: .hotkeyCapture).isSupported == false)
            }

            Text("Requested binding: \(model.settings.hotkeyBinding.displayTitle)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)

            Text("Effective binding: \(model.hotkeyEffectiveBindingTitle)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)

            Text("Backend: \(model.hotkeyBackendTitle)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)

            if let fallbackReason = model.hotkeyFallbackReason, fallbackReason.isEmpty == false {
                Text(fallbackReason)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppSectionAccent.amber.tint)
            }

            Text(model.hotkeyStatusMessage)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)

            if model.featureCapability(for: .hotkeyCapture).isSupported == false {
                Text(model.featureCapability(for: .hotkeyCapture).detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppSectionAccent.amber.tint)
            }
        }
    }

    private var providerSelectionButtons: some View {
        HStack(spacing: 8) {
            ForEach(providerOrder) { provider in
                let capability = model.providerCapability(for: provider)

                Button {
                    model.selectProvider(provider)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: providerSystemImage(provider))
                            .font(.system(size: 13, weight: .semibold))
                        Text(provider.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(model.settings.selectedProvider == provider ? AppSectionAccent.cobalt.tint : VerbatimPalette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .opacity(capability.isSupported ? 1 : 0.62)
                    .applySelectionPillStyle(selected: model.settings.selectedProvider == provider, accent: .cobalt, cornerRadius: 16)
                }
                .buttonStyle(.plain)
                .disabled(model.canSelectProvider(provider) == false)
            }
        }
    }

    private var privacyPanel: some View {
        VerbatimGlassGroup(spacing: Layout.sectionSpacing) {
            settingsCard("Permissions") {
                permissionRow(
                    title: "Microphone",
                    subtitle: "Required for local recording and transcription.",
                    granted: model.permissionsManager.microphoneAuthorized,
                    actionTitle: model.permissionsManager.microphoneAuthorized ? "Granted" : "Grant"
                ) {
                    Task { await model.requestMicrophone() }
                }

                permissionRow(
                    title: "Accessibility",
                    subtitle: "Needed for global hotkeys and automatic paste after transcription.",
                    granted: model.permissionsManager.accessibilityAuthorized,
                    actionTitle: model.permissionsManager.accessibilityAuthorized ? "Granted" : "Grant"
                ) {
                    model.promptAccessibility()
                }
            }

            settingsCard("Privacy") {
                Text("Verbatim stores transcripts, dictionary entries, and local models on this Mac only. No cloud sync, billing, or account features are present in this build.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)

                HStack(spacing: 10) {
                    Button("Open Microphone Settings") {
                        model.permissionsManager.openMicrophoneSettings()
                    }
                    .applyGlassButtonStyle()

                    Button("Open Accessibility Settings") {
                        model.permissionsManager.openAccessibilitySettings()
                    }
                    .applyGlassButtonStyle()
                }
            }

            settingsCard("Diagnostics") {
                Text("Preflighted local runtime, selected model, and provider readiness state.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)

                HStack(spacing: 10) {
                    Button("Re-check") {
                        Task { await model.recheckDiagnostics() }
                    }
                    .applyGlassButtonStyle(prominent: true)

                    Button("Reveal Logs") {
                        model.revealLogs()
                    }
                    .applyGlassButtonStyle()

                    Button("Copy Diagnostics") {
                        model.copyDiagnostics()
                    }
                    .applyGlassButtonStyle()
                }

                ForEach(providerOrder) { provider in
                    if let diagnostic = model.providerDiagnostic(for: provider) {
                        diagnosticRow(diagnostic)
                    }
                }
            }
        }
    }

    private var supportOverlay: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Support")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("Quick help for hotkeys, permissions, and local runtime setup.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                }

                Spacer()

                Button {
                    model.closeSupport()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                        .padding(10)
                        .applySelectionPillStyle(selected: false, accent: .violet, cornerRadius: 14)
                }
                .buttonStyle(.plain)
            }

            supportCard(
                title: "Hotkey",
                subtitle: "Current global shortcut",
                detail: [
                    "Requested: \(model.settings.hotkeyBinding.displayTitle)",
                    "Effective: \(model.hotkeyEffectiveBindingTitle)",
                    "Backend: \(model.hotkeyBackendTitle)",
                    "Trigger mode: \(model.settings.hotkeyTriggerMode.title)",
                    model.hotkeyFallbackReason
                ]
                .compactMap { $0 }
                .joined(separator: "\n")
            )

            supportCard(
                title: "Permissions",
                subtitle: "Microphone is required. Accessibility is optional unless you want auto-paste.",
                detail: "Microphone: \(model.permissionsManager.microphoneAuthorized ? "Granted" : "Missing")\nAccessibility: \(model.permissionsManager.accessibilityAuthorized ? "Granted" : "Missing")"
            )

            supportCard(
                title: "Storage",
                subtitle: "Local history, dictionary, models, and logs live here.",
                detail: model.paths.rootURL.path
            )

            supportCard(
                title: "Local Runtimes",
                subtitle: "Whisper uses whisper-server, Parakeet uses sherpa-onnx, and Apple Speech uses macOS system assets.",
                detail: "Everything continues to work offline after models and Apple language assets are installed.\n\(model.providerPrewarmStatusMessage)"
            )

            supportCard(
                title: "Diagnostics",
                subtitle: "Current provider/runtime summary",
                detail: model.supportDiagnosticsSummary.isEmpty ? "Checking local runtime state…" : model.supportDiagnosticsSummary
            )

            HStack(spacing: 10) {
                Button("Re-check") {
                    Task { await model.recheckDiagnostics() }
                }
                .applyGlassButtonStyle(prominent: true)

                Button("Reveal Logs") {
                    model.revealLogs()
                }
                .applyGlassButtonStyle()

                Button("Copy Diagnostics") {
                    model.copyDiagnostics()
                }
                .applyGlassButtonStyle()

                Button("Reveal Application Support") {
                    model.revealAppSupport()
                }
                .applyGlassButtonStyle()

                Button("Microphone Settings") {
                    model.permissionsManager.openMicrophoneSettings()
                }
                .applyGlassButtonStyle()

                Button("Accessibility Settings") {
                    model.permissionsManager.openAccessibilitySettings()
                }
                .applyGlassButtonStyle()
            }

            HStack {
                Spacer()
                Button("Close") {
                    model.closeSupport()
                }
                .applyGlassButtonStyle(prominent: true)
            }
        }
        .padding(24)
        .frame(width: Layout.supportWidth)
        .applyLiquidCardStyle(cornerRadius: 30, tone: .shell, padding: 0)
        .shadow(color: Color.black.opacity(0.16), radius: 30, x: 0, y: 18)
    }

    private func supportCard(title: String, subtitle: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)
            Text(detail)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .applyLiquidCardStyle(cornerRadius: 22, tone: .frost, padding: Layout.cardPadding)
    }

    private func diagnosticRow(_ diagnostic: ProviderDiagnosticStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(diagnostic.provider.title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))

                        Text(diagnostic.readiness.kind == .ready ? "Ready" : "Attention")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(diagnostic.readiness.kind == .ready ? AppSectionAccent.mint.tint : AppSectionAccent.amber.tint)
                            .applyStatusBadgeEffect()
                    }

                    Text("Selected: \(diagnostic.selectionDescription)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)

                    Text("Availability: \(diagnostic.availability.isAvailable ? "Available" : "Unavailable")")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)

                    if let snapshot = diagnostic.runtimeSnapshot {
                        Text("Runtime: \(snapshot.binaryPresent ? "Binary present" : "Binary missing") • \(snapshot.state.rawValue.capitalized)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(VerbatimPalette.mutedInk)
                    } else {
                        Text("Runtime: System managed")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(VerbatimPalette.mutedInk)
                    }

                    if let source = diagnostic.selectionSource {
                        Text("Install source: \(source.title)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(VerbatimPalette.mutedInk)
                    }

                    if let lastCheck = diagnostic.lastCheck {
                        Text("Last checked: \(lastCheck.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(VerbatimPalette.mutedInk)
                    }

                    if let error = diagnostic.lastError, error.isEmpty == false {
                        Text(error)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.red)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(diagnostic.readiness.message)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(VerbatimPalette.mutedInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    if diagnostic.provider != .appleSpeech {
                        Button("Restart Runtime") {
                            Task { await model.restartRuntime(for: diagnostic.provider) }
                        }
                        .applyGlassButtonStyle(prominent: true)
                        .disabled(diagnostic.selectionInstalled == false || diagnostic.runtimeSnapshot?.binaryPresent != true)
                    } else if diagnostic.readiness.actionTitle == "Install" {
                        Button("Install") {
                            Task { await model.installAppleAssets() }
                        }
                        .applyGlassButtonStyle(prominent: true)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        )
    }

    private func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .applyLiquidCardStyle(cornerRadius: Layout.cardRadius, tone: .frost, padding: Layout.cardPadding)
    }

    private func permissionRow(
        title: String,
        subtitle: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)
            }

            Spacer()

            Button(actionTitle, action: action)
                .applyGlassButtonStyle(prominent: granted == false)
                .disabled(granted)
        }
    }

    private func modelRow(
        _ status: ModelStatus,
        selected: Bool,
        onSelect: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(status.descriptor.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    if status.descriptor.recommended {
                        Text("Recommended")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppSectionAccent.mint.tint)
                            .applyStatusBadgeEffect()
                    }
                }
                Text("\(status.descriptor.detail) • \(status.descriptor.sizeLabel)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)
            }

            Spacer()

            switch status.state {
            case .ready:
                Button(selected ? "Active" : "Select", action: onSelect)
                    .applyGlassButtonStyle(prominent: selected == false)
                Button("Delete", action: onDelete)
                    .applyGlassButtonStyle()
            case .downloading:
                Text("Downloading…")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)
            case .installing:
                Text("Installing…")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)
            case .failed(let message):
                Text(message)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.red)
            case .notInstalled:
                Button("Download", action: onDownload)
                    .applyGlassButtonStyle(prominent: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(selected ? AppSectionAccent.cobalt.glow : Color.white.opacity(0.28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(selected ? AppSectionAccent.cobalt.tint.opacity(0.28) : Color.white.opacity(0.28), lineWidth: 1)
        )
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
