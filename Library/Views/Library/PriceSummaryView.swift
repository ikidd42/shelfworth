import SwiftUI
import SwiftData

/// Shows a summary of all books' eBay prices, sortable by price
struct PriceSummaryView: View {
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]
    @State private var lookupService = BookLookupService()
    @State private var showPriceCheck = false

    private var booksWithPrices: [Book] {
        books.filter { $0.ebayLowestPrice != nil }
             .sorted { ($0.ebayLowestPrice ?? 0) > ($1.ebayLowestPrice ?? 0) }
    }

    private var booksWithoutPrices: [Book] {
        books.filter { $0.ebayLowestPrice == nil }
    }

    private var totalValue: Double {
        booksWithPrices.reduce(0) { $0 + ($1.ebayLowestPrice ?? 0) }
    }

    var body: some View {
        NavigationStack {
            List {
                // Summary card
                if !booksWithPrices.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Library Value Estimate")
                                .font(.headline)

                            Text(formatPrice(totalValue))
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundStyle(.green)

                            Text("Based on \(booksWithPrices.count) of \(books.count) books with eBay prices")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }

                // Books with prices
                if !booksWithPrices.isEmpty {
                    Section("Books with Prices") {
                        ForEach(booksWithPrices) { book in
                            NavigationLink(destination: BookDetailView(book: book)) {
                                priceRow(book)
                            }
                        }
                    }
                }

                // Books without prices
                if !booksWithoutPrices.isEmpty {
                    Section("No Price Data") {
                        ForEach(booksWithoutPrices) { book in
                            NavigationLink(destination: BookDetailView(book: book)) {
                                HStack {
                                    BookCoverView(book: book, width: 35, height: 52)
                                    VStack(alignment: .leading) {
                                        Text(book.title)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                        Text(book.authors)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text("—")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("eBay Prices")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showPriceCheck = true
                    } label: {
                        Label("Price Check", systemImage: "barcode.viewfinder")
                    }
                }
            }
            .sheet(isPresented: $showPriceCheck) {
                PriceCheckView()
                    .presentationDragIndicator(.visible)
            }
            .refreshable {
                await refreshAllPrices()
            }
            .overlay {
                if books.isEmpty {
                    ContentUnavailableView(
                        "No Books",
                        systemImage: "tag",
                        description: Text("Add books to your library to see pricing data.")
                    )
                } else if !APIConfiguration.shared.ebayIsConfigured && booksWithPrices.isEmpty {
                    // Only cover the list when there's truly nothing to show —
                    // books can already carry prices from before keys were removed.
                    ContentUnavailableView(
                        "eBay Not Configured",
                        systemImage: "key",
                        description: Text("Add your eBay API credentials in Settings to see pricing.")
                    )
                }
            }
        }
    }

    private func priceRow(_ book: Book) -> some View {
        HStack(spacing: 12) {
            BookCoverView(book: book, width: 35, height: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(book.authors)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatPrice(book.ebayLowestPrice ?? 0))
                    .font(.subheadline.weight(.semibold))

                if let change = book.recentPriceChange {
                    PriceDeltaBadge(change: change, perspective: .owning)
                } else if let lastUpdated = book.ebayPriceLastUpdated {
                    Text(lastUpdated.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func refreshAllPrices() async {
        for book in books {
            if let result = await lookupService.fetchEbayPrice(for: book) {
                book.ebayLowestPrice = result.lowestPrice
                book.ebayPriceURL = result.listingURL
                book.ebayPriceLastUpdated = Date()

                // Record price history
                let entry = PriceHistoryEntry(price: result.lowestPrice, currency: result.currency)
                book.priceHistory.append(entry)
            }

            // Small delay to avoid rate limiting
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private func formatPrice(_ price: Double) -> String {
        price.formattedAsPrice()
    }
}
