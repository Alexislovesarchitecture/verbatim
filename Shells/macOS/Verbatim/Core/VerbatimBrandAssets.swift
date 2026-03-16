import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

enum VerbatimBrandAsset: String {
    case mark = "verbatim-mark"
    case menuGlyph = "verbatim-menu-glyph"
}

enum VerbatimBrandAssets {
    static func url(for asset: VerbatimBrandAsset) -> URL? {
        VerbatimBundle.current.url(forResource: asset.rawValue, withExtension: "png", subdirectory: "Brand")
            ?? VerbatimBundle.current.url(forResource: asset.rawValue, withExtension: "png", subdirectory: "Resources/Brand")
    }

#if canImport(AppKit)
    static func nsImage(for asset: VerbatimBrandAsset) -> NSImage? {
        guard let url = url(for: asset) else { return nil }
        return NSImage(contentsOf: url)
    }
#endif

    static func swiftUIImage(for asset: VerbatimBrandAsset) -> Image? {
#if canImport(AppKit)
        guard let image = nsImage(for: asset) else { return nil }
        return Image(nsImage: image)
#else
        return nil
#endif
    }
}

struct VerbatimBrandMark: View {
    var size: CGFloat = 32
    var fallbackSystemName: String = "mic.fill"

    var body: some View {
        Group {
            if let image = VerbatimBrandAssets.swiftUIImage(for: .mark) {
                image
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: fallbackSystemName)
                    .resizable()
                    .scaledToFit()
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
    }
}
