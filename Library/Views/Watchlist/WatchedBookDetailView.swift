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
            VStack(spacing: 0) {
                // MARK: Header
                VStack(spacing: 12) {
                    WatchedBookCoverView(book: book, width: 120, height: 180)
                        .shadow(radius: 6, y: 3)
                        .padding(.top, 20)

                    Text(book.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if !book.authors.isEmpty {
                        Text(book.authors)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 20)

                Divider()

                // MARK: Price section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label("eBay Price Tracker", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.headline)
                        Spacer()
                        Button {
                            Task { await refreshPrice() }
                        } label: {
                            if isFetchingPrice {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Refresh", systemImage: "arrow.clockwise")
                                    .font(.caption)
                            }
                        }
                        .disabled(isFetchingPrice)
                    }

                    // Current price
                    if let price = book.ebayLowestPrice {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(formatPrice(price))
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundStyle(.green)
                            Text("lowest")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let change = book.recentPriceChange {
                                PriceDeltaBadge(change: change)
                            }
                        }

                        if let updated = book.ebayPriceLastUpdated {
                            Text("Updated \(updated.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    } else if isFetchingPrice {
                        Text("Fetching price...")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No price data yet — tap Refresh")
                            .foregroundStyle(.secondary)
                    }

                    if let error = priceError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    // eBay links
                    HStack(spacing: 12) {
                        if let listingURL = book.ebayListingURL, let url = URL(string: listingURL) {
                            Link(destination: url) {
                                Label("Original Listing", systemImage: "link")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }

                        if let searchURL = book.ebaySearchURL, let url = URL(string: searchURL) {
                            Link(destination: url) {
                                Label("All Listings", systemImage: "list.bullet")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    // Price history chart
                    if !book.priceHistory.isEmpty {
                        Divider()
                        WatchedPriceHistoryChartView(entries: book.priceHistory)
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.top, 16)

                // MARK: Details
                VStack(alignment: .leading, spacing: 16) {
                    Text("Details")
                        .font(.headline)

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                        if !book.displayISBN.isEmpty && book.displayISBN != "No ISBN" {
                            GridRow {
                                Text("ISBN").foregroundStyle(.secondary)
                                Text(book.displayISBN).textSelection(.enabled)
                            }
                        }
                        GridRow {
                            Text("Added").foregroundStyle(.secondary)
                            Text(book.dateAdded.formatted(date: .abbreviated, time: .omitted))
                        }
                        if !book.authors.isEmpty {
                            GridRow {
                                Text("Author").foregroundStyle(.secondary)
                                Text(book.authors)
                            }
                        }
                    }
                    .font(.subheadline)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.top, 12)

                // MARK: Notes
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.headline)
                    TextEditor(text: Binding(
                        get: { book.notes ?? "" },
                        set: { book.notes = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(minHeight: 80)
                    .font(.body)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.top, 12)

                // MARK: Add to Library
                Button {
                    addToLibrary()
                } label: {
                    Label("Add to My Library", systemImage: "books.vertical.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
        }
        .background(Color(.systemGroupedBackground))
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
            book.ebayLowestPrice = result.lowestPrice
            book.ebaySearchURL = result.searchResultsURL
            book.ebayPriceLastUpdated = Date()
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Price History")
                .font(.subheadline.weight(.medium))

            if sorted.count >= 2 {
                Chart(sorted, id: \.fetchedAt) { entry in
                    LineMark(
                        x: .value("Date", entry.fetchedAt),
                        y: .value("Price", entry.price)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.green)

                    PointMark(
                        x: .value("Date", entry.fetchedAt),
                        y: .value("Price", entry.price)
                    )
                    .foregroundStyle(.green)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let price = value.as(Double.self) {
                                Text("$\(Int(price))")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date.formatted(.dateTime.month(.abbreviated).day()))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 140)

            } else if sorted.count == 1 {
                HStack {
                    Text("First check:")
                    Text(formatPrice(sorted[0].price))
                        .foregroundStyle(.green)
                    Spacer()
                    Text(sorted[0].fetchedAt.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            } else {
                Text("No price history yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Stats pills
            if sorted.count >= 2 {
                HStack(spacing: 8) {
                    statPill("Low", value: minPrice, color: .blue)
                    statPill("Avg", value: avgPrice, color: .orange)
                    statPill("High", value: maxPrice, color: .red)
                    Spacer()
                    Text("\(sorted.count) checks")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func statPill(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundStyle(color)
            Text(formatPrice(value))
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
        Group {
            if let data = book.coverImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if let urlString = book.coverImageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 4) {
                Text(book.title)
                    .font(.system(size: min(width * 0.13, 12), weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 4)
                if !book.authors.isEmpty {
                    Text(book.authors)
                        .font(.system(size: min(width * 0.10, 10)))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private var gradientColors: [Color] {
        let palettes: [[Color]] = [
            [.indigo, .purple],
            [.teal, .blue],
            [.orange, .red],
            [.green, .teal],
            [.pink, .purple],
            [.blue, .indigo],
        ]
        let index = abs(book.title.hashValue) % palettes.count
        return palettes[index]
    }
}
