import SwiftUI

/// "Athenaeum" — the app's design language.
///
/// A warm, editorial aesthetic inspired by a private library: ivory paper,
/// ink, library green and brass. Typography pairs a serif display face
/// (New York) with the system text face for legibility. All colors are
/// light/dark adaptive; dark mode reads as "reading by lamplight".
enum Theme {

    // MARK: - Color

    /// Light/dark adaptive color from two sRGB hex values.
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// Warm ivory paper (light) / lamp-lit espresso (dark). Main backdrop.
    static let canvas = adaptive(light: 0xF6F0E4, dark: 0x151009)
    /// Slightly raised paper for cards and grouped content.
    static let card = adaptive(light: 0xFFFDF7, dark: 0x211A10)
    /// Recessed paper for fields, chips and inset areas.
    static let well = adaptive(light: 0xEFE7D6, dark: 0x2A2216)
    /// Hairline / border tone.
    static let rule = adaptive(light: 0xE0D4BC, dark: 0x403524)

    /// Primary text — warm ink.
    static let ink = adaptive(light: 0x2A2115, dark: 0xF0E7D5)
    /// Secondary text.
    static let inkSecondary = adaptive(light: 0x77694F, dark: 0xAE9F83)
    /// Tertiary text / placeholders.
    static let inkTertiary = adaptive(light: 0xA2926F, dark: 0x7C7059)

    /// Library green — the app accent (buttons, tint, selected states).
    static let green = adaptive(light: 0x31553B, dark: 0x93C29E)
    /// Stronger green used on light surfaces where contrast matters.
    static let greenStrong = adaptive(light: 0x274731, dark: 0xA8D4B1)
    /// Brass — stars, valuation highlights, premium details.
    static let brass = adaptive(light: 0x9A701F, dark: 0xDDB670)
    /// Price moved in your favor.
    static let gain = adaptive(light: 0x2E6B45, dark: 0x85C996)
    /// Price moved against you.
    static let loss = adaptive(light: 0xAE3A2B, dark: 0xE58E79)

    /// Tinted fills behind gain/loss badges.
    static func gainWash() -> Color { gain.opacity(0.12) }
    static func lossWash() -> Color { loss.opacity(0.12) }

    // MARK: - Type

    /// Serif display face for hero moments (big numbers, screen titles).
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    /// Serif for titles / headlines.
    static func serif(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    /// Tracking-wide small caps eyebrow, e.g. section labels.
    static func eyebrow(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .semibold)
    }
    /// Numbers that should align (prices in lists).
    static func figure(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    // MARK: - Global appearance

    /// Applies the serif display face to navigation titles and the library
    /// green to bar buttons, app-wide. Called once from `LibraryApp.init`.
    @MainActor
    static func applyAppearances() {
        let inkUIColor = UIColor(ink)

        func serifFont(_ textStyle: UIFont.TextStyle) -> UIFont {
            let base = UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle)
            let serif = base.withDesign(.serif) ?? base
            let bolded = serif.withSymbolicTraits(serif.symbolicTraits.union(.traitBold)) ?? serif
            return UIFont(descriptor: bolded, size: 0)
        }

        let barAppearance = UINavigationBarAppearance()
        barAppearance.configureWithDefaultBackground()
        barAppearance.largeTitleTextAttributes = [
            .font: serifFont(.largeTitle),
            .foregroundColor: inkUIColor
        ]
        barAppearance.titleTextAttributes = [
            .font: serifFont(.headline),
            .foregroundColor: inkUIColor
        ]

        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance = barAppearance
        navBar.scrollEdgeAppearance = barAppearance
        navBar.compactAppearance = barAppearance

        UITabBar.appearance().unselectedItemTintColor = UIColor(inkSecondary)
    }
}

// MARK: - UIColor hex helper

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

// MARK: - Reusable styles & components

/// Raised paper card: fill, hairline border, soft ambient shadow.
///
/// The foot of the card carries a 19th-century gilt page-edge: the border
/// warms to gold along the bottom edge, and two gilt hairlines peek out
/// beneath like the gilded edges of pages stacked under the top sheet.
struct CardStyle: ViewModifier {
    var radius: CGFloat = 16
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Theme.rule.opacity(0.8), location: 0),
                                .init(color: Theme.rule.opacity(0.8), location: 0.70),
                                .init(color: Theme.brass.opacity(0.45), location: 0.90),
                                .init(color: Theme.brass.opacity(0.70), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .background {
                // Gilt page block beneath the top sheet
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Theme.brass.opacity(0.38), lineWidth: 1)
                        .padding(.horizontal, 6)
                        .offset(y: 3)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Theme.brass.opacity(0.20), lineWidth: 1)
                        .padding(.horizontal, 12)
                        .offset(y: 6)
                }
            }
            .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 6)
    }
}

extension View {
    func cardStyle(radius: CGFloat = 16, padding: CGFloat = 16) -> some View {
        modifier(CardStyle(radius: radius, padding: padding))
    }
}

/// Small-caps section label, e.g. "VALUATION".
struct SectionEyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.eyebrow())
            .tracking(1.6)
            .foregroundStyle(Theme.inkSecondary)
    }
}

/// Tappable filter chip used under navigation bars.
struct FilterChip: View {
    let title: String
    var systemImage: String?
    var isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Theme.card : Theme.ink)
            .background(isSelected ? Theme.green : Theme.well)
            .clipShape(Capsule())
            .overlay {
                Capsule().strokeBorder(isSelected ? .clear : Theme.rule, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isSelected)
    }
}

/// Brass star rating display (read-only).
struct StarRatingView: View {
    let rating: Int
    var size: CGFloat = 10

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(star <= rating ? Theme.brass : Theme.inkTertiary.opacity(0.45))
            }
        }
    }
}

/// Decorative fleuron used to ornament empty spaces and dividers.
struct Fleuron: View {
    var body: some View {
        HStack(spacing: 10) {
            rule
            Image(systemName: "diamond.fill")
                .font(.system(size: 5))
                .foregroundStyle(Theme.brass)
            rule
        }
    }

    private var rule: some View {
        Rectangle()
            .fill(Theme.rule)
            .frame(width: 36, height: 1)
    }
}
