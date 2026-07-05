import SwiftUI
import SwiftData
import TipKit
import os

/// Displays all watched books and their current eBay market prices.
/// Books can be added by sharing an eBay listing or via the + button to search manually.
struct WatchlistView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WatchedBook.dateAdded, order: .reverse) private var watchedBooks: [WatchedBook]

    @State private var lookupService = BookLookupService()
    @State private var showAddSheet = false

    private let shareTip = ShareToWatchlistTip()

    var body: some View {
        NavigationStack {
            List {
                if !watchedBooks.isEmpty {
                    TipView(shareTip)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                // Summary card
                if !watchedBooks.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Watching \(watchedBooks.count) book\(watchedBooks.count == 1 ? "" : "s")")
                                .font(.headline)
                            if let total = totalValue {
                                Text("Combined lowest price: \(formatPrice(total))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Watched books list
                ForEach(watchedBooks) { book in
                    NavigationLink(destination: WatchedBookDetailView(book: book)) {
                        watchRow(book)
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .navigationTitle("Watchlist")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .refreshable {
                await refreshAllPrices()
            }
            .overlay {
                if watchedBooks.isEmpty {
                    ContentUnavailableView {
                        Label("No Watched Books", systemImage: "eye")
                    } description: {
                        Text("Share an eBay listing to the Library app, or tap + to search for a book to track.")
                    } actions: {
                        Button("Add a Book") { showAddSheet = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            // Ingest on first load
            .task { await ingestPendingItems() }
            // Also ingest whenever the app returns to the foreground (e.g. after sharing from eBay)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task { await ingestPendingItems() }
            }
            .sheet(isPresented: $showAddSheet) {
                WatchlistSearchSheet { result in
                    Task { await addWatchedBook(from: result) }
                }
            }
        }
    }

    // MARK: - Row

    private func watchRow(_ book: WatchedBook) -> some View {
        HStack(spacing: 12) {
            WatchedBookCoverView(book: book, width: 35, height: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(book.authors.isEmpty ? "Unknown Author" : book.authors)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let price = book.ebayLowestPrice {
                    Text(formatPrice(price))
                        .font(.subheadline.weight(.semibold))
                    if let change = book.recentPriceChange {
                        PriceDeltaBadge(change: change)
                    } else if let updated = book.ebayPriceLastUpdated {
                        Text(updated.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text("No price yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private var totalValue: Double? {
        let prices = watchedBooks.compactMap(\.ebayLowestPrice)
        guard !prices.isEmpty else { return nil }
        return prices.reduce(0, +)
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(watchedBooks[index])
        }
    }

    /// Batch-refreshes lowest eBay prices for all watched books.
    private func refreshAllPrices() async {
        for book in watchedBooks {
            if let result = await lookupService.fetchEbayPrice(for: book) {
                book.ebayLowestPrice = result.lowestPrice
                book.ebaySearchURL = result.searchResultsURL
                book.ebayPriceLastUpdated = Date()
                let entry = WatchedPriceEntry(price: result.lowestPrice, currency: result.currency)
                book.priceHistory.append(entry)
            }
            // Respect eBay rate limits
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    /// Reads items queued by the Share Extension and creates WatchedBook records.
    @MainActor
    private func ingestPendingItems() async {
        let pending = SharedContainer.readPendingItems()
        guard !pending.isEmpty else { return }

        Logger.watchlist.info("Ingesting \(pending.count) shared item(s)")
        SharedContainer.clearPendingItems()

        for item in pending {
            // Insert a placeholder immediately so the row appears in the list
            let watched = WatchedBook(
                title: item.listingTitle,
                ebayItemID: item.ebayItemID,
                ebayListingURL: item.ebayListingURL
            )
            modelContext.insert(watched)

            // Enrich asynchronously: real eBay title → Google Books metadata → price lookup
            Task { @MainActor in
                await enrichWatchedBook(watched, from: item)
            }
        }
    }

    /// Full enrichment pipeline for a just-shared eBay item:
    /// 1. Fetch real listing title from eBay item endpoint
    /// 2. Search Google Books / Open Library for clean book metadata
    /// 3. Fetch lowest eBay market price using the clean metadata
    private func enrichWatchedBook(_ watched: WatchedBook, from item: PendingWatchItem) async {
        // Step 1: Get the real listing title from eBay
        let listingTitle = await lookupService.fetchEbayItemTitle(itemID: item.ebayItemID) ?? item.listingTitle
        let cleanedTitle = EbayTitleCleaner.clean(listingTitle)

        // Step 2: Find the actual book in Google Books / Open Library
        let searchTitle = cleanedTitle.isEmpty ? listingTitle : cleanedTitle
        let bookResults = await lookupService.searchFreeTextResults(searchTitle)

        if let match = bookResults.first {
            watched.title = match.title
            watched.authors = match.authors
            watched.isbn = match.isbn
            watched.isbn13 = match.isbn13
            watched.coverImageURL = match.coverImageURL
            if let coverURL = match.coverImageURL {
                watched.coverImageData = await lookupService.downloadCoverImage(from: coverURL)
            }
        } else {
            Logger.watchlist.info("No book match found for '\(searchTitle)', keeping cleaned title")
            watched.title = searchTitle
        }

        // Step 3: Now price-lookup with proper title / author / ISBN
        if let result = await lookupService.fetchEbayPrice(for: watched) {
            watched.ebayLowestPrice = result.lowestPrice
            watched.ebaySearchURL = result.searchResultsURL
            watched.ebayPriceLastUpdated = Date()
            watched.priceHistory.append(
                WatchedPriceEntry(price: result.lowestPrice, currency: result.currency)
            )
        } else {
            Logger.watchlist.info("Price fetch returned no results for '\(watched.title)'")
        }
    }

    /// Adds a book from a manual search result to the watchlist.
    private func addWatchedBook(from result: BookSearchResult) async {
        let watched = WatchedBook(
            title: result.title,
            authors: result.authors,
            isbn: result.isbn,
            isbn13: result.isbn13,
            coverImageURL: result.coverImageURL
        )

        // Insert first so the row appears immediately, then fill in the price.
        modelContext.insert(watched)

        if let result = await lookupService.fetchEbayPrice(for: watched) {
            watched.ebayLowestPrice = result.lowestPrice
            watched.ebaySearchURL = result.searchResultsURL
            watched.ebayPriceLastUpdated = Date()
            watched.priceHistory.append(
                WatchedPriceEntry(price: result.lowestPrice, currency: result.currency)
            )
        }
    }

    private func formatPrice(_ price: Double) -> String {
        price.formattedAsPrice()
    }
}
