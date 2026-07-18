import SwiftUI

/// Core cover renderer: image (data or URL) with a generated cloth-bound
/// placeholder fallback. Every variant gets a spine highlight and contact
/// shadow so books read as physical objects on the shelf.
struct CoverArtView: View {
    let title: String
    let authors: String
    var imageData: Data?
    var imageURL: String?
    var width: CGFloat = 120
    var height: CGFloat = 180

    /// Lazily rendered marbled sheet for half-leather bindings.
    @State private var marble: UIImage?

    /// Roughly one title in three gets a half-leather marbled binding;
    /// the rest stay full cloth. Stable per title.
    private var marbledKind: Marbling.Kind? {
        Marbling.kind(forTitle: title)
    }

    var body: some View {
        coverContent
            .frame(width: width, height: height)
            .clipShape(BookShape(spine: spineWidth))
            .overlay { spineAndEdgeShading }
            .overlay {
                BookShape(spine: spineWidth)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.28), radius: 8, x: 0, y: 4)
            .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
    }

    /// The spine takes ~7% of the cover width.
    private var spineWidth: CGFloat { max(4, width * 0.07) }

    @ViewBuilder
    private var coverContent: some View {
        if let imageData,
           let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let imageURL,
                  let url = URL(string: imageURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    placeholderCover
                case .empty:
                    placeholderCover
                        .overlay { ProgressView().tint(.white.opacity(0.8)) }
                @unknown default:
                    placeholderCover
                }
            }
        } else {
            placeholderCover
        }
    }

    /// Leading-edge spine shadow + page-edge highlight, drawn over any cover.
    private var spineAndEdgeShading: some View {
        HStack(spacing: 0) {
            // Spine: hinge shadow then a hairline highlight
            ZStack {
                LinearGradient(
                    colors: [.black.opacity(0.38), .black.opacity(0.12), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                HStack {
                    Spacer()
                    Rectangle()
                        .fill(.white.opacity(0.22))
                        .frame(width: 1)
                }
            }
            .frame(width: spineWidth)

            // Subtle vignette lifting toward the page edge
            LinearGradient(
                colors: [.black.opacity(0.10), .clear, .clear, .black.opacity(0.08)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .clipShape(BookShape(spine: spineWidth))
        .allowsHitTesting(false)
    }

    /// Generated placeholder when no image is available: half-leather with
    /// marbled boards for some books, full cloth for the rest.
    @ViewBuilder
    private var placeholderCover: some View {
        if let kind = marbledKind {
            halfLeatherCover(kind: kind)
        } else {
            clothCover
        }
    }

    /// Full cloth binding (the original look).
    private var clothCover: some View {
        let palette = CoverPalette.forTitle(title)
        return ZStack {
            // Cloth base
            LinearGradient(
                colors: palette.cloth,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Woven texture suggestion
            Canvas { context, size in
                let step: CGFloat = 3
                var y: CGFloat = 0
                while y < size.height {
                    let path = Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(path, with: .color(.white.opacity(0.025)), lineWidth: 1)
                    y += step
                }
            }
            .allowsHitTesting(false)

            if width >= 64 {
                fullJacket(palette: palette)
            } else {
                monogramJacket(foil: palette.foil)
            }
        }
        .frame(width: width, height: height)
    }

    /// Half-leather binding: leather spine strip, marbled paper boards, and a
    /// gilt-stamped leather title label — the 19th-century fine binding.
    private func halfLeatherCover(kind: Marbling.Kind) -> some View {
        let leather = CoverPalette.leather
        let stripWidth = max(6, width * 0.17)

        return ZStack {
            // Leather base (visible while the marble sheet renders)
            LinearGradient(colors: leather, startPoint: .top, endPoint: .bottom)

            // Marbled boards
            if let marble {
                Image(uiImage: marble)
                    .resizable()
                    .scaledToFill()
                    .padding(.leading, stripWidth)
                    .transition(.opacity)
            }

            // Leather spine strip with gilt rules
            HStack(spacing: 0) {
                ZStack {
                    LinearGradient(
                        colors: [leather[0], leather[1]],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    HStack {
                        Spacer()
                        Rectangle()
                            .fill(CoverPalette.giltColor.opacity(0.65))
                            .frame(width: 1)
                        Rectangle()
                            .fill(CoverPalette.giltColor.opacity(0.3))
                            .frame(width: 1)
                            .padding(.leading, 2)
                    }
                    Rectangle()
                        .fill(.black.opacity(0.18))
                        .frame(width: 3)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(width: stripWidth)
                Spacer(minLength: 0)
            }

            if width >= 64 {
                titleLabel
                    .padding(.leading, stripWidth)
            } else {
                monogramJacket(foil: CoverPalette.giltColor)
                    .padding(.leading, stripWidth)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .task(id: "\(kind.rawValue)-\(title)-\(Int(width))x\(Int(height))") {
            let seed = Marbling.stableSeed(title)
            let img = await Marbling.image(
                kind: kind, seed: seed,
                size: CGSize(width: width - stripWidth, height: height)
            )
            withAnimation(.easeIn(duration: 0.3)) { marble = img }
        }
    }

    /// Gilt-stamped leather title label pasted on the marbled board.
    private var titleLabel: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: max(10, width * 0.10), weight: .bold, design: .serif))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .foregroundStyle(CoverPalette.giltColor)
                .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                .fixedSize(horizontal: false, vertical: true)

            Image(systemName: "diamond.fill")
                .font(.system(size: 4))
                .foregroundStyle(CoverPalette.giltColor.opacity(0.8))
                .padding(.vertical, max(3, height * 0.028))

            if !authors.isEmpty {
                Text(authors)
                    .font(.system(size: max(7.5, width * 0.068), weight: .medium, design: .serif))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(CoverPalette.giltColor.opacity(0.85))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, max(6, height * 0.05))
        .background {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(LinearGradient(colors: CoverPalette.leather, startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(CoverPalette.giltColor.opacity(0.7), lineWidth: 1)
                .padding(2)
        }
        .padding(.horizontal, 10)
    }

    /// Full jacket for shelf-size covers: gilt frame, title, ornament, author.
    private func fullJacket(palette: CoverPalette) -> some View {
        ZStack {
            // Gilt double-rule frame
            giltFrame(palette: palette)
                .padding(spineWidth / 2)

            // Title / ornament / author
            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: max(11, width * 0.105), weight: .bold, design: .serif))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .foregroundStyle(palette.foil)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .fixedSize(horizontal: false, vertical: true)

                Image(systemName: "diamond.fill")
                    .font(.system(size: 4.5))
                    .foregroundStyle(palette.foil.opacity(0.8))
                    .padding(.vertical, max(4, height * 0.035))

                if !authors.isEmpty {
                    Text(authors)
                        .font(.system(size: max(8, width * 0.075), weight: .medium, design: .serif))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .foregroundStyle(palette.foil.opacity(0.85))
                }
            }
            .padding(.leading, spineWidth + 8)
            .padding(.trailing, 8)
        }
    }

    /// Simplified jacket for row thumbnails: a single serif initial.
    private func monogramJacket(foil: Color) -> some View {
        Text(title.prefix(1).uppercased())
            .font(.system(size: width * 0.42, weight: .bold, design: .serif))
            .foregroundStyle(foil)
            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            .padding(.leading, spineWidth)
    }

    private func giltFrame(palette: CoverPalette) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .strokeBorder(palette.foil.opacity(0.55), lineWidth: 1.4)
            .padding(1)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(palette.foil.opacity(0.3), lineWidth: 0.6)
                    .padding(4)
            }
            .padding(6)
    }
}

/// Displays a library book's cover.
struct BookCoverView: View {
    let book: Book
    var width: CGFloat = 120
    var height: CGFloat = 180

    var body: some View {
        CoverArtView(
            title: book.title,
            authors: book.authors,
            imageData: book.coverImageData,
            imageURL: book.coverImageURL,
            width: width,
            height: height
        )
    }
}

/// A rounded rectangle with a squared-off leading edge for the spine.
struct BookShape: InsettableShape {
    var spine: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius: CGFloat = max(0, 5 - insetAmount)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                       control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> BookShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// Cloth + foil colorways for generated covers, chosen by title hash.
struct CoverPalette {
    let cloth: [Color]
    let foil: Color

    /// Stable palette choice. Swift's `hashValue` is randomized per process,
    /// so a simple deterministic djb2 keeps a book's cloth consistent
    /// between launches.
    static func forTitle(_ title: String) -> CoverPalette {
        var hash: UInt = 5381
        for byte in title.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt(byte)
        }
        return all[Int(hash % UInt(all.count))]
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }

    private static let gilt = rgb(0xE8D5A3)

    /// Shared gilt tone for stamping on leather.
    static let giltColor = rgb(0xE8D5A3)

    /// Deep calf-leather gradient for spine strips and title labels.
    static let leather: [Color] = [rgb(0x4A2E1E), rgb(0x2B190E)]

    private static let all: [CoverPalette] = [
        // Forest green cloth
        CoverPalette(cloth: [rgb(0x3D5A44), rgb(0x24382A)], foil: gilt),
        // Oxblood leather
        CoverPalette(cloth: [rgb(0x7A3B2E), rgb(0x4E231B)], foil: gilt),
        // Midnight navy
        CoverPalette(cloth: [rgb(0x33465E), rgb(0x1E2B3D)], foil: gilt),
        // Ochre linen
        CoverPalette(cloth: [rgb(0xA97B2F), rgb(0x6F4E1B)], foil: rgb(0xFFF3D6)),
        // Plum buckram
        CoverPalette(cloth: [rgb(0x5E3A55), rgb(0x3A2235)], foil: gilt),
        // Charcoal cloth
        CoverPalette(cloth: [rgb(0x4A463F), rgb(0x2B2823)], foil: gilt),
        // Teal cloth
        CoverPalette(cloth: [rgb(0x2F5A58), rgb(0x1B3837)], foil: gilt),
        // Russet leather
        CoverPalette(cloth: [rgb(0x8A5426), rgb(0x57331A)], foil: rgb(0xFFF3D6)),
    ]
}

/// Small price tag overlay for grid items — a dark green tag with cream text,
/// like a bookseller's price ticket.
struct PriceBadgeView: View {
    let price: Double?
    let currency: String

    var body: some View {
        if let price = price {
            Text(price.formattedAsPrice(currency: currency))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.98, green: 0.95, blue: 0.87))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color(red: 0.16, green: 0.30, blue: 0.21).opacity(0.94))
                .clipShape(Capsule())
                .overlay {
                    Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        }
    }
}
