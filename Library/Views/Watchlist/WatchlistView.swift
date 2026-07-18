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
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !watchedBooks.isEmpty {
                        TipView(shareTip)
                            .tipViewStyle(ThemedTipStyle())
                    }

                    if !watchedBooks.isEmpty {
                        summaryCard
                        watchingSection
                    }
                }
                .padding()
                .padding(.bottom, 12)
            }
            .background(Theme.canvas.ignoresSafeArea())
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
                    emptyState
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

    // MARK: - Summary Card

    private var summaryCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                SectionEyebrow(text: "Watching")

                Text("\(watchedBooks.count) book\(watchedBooks.count == 1 ? "" : "s")")
                    .font(Theme.display(28))
                    .foregroundStyle(Theme.ink)

                if let total = totalValue {
                    Text("Combined lowest: \(formatPrice(total))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }

            Spacer()

            Image(systemName: "eye.fill")
                .font(.system(size: 26))
                .foregroundStyle(Theme.brass.opacity(0.7))
        }
        .cardStyle(radius: 20, padding: 20)
    }

    // MARK: - Watching Section

    private var watchingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "On the radar")
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(watchedBooks.enumerated()), id: \.element.id) { index, book in
                    NavigationLink(destination: WatchedBookDetailView(book: book)) {
                        watchRow(book)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            withAnimation { modelContext.delete(book) }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }

                    if index < watchedBooks.count - 1 {
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

    // MARK: - Row

    private func watchRow(_ book: WatchedBook) -> some View {
        HStack(spacing: 12) {
            WatchedBookCoverView(book: book, width: 38, height: 57)

            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(Theme.serif(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(book.authors.isEmpty ? "Unknown Author" : book.authors)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if let price = book.ebayLowestPrice {
                    Text(formatPrice(price))
                        .font(Theme.figure(16))
                        .foregroundStyle(Theme.ink)
                    if let change = book.recentPriceChange {
                        PriceDeltaBadge(change: change)
                    } else if let updated = book.ebayPriceLastUpdated {
                        Text(updated.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundStyle(Theme.inkTertiary)
                    }
                } else {
                    Text("No price yet")
                        .font(.caption)
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "binoculars.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.brass)

            Text("Nothing on the radar")
                .font(Theme.display(26))

            Text("Share an eBay listing to Library, or search\nfor a book to track its price.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)

            Button {
                showAddSheet = true
            } label: {
                Label("Add a Book", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.green)
            .padding(.top, 4)
        }
        .padding()
    }

    // MARK: - Actions

    private var totalValue: Double? {
        let prices = watchedBooks.compactMap(\.ebayLowestPrice)
        guard !prices.isEmpty else { return nil }
        return prices.reduce(0, +)
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

// MARK: - Themed Tip Style

/// TipKit style matching the paper-and-brass design language.
struct ThemedTipStyle: TipViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "square.and.arrow.up")
                .font(.title3)
                .foregroundStyle(Theme.brass)

            VStack(alignment: .leading, spacing: 4) {
                if let title = configuration.title {
                    title
                        .font(Theme.serif(15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                if let message = configuration.message {
                    message
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }

            Spacer()

            Button(action: { configuration.tip.invalidate(reason: .tipClosed) }) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .cardStyle()
    }
}
