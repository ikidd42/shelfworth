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
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !booksWithPrices.isEmpty {
                        valuationCard
                    }

                    if !booksWithPrices.isEmpty {
                        pricedSection
                    }

                    if !booksWithoutPrices.isEmpty {
                        unpricedSection
                    }
                }
                .padding()
                .padding(.bottom, 12)
            }
            .background(Theme.canvas.ignoresSafeArea())
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

    // MARK: - Valuation Hero

    private var valuationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionEyebrow(text: "Collection value")
                Spacer()
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.subheadline)
                    .foregroundStyle(Theme.brass)
            }

            Text(formatPrice(totalValue))
                .font(Theme.display(44))
                .foregroundStyle(Theme.brass)
                .contentTransition(.numericText())

            Text("Across \(booksWithPrices.count) of \(books.count) volume\(books.count == 1 ? "" : "s") with eBay appraisals")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)

            if let top = booksWithPrices.first {
                Rectangle()
                    .fill(Theme.rule)
                    .frame(height: 1)
                    .padding(.vertical, 2)

                HStack(spacing: 10) {
                    BookCoverView(book: top, width: 28, height: 42)
                    Text("Most valuable: \(top.title)")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                    Spacer()
                    Text(formatPrice(top.ebayLowestPrice ?? 0))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .cardStyle(radius: 20, padding: 20)
    }

    // MARK: - Sections

    private var pricedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Appraised")
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(booksWithPrices.enumerated()), id: \.element.id) { index, book in
                    NavigationLink(destination: BookDetailView(book: book)) {
                        priceRow(book)
                    }
                    .buttonStyle(.plain)

                    if index < booksWithPrices.count - 1 {
                        Rectangle()
                            .fill(Theme.rule)
                            .frame(height: 1)
                            .padding(.leading, 66)
                    }
                }
            }
            .cardStyle(padding: 0)
        }
    }

    private var unpricedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Awaiting appraisal")
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(booksWithoutPrices.enumerated()), id: \.element.id) { index, book in
                    NavigationLink(destination: BookDetailView(book: book)) {
                        HStack(spacing: 12) {
                            BookCoverView(book: book, width: 38, height: 57)
                                .saturation(0.4)
                                .opacity(0.8)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(book.title)
                                    .font(Theme.serif(15, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Text(book.authors)
                                    .font(.caption)
                                    .foregroundStyle(Theme.inkSecondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text("—")
                                .foregroundStyle(Theme.inkTertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                    }
                    .buttonStyle(.plain)

                    if index < booksWithoutPrices.count - 1 {
                        Rectangle()
                            .fill(Theme.rule)
                            .frame(height: 1)
                            .padding(.leading, 66)
                    }
                }
            }
            .cardStyle(padding: 0)
        }
    }

    private func priceRow(_ book: Book) -> some View {
        HStack(spacing: 12) {
            BookCoverView(book: book, width: 38, height: 57)

            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(Theme.serif(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(book.authors)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(formatPrice(book.ebayLowestPrice ?? 0))
                    .font(Theme.figure(16))
                    .foregroundStyle(Theme.ink)

                if let change = book.recentPriceChange {
                    PriceDeltaBadge(change: change, perspective: .owning)
                } else if let lastUpdated = book.ebayPriceLastUpdated {
                    Text(lastUpdated.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(Theme.inkTertiary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.inkTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
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
