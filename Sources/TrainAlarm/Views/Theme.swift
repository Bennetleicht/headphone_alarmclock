import SwiftUI

/// Gestaltungs-Grundlagen. Die App ist bewusst nur fuer Dark Mode ausgelegt --
/// sie wird im dunklen Zug benutzt, nicht am Schreibtisch.
enum Theme {

    // MARK: - Farben

    static let background = Color(red: 0.027, green: 0.035, blue: 0.055)
    static let backgroundTop = Color(red: 0.047, green: 0.078, blue: 0.102)

    static let card = Color.white.opacity(0.055)
    static let cardBorder = Color.white.opacity(0.09)

    static let accent = Color(red: 0.310, green: 0.996, blue: 0.788)
    static let accentDim = Color(red: 0.310, green: 0.996, blue: 0.788).opacity(0.15)

    static let danger = Color(red: 1.0, green: 0.353, blue: 0.376)
    static let dangerDim = Color(red: 1.0, green: 0.353, blue: 0.376).opacity(0.16)

    static let warning = Color(red: 1.0, green: 0.733, blue: 0.290)
    static let warningDim = Color(red: 1.0, green: 0.733, blue: 0.290).opacity(0.16)

    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.38)

    // MARK: - Masse

    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 14

    static var screenGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, background],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Einheitlicher Karten-Container.
struct Card<Content: View>: View {
    var content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            )
    }
}

/// Kleine Ueberschrift innerhalb einer Karte.
struct CardTitle: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 7) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(text.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.1)
        }
        .foregroundStyle(Theme.tertiaryText)
    }
}
