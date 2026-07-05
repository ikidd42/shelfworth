import Foundation

/// Computes recent price movement from a book's price-check history.
nonisolated enum PriceTrend {

    /// The signed change between the latest price and the most recent *different*
    /// price before it (negative = the price dropped).
    ///
    /// Refreshes append an entry even when the price hasn't moved, so comparing
    /// only the last two checks would almost always report "no change". Walking
    /// back to the last differing price answers the question the user actually
    /// has: "what happened since this price changed?"
    /// Returns nil when there are fewer than two distinct prices.
    static func recentChange(in chronologicalPrices: [Double]) -> Double? {
        guard let latest = chronologicalPrices.last else { return nil }
        for earlier in chronologicalPrices.dropLast().reversed() where earlier != latest {
            return latest - earlier
        }
        return nil
    }
}

extension Book {
    /// Signed price movement since the last time the eBay price changed.
    var recentPriceChange: Double? {
        PriceTrend.recentChange(
            in: priceHistory.sorted { $0.fetchedAt < $1.fetchedAt }.map(\.price)
        )
    }
}

extension WatchedBook {
    /// Signed price movement since the last time the eBay price changed.
    var recentPriceChange: Double? {
        PriceTrend.recentChange(
            in: priceHistory.sorted { $0.fetchedAt < $1.fetchedAt }.map(\.price)
        )
    }
}
