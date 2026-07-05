import SwiftUI

/// Small capsule showing recent price movement, e.g. "↓ $3.50".
///
/// Color depends on perspective: on the watchlist you're a buyer, so a
/// falling price is good news (green); for a book you own, a rising price
/// means your copy gained value, so up is the green direction.
struct PriceDeltaBadge: View {
    enum Perspective {
        /// Watchlist: you want to buy this book, cheaper is better.
        case buying
        /// Library: you own this book, appreciation is better.
        case owning
    }

    let change: Double
    var perspective: Perspective = .buying

    private var isRise: Bool { change > 0 }

    private var isGoodNews: Bool {
        switch perspective {
        case .buying: !isRise
        case .owning: isRise
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: isRise ? "arrow.up" : "arrow.down")
                .font(.system(size: 8, weight: .bold))
            Text(abs(change).formattedAsPrice())
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(isGoodNews ? .green : .red)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((isGoodNews ? Color.green : Color.red).opacity(0.12))
        .clipShape(Capsule())
        .accessibilityLabel("Price \(isRise ? "rose" : "dropped") \(abs(change).formattedAsPrice())")
    }
}
