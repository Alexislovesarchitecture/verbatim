import SwiftUI

struct StylePage: View {
    @ObservedObject var viewModel: StyleViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Style")
                .font(.system(size: 38, weight: .bold, design: .rounded))

            Picker("Category", selection: $viewModel.selectedCategory) {
                ForEach(StyleCategory.allCases) { category in
                    Text(category.title).tag(category)
                }
            }
            .pickerStyle(.segmented)

            sectionCard(title: "Tone") {
                let categoryProfile = viewModel.profile(for: viewModel.selectedCategory)
                HStack(spacing: 12) {
                    ForEach(viewModel.toneCards(), id: \.self) { tone in
                        Button {
                            viewModel.selectTone(tone, for: viewModel.selectedCategory)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(tone.title)
                                    .font(.title3.weight(.semibold))
                                Text(viewModel.previewText(for: viewModel.selectedCategory))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                if categoryProfile.tone == tone {
                                    Text("Selected")
                                        .font(.caption2.weight(.semibold))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                        }
                        .buttonStyle(.bordered)
                        .tint(categoryProfile.tone == tone ? .accentColor : .secondary.opacity(0.2))
                    }
                }
            }

            let category = viewModel.selectedCategory
            if let profile = viewModel.profiles[category] {
                sectionCard(title: "Formatting") {
                    Picker("Caps", selection: Binding(
                        get: { profile.capsMode },
                        set: { newValue in
                            viewModel.updateProfile(profile, caps: newValue, punctuation: profile.punctuationMode, exclamations: profile.exclamationMode, removeFillers: profile.removeFillers, interpretVoiceCommands: profile.interpretVoiceCommands)
                        }
                    )) {
                        Text("Sentence case").tag(CapsMode.sentenceCase)
                        Text("Lowercase").tag(CapsMode.lowercase)
                    }
                    .pickerStyle(.segmented)

                    Picker("Punctuation", selection: Binding(
                        get: { profile.punctuationMode },
                        set: { newValue in
                            viewModel.updateProfile(profile, caps: profile.capsMode, punctuation: newValue, exclamations: profile.exclamationMode, removeFillers: profile.removeFillers, interpretVoiceCommands: profile.interpretVoiceCommands)
                        }
                    )) {
                        Text("Normal").tag(PunctuationMode.normal)
                        Text("Light").tag(PunctuationMode.light)
                    }
                    .pickerStyle(.segmented)

                    Picker("Exclamations", selection: Binding(
                        get: { profile.exclamationMode },
                        set: { newValue in
                            viewModel.updateProfile(profile, caps: profile.capsMode, punctuation: profile.punctuationMode, exclamations: newValue, removeFillers: profile.removeFillers, interpretVoiceCommands: profile.interpretVoiceCommands)
                        }
                    )) {
                        Text("Normal").tag(ExclamationMode.normal)
                        Text("More").tag(ExclamationMode.more)
                        Text("None").tag(ExclamationMode.none)
                    }
                    .pickerStyle(.segmented)

                    Toggle("Remove fillers", isOn: Binding(
                        get: { profile.removeFillers },
                        set: { newValue in
                            viewModel.updateProfile(profile, caps: profile.capsMode, punctuation: profile.punctuationMode, exclamations: profile.exclamationMode, removeFillers: newValue, interpretVoiceCommands: profile.interpretVoiceCommands)
                        }
                    ))

                    Toggle("Interpret voice commands", isOn: Binding(
                        get: { profile.interpretVoiceCommands },
                        set: { newValue in
                            viewModel.updateProfile(profile, caps: profile.capsMode, punctuation: profile.punctuationMode, exclamations: profile.exclamationMode, removeFillers: profile.removeFillers, interpretVoiceCommands: newValue)
                        }
                    ))
                }
            }

            Spacer()
        }
        .padding(20)
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }
}
