import SwiftUI

struct StyleView: View {
    @EnvironmentObject private var controller: VerbatimController

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Style")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Picker("Category", selection: $controller.activeStyleCategory) {
                ForEach(StyleCategory.allCases) { category in
                    Text(category.title).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: controller.activeStyleCategory) { _, newValue in
                controller.selectedStyleProfileID = controller.styleProfiles.first(where: { $0.category == newValue })?.id
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Set the tone by app context")
                        .font(.headline)
                    Text("Keep this profile-based, not generative, until insertion and undo are rock solid. Caps, punctuation density, filler removal, and excitement level are enough for the first version.")
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                ForEach(controller.activeCategoryStyles) { profile in
                    StyleCard(profile: profile, isSelected: controller.selectedStyleProfileID == profile.id)
                        .onTapGesture {
                            controller.chooseStyle(profile)
                        }
                }
            }
            Spacer()
        }
    }
}

private struct StyleCard: View {
    let profile: StyleProfile
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(profile.name)
                .font(.largeTitle)
                .fontWeight(.medium)
            Text(summary)
                .font(.headline)
                .foregroundStyle(.secondary)
            Divider()
            Text(exampleText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            HStack {
                Spacer()
                Circle()
                    .fill(isSelected ? Color.purple : Color.purple.opacity(0.25))
                    .frame(width: 42, height: 42)
                    .overlay(Text("J").foregroundStyle(.white).fontWeight(.semibold))
            }
        }
        .padding(20)
        .frame(width: 250, height: 330)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color.purple : Color.secondary.opacity(0.16), lineWidth: isSelected ? 2 : 1)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        )
    }

    private var summary: String {
        let caps = profile.sentenceCase ? "Caps" : "No caps"
        let punctuation = profile.punctuationLevel >= 0.8 ? "Normal punctuation" : "Less punctuation"
        return "\(caps) + \(punctuation)"
    }

    private var exampleText: String {
        switch profile.name {
        case "Formal":
            return "Hey, are you free for lunch tomorrow? Let's do 12 if that works for you."
        case "Very casual":
            return "hey are you free for lunch tomorrow let's do 12 if that works for you"
        case "Excited":
            return "I am excited for tomorrow's workout, especially after a full night of rest!"
        default:
            return "Hey are you free for lunch tomorrow? Let's do 12 if that works for you"
        }
    }
}
