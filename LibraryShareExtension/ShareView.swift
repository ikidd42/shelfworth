import SwiftUI

/// Confirmation UI shown inside the Share Extension after processing a listing.
/// Styled with the app's "Athenaeum" language — kept self-contained so the
/// extension target stays tiny (no shared code with the app).
struct ShareResultView: View {
    let success: Bool
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            SharePalette.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Status medallion
                ZStack {
                    Circle()
                        .fill(success ? SharePalette.green.opacity(0.12) : SharePalette.brass.opacity(0.14))
                    Image(systemName: success ? "books.vertical.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(success ? SharePalette.green : SharePalette.brass)
                }
                .frame(width: 88, height: 88)

                Text(success ? "Added to Watchlist" : "Couldn't Add Book")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(SharePalette.ink)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)

                Text(message)
                    .font(success ? .callout.italic() : .callout)
                    .foregroundStyle(SharePalette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 36)
                    .padding(.top, 10)

                // Fleuron divider
                HStack(spacing: 10) {
                    fleuronRule
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(SharePalette.brass)
                    fleuronRule
                }
                .padding(.top, 22)

                if success {
                    Text("Open Library to see your Watchlist and track prices.")
                        .font(.caption)
                        .foregroundStyle(SharePalette.inkTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .padding(.top, 14)
                }

                Spacer()

                Button(action: onDismiss) {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(SharePalette.green)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }

    private var fleuronRule: some View {
        Rectangle()
            .fill(SharePalette.rule)
            .frame(width: 36, height: 1)
    }
}

/// The Athenaeum palette, duplicated minimally for the extension target.
private enum SharePalette {
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    static let canvas = adaptive(light: 0xF6F0E4, dark: 0x151009)
    static let ink = adaptive(light: 0x2A2115, dark: 0xF0E7D5)
    static let inkSecondary = adaptive(light: 0x77694F, dark: 0xAE9F83)
    static let inkTertiary = adaptive(light: 0xA2926F, dark: 0x7C7059)
    static let green = adaptive(light: 0x31553B, dark: 0x93C29E)
    static let brass = adaptive(light: 0x9A701F, dark: 0xDDB670)
    static let rule = adaptive(light: 0xE0D4BC, dark: 0x403524)
}
