import SwiftUI

/// A customised folder: the folder glyph itself in the chosen colour, with no box behind it.
/// Increase Contrast outlines the glyph; nothing here is translucent, so Reduce Transparency
/// needs no change.
struct DockFolderIconView: View {
    var item: DockItem
    var size: CGFloat
    @DockAccessibilityStyle() private var accessibility

    var body: some View {
        ZStack(alignment: .center) {
            glyph("folder.fill").foregroundStyle(color.gradient)
            if accessibility.contrast == .increased {
                glyph("folder").foregroundStyle(Color.primary.opacity(0.85))
            }
            if let letter = item.folderIconLetter, !letter.isEmpty {
                Text(letter)
                    .font(.system(size: size * 0.36, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                    .offset(y: size * 0.06)
            }
            if let number = item.folderIconNumber, !number.isEmpty {
                Text(number)
                    .font(.system(size: size * 0.18, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(color)
                    .padding(size * 0.06)
                    .background(.white, in: Circle())
                    .offset(x: size * 0.30, y: size * 0.27)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .frame(width: size * 0.9, height: size * 0.9)
            .accessibilityHidden(true)
    }

    /// The profile palette, so a folder colour matches the same colour everywhere else in MyDock.
    private var color: Color { (item.folderIconColor ?? .blue).displayColor }

    private var accessibilityLabel: String {
        var parts = [item.displayName, "folder"]
        if let letter = item.folderIconLetter, !letter.isEmpty { parts.append("letter \(letter)") }
        if let number = item.folderIconNumber, !number.isEmpty { parts.append("number \(number)") }
        return parts.joined(separator: ", ")
    }
}
