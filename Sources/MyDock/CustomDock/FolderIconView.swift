import SwiftUI

struct DockFolderIconView: View {
    var item: DockItem
    var size: CGFloat

    var body: some View {
        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(color)
            Image(systemName: "folder.fill")
                .font(.system(size: size * 0.78, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .offset(y: size * 0.04)
            if let letter = item.folderIconLetter, !letter.isEmpty {
                Text(letter)
                    .font(.system(size: size * 0.34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .offset(y: size * 0.02)
            }
            if let number = item.folderIconNumber, !number.isEmpty {
                Text(number)
                    .font(.system(size: size * 0.18, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(color)
                    .padding(size * 0.06)
                    .background(.white, in: Circle())
                    .overlay(Circle().stroke(color.opacity(0.25), lineWidth: 0.5))
                    .offset(x: size * 0.30, y: size * 0.27)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(accessibilityLabel)
    }

    private var color: Color {
        switch item.folderIconColor ?? .blue {
        case .blue: .blue
        case .purple: .purple
        case .teal: .teal
        case .green: .green
        case .orange: .orange
        case .pink: .pink
        case .red: .red
        }
    }

    private var accessibilityLabel: String {
        var parts = [item.displayName, "folder"]
        if let letter = item.folderIconLetter, !letter.isEmpty { parts.append("letter \(letter)") }
        if let number = item.folderIconNumber, !number.isEmpty { parts.append("number \(number)") }
        return parts.joined(separator: ", ")
    }
}
