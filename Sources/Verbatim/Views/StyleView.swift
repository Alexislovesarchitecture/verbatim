import SwiftUI

struct StyleView: View {
    @EnvironmentObject private var store: VerbatimStore
    @State private var selectedCategory: AppStyleCategory = .personal

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Style")
                .font(.largeTitle.weight(.bold))

            Picker("Category", selection: $selectedCategory) {
                ForEach(AppStyleCategory.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)

            Text("Apply tone by app context. Keep it deterministic first. Add AI rewrite later only if you want more aggressive cleanup.")
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 18) {
                ForEach(StyleTone.allCases) { tone in
                    StyleCard(
                        title: tone.rawValue,
                        subtitle: tone.subtitle,
                        sample: tone.sample,
                        isSelected: store.settings.tone(for: selectedCategory) == tone
                    ) {
                        store.settings.setTone(tone, for: selectedCategory)
                        store.persist()
                    }
                }
            }

            Spacer()
        }
        .padding(32)
    }
}

private struct StyleCard: View {
    let title: String
    let subtitle: String
    let sample: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(.system(size: 24, weight: .medium, design: .serif))
                Text(subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Divider()
                Text(sample)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
