import SwiftUI
import SwiftData
import Charts

/// Detail view for a WatchedBook — shows price history, eBay links,
/// and lets the user graduate the book into their main library.
struct WatchedBookDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var book: WatchedBook
    @State private var lookupService = BookLookupService()
    @State private var isFetchingPrice = false
    @State private var priceError: String?
    @State private var showDeleteConfirmation = false
    @State private var showAddedToLibrary = false
    @State private var addedBookTitle = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: Header
                VStack(spacing: 16) {
                    WatchedBookCoverView(book: book, width: 150, height: 225)
                        .padding(.top, 8)

                    VStack(spacing: 7) {
                        Text(book.title)
                            .font(Theme.display(24))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.center)

                        if !book.authors.isEmpty {
                            Text(book.authors)
                                .font(Theme.serif(17, weight: .medium))
                                .foregroundStyle(Theme.inkSecondary)
                        }

                        Label("Watching", systemImage: "eye.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.brass)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Theme.brass.opacity(0.12))
                            .clipShape(Capsule())
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .padding(.horizontal, 12)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Theme.rule.opacity(0.8), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.06), radius: 14, y: 6)

                // MARK: Price section
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        SectionEyebrow(text: "Price tracker")
                        Spacer()
                        Button {
                            Task { await refreshPrice() }
                        } label: {
                            if isFetchingPrice {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Refresh", systemImage: "arrow.clockwise")
                                    .font(.caption.weight(.medium))
                            }
                        }
                        .tint(Theme.green)
                        .disabled(isFetchingPrice)
                    }

                    // Current price
                    if let price = book.ebayLowestPrice {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(formatPrice(price))
                                .font(Theme.display(38))
                                .foregroundStyle(Theme.brass)
                                .contentTransition(.numericText())
                            Text("lowest")
                                .font(.subheadline)
                                .foregroundStyle(Theme.inkSecondary)
                            if let change = book.recentPriceChange {
                                PriceDeltaBadge(change: change)
                            }
                        }

                        if let updated = book.ebayPriceLastUpdated {
                            Text("Checked \(updated.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(Theme.inkTertiary)
                        }
                    } else if isFetchingPrice {
                        Text("Fetching price…")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSecondary)
                    } else {
                        Text("No price data yet — tap Refresh")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSecondary)
                    }

                    if let error = priceError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Theme.loss)
                    }

                    // eBay links
                    HStack(spacing: 12) {
                        if let listingURL = book.ebayListingURL, let url = URL(string: listingURL) {
                            Link(destination: url) {
                                Label("Original Listing", systemImage: "link")
                                    .font(.caption.weight(.medium))
                            }
                            .buttonStyle(.bordered)
                        }

                        if let searchURL = book.ebaySearchURL, let url = URL(string: searchURL) {
                            Link(destination: url) {
                                Label("All Listings", systemImage: "list.bullet")
                                    .font(.caption.weight(.medium))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .tint(Theme.green)

                    // Price history chart
                    if !book.priceHistory.isEmpty {
                        Rectangle()
                            .fill(Theme.rule)
                            .frame(height: 1)
                        WatchedPriceHistoryChartView(entries: book.priceHistory)
                    }
                }
                .cardStyle()

                // MARK: Details
                VStack(alignment: .leading, spacing: 14) {
                    SectionEyebrow(text: "Details")

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                        if !book.displayISBN.isEmpty && book.displayISBN != "No ISBN" {
                            GridRow {
                                Text("ISBN").foregroundStyle(Theme.inkSecondary)
                                Text(book.displayISBN).textSelection(.enabled)
                            }
                        }
                        GridRow {
                            Text("Added").foregroundStyle(Theme.inkSecondary)
                            Text(book.dateAdded.formatted(date: .abbreviated, time: .omitted))
                        }
                        if !book.authors.isEmpty {
                            GridRow {
                                Text("Author").foregroundStyle(Theme.inkSecondary)
                                Text(book.authors)
                            }
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                }
                .cardStyle()

                // MARK: Notes
                VStack(alignment: .leading, spacing: 10) {
                    SectionEyebrow(text: "Notes")
                    TextEditor(text: Binding(
                        get: { book.notes ?? "" },
                        set: { book.notes = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(minHeight: 88)
                    .font(.body)
                    .padding(10)
                    .background(Theme.well)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.rule, lineWidth: 1)
                    }
                }
                .cardStyle()

                // MARK: Add to Library
                Button {
                    addToLibrary()
                } label: {
                    Label("Add to My Library", systemImage: "books.vertical.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.green)
                .padding(.bottom, 24)
            }
            .padding()
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Watching")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "Remove from Watchlist?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                modelContext.delete(book)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Added to Library", isPresented: $showAddedToLibrary) {
            Button("OK") { dismiss() }
        } message: {
            Text("\"\(addedBookTitle)\" has been added to your library and removed from your watchlist.")
        }
        .task {
            // Auto-refresh if never fetched or stale (>24h)
            if book.ebayLowestPrice == nil ||
               book.ebayPriceLastUpdated.map({ Date().timeIntervalSince($0) > 86400 }) == true {
                await refreshPrice()
            }
        }
    }

    // MARK: - Actions

    private func refreshPrice() async {
        isFetchingPrice = true
        priceError = nil

        if let result = await lookupService.fetchEbayPrice(for: book) {
            withAnimation {
                book.ebayLowestPrice = result.lowestPrice
                book.ebaySearchURL = result.searchResultsURL
                book.ebayPriceLastUpdated = Date()
            }
            book.priceHistory.append(
                WatchedPriceEntry(price: result.lowestPrice, currency: result.currency)
            )
        } else {
            priceError = "Couldn't fetch a price. Check eBay settings or try again."
        }

        isFetchingPrice = false
    }

    /// Converts this WatchedBook into a Library Book and removes it from the watchlist.
    private func addToLibrary() {
        let libraryBook = Book(
            title: book.title,
            authors: book.authors,
            isbn: book.isbn,
            isbn13: book.isbn13,
            coverImageURL: book.coverImageURL,
            readingStatus: .wantToRead
        )
        libraryBook.coverImageData = book.coverImageData
        libraryBook.ebayLowestPrice = book.ebayLowestPrice
        libraryBook.ebayPriceURL = book.ebayListingURL
        libraryBook.ebayPriceLastUpdated = book.ebayPriceLastUpdated

        // Port price history across
        for entry in book.priceHistory {
            let newEntry = PriceHistoryEntry(price: entry.price, currency: entry.currency)
            newEntry.fetchedAt = entry.fetchedAt
            libraryBook.priceHistory.append(newEntry)
        }

        // Capture the title before deleting — the alert must not read the deleted model.
        addedBookTitle = book.title
        modelContext.insert(libraryBook)
        modelContext.delete(book)
        showAddedToLibrary = true
    }

    private func formatPrice(_ price: Double) -> String {
        price.formattedAsPrice()
    }
}

// MARK: - Price History Chart

/// Line chart showing price history for a WatchedBook.
struct WatchedPriceHistoryChartView: View {
    let entries: [WatchedPriceEntry]

    private var sorted: [WatchedPriceEntry] {
        entries.sorted { $0.fetchedAt < $1.fetchedAt }
    }

    private var minPrice: Double { sorted.map(\.price).min() ?? 0 }
    private var maxPrice: Double { sorted.map(\.price).max() ?? 0 }
    private var avgPrice: Double {
        guard !sorted.isEmpty else { return 0 }
        return sorted.map(\.price).reduce(0, +) / Double(sorted.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Price history")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)

            if sorted.count >= 2 {
                Chart(sorted, id: \.fetchedAt) { entry in
                    LineMark(
                        x: .value("Date", entry.fetchedAt),
                        y: .value("Price", entry.price)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Theme.gain)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    AreaMark(
                        x: .value("Date", entry.fetchedAt),
                        y: .value("Price", entry.price)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Theme.gain.opacity(0.12))

                    PointMark(
                        x: .value("Date", entry.fetchedAt),
                        y: .value("Price", entry.price)
                    )
                    .foregroundStyle(Theme.gain)
                    .symbolSize(24)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(Theme.rule)
                        AxisValueLabel {
                            if let price = value.as(Double.self) {
                                Text("$\(Int(price))")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date.formatted(.dateTime.month(.abbreviated).day()))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                        }
                    }
                }
                .frame(height: 150)

            } else if sorted.count == 1 {
                HStack {
                    Text("First check:")
                    Text(formatPrice(sorted[0].price))
                        .foregroundStyle(Theme.gain)
                    Spacer()
                    Text(sorted[0].fetchedAt.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .font(.subheadline)
            } else {
                Text("No price history yet.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }

            // Stats pills
            if sorted.count >= 2 {
                HStack(spacing: 8) {
                    statPill("Low", value: minPrice, color: Theme.gain)
                    statPill("Avg", value: avgPrice, color: Theme.brass)
                    statPill("High", value: maxPrice, color: Theme.loss)
                    Spacer()
                    Text("\(sorted.count) checks")
                        .font(.caption2)
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
        }
    }

    private func statPill(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundStyle(color)
            Text(formatPrice(value))
                .foregroundStyle(Theme.ink)
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }

    private func formatPrice(_ price: Double) -> String {
        price.formattedAsPrice()
    }
}

// MARK: - Cover View

struct WatchedBookCoverView: View {
    let book: WatchedBook
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
