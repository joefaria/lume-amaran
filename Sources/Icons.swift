import AppKit
import SwiftUI

/// Original Phosphor SVGs remain vector-backed and use macOS template tinting.
@MainActor enum Phosphor {
    private static var cache: [String: NSImage] = [:]
    static func image(_ name: String) -> NSImage {
        if let image = cache[name] { return image }
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("Phosphor"),
              let image = NSImage(contentsOf: folder.appendingPathComponent(name + ".svg")) else {
            assertionFailure("Missing Phosphor icon: \(name)")
            return NSImage(size: NSSize(width: 18, height: 18))
        }
        image.isTemplate = true; image.size = NSSize(width: 18, height: 18)
        cache[name] = image; return image
    }
}

struct PhosphorIcon: View {
    let name: String
    var size: CGFloat = 16
    var body: some View {
        Image(nsImage: Phosphor.image(name)).renderingMode(.template).resizable()
            .aspectRatio(contentMode: .fit).frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A restrained glass surface, with a native material fallback on macOS 13–15.
struct InstrumentGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var radius: CGFloat = 18
    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }
}
