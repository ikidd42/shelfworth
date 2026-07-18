import SwiftUI
import SwiftData

/// Quick price-check mode: scan a barcode or enter an ISBN, see the eBay price
/// immediately without adding the book to the library. Perfect for browsing
/// at a bookstore and checking if a book is fairly priced.
struct PriceCheckView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var existingBooks: [Book]
    @State private var lookupService = BookLookupService()

    // Scan state
    @State private var showScanner = false
    @State private var scannedCode: String?

    // Manual entry
    @State private var manualTitle = ""
    @State private var manualAuthor = ""

    // Duplicate detection
    @State private var duplicateBook: Book?
    @State private var pendingAddResult: BookSearchResult?
    @State private var showDuplicateAlert = false

    // Results
    @State private var bookResult: BookSearchResult?
    @State private var ebayResult: EbayPriceResult?
    @State private var isLookingUp = false
    @State private var isFetchingPrice = false
    @State private var errorMessage: String?

    // History of recent checks (in-memory, not persisted)
    @State private var recentChecks: [PriceCheck] = []

    struct PriceCheck: Identifiable {
        let id = UUID()
        let title: String
        let authors: String
        let coverURL: String?
        let ebayPrice: Double?
        let ebayURL: String?
        let searchResult: BookSearchResult
        let timestamp: Date = Date()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Scan button
                    scanSection

                    // Manual ISBN entry
                    manualEntrySection

                    // Current result
                    if isLookingUp || isFetchingPrice {
                        loadingSection
                    }

                    if let error = errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.brass)
                            .font(.subheadline)
                            .padding(.horizontal)
                    }

                    if let book = bookResult {
                        resultCard(book)
                    }

                    // Recent checks
                    if !recentChecks.isEmpty {
                        recentChecksSection
                    }
                }
                .padding(.vertical)
            }
            .background(Theme.canvas.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .navigationTitle("Price Check")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                BarcodeScannerSheet(scannedISBN: $scannedCode)
            }
            .onChange(of: scannedCode) { _, code in
                if let code = code {
                    Task { await lookup(code: code) }
                }
            }
            .alert("Duplicate Book", isPresented: $showDuplicateAlert) {
                Button("Add Copy") {
                    if let existing = duplicateBook {
                        existing.copyCount += 1
                    }
                    pendingAddResult = nil
                    duplicateBook = nil
                }
                Button("Add Anyway") {
                    if let result = pendingAddResult {
                        insertBook(from: result)
                    }
                    pendingAddResult = nil
                    duplicateBook = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingAddResult = nil
                    duplicateBook = nil
                }
            } message: {
                if let existing = duplicateBook {
                    Text("\"\(existing.title)\" is already in your library\(existing.copyCount > 1 ? " (\(existing.copyCount) copies)" : ""). Add another copy or add as a separate entry?")
                }
            }
        }
    }

    // MARK: - Scan Section

    private var scanSection: some View {
        Button {
            clearResult()
            showScanner = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.green)
                VStack(alignment: .leading) {
                    Text("Scan Barcode")
                        .font(Theme.serif(17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Quick price lookup")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding()
            .background(Theme.green.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.green.opacity(0.25), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    // MARK: - Manual Entry

    private var manualEntrySection: some View {
        HStack(spacing: 8) {
            TextField("Title", text: $manualTitle)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .onSubmit { manualLookup() }

            TextField("Author", text: $manualAuthor)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .onSubmit { manualLookup() }

            Button {
                manualLookup()
            } label: {
                Image(systemName: "magnifyingglass")
                    .padding(8)
                    .background(Theme.green)
                    .foregroundStyle(Theme.card)
                    .clipShape(Circle())
            }
            .disabled(manualTitle.trimmingCharacters(in: .whitespaces).isEmpty && manualAuthor.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal)
    }

    // MARK: - Loading

    private var loadingSection: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text(isLookingUp ? "Looking up book..." : "Fetching eBay price...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Result Card

    private func resultCard(_ book: BookSearchResult) -> some View {
        VStack(spacing: 16) {
            // Book info
            HStack(spacing: 14) {
                if let urlString = book.coverImageURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Theme.well)
                                .overlay { Image(systemName: "book.closed").foregroundStyle(.secondary) }
                        }
                    }
                    .frame(width: 70, height: 105)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(radius: 2)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.well)
                        .frame(width: 70, height: 105)
                        .overlay { Image(systemName: "book.closed").foregroundStyle(.secondary) }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title)
                        .font(Theme.serif(17, weight: .semibold))
                        .lineLimit(3)
                    Text(book.authors)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                    if let isbn = book.isbn13 ?? book.isbn {
                        Text("ISBN: \(isbn)")
                            .font(.caption)
                            .foregroundStyle(Theme.inkTertiary)
                    }
                    if let publisher = book.publisher {
                        Text(publisher)
                            .font(.caption)
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }

                Spacer()
            }

            Divider()

            // eBay price
            if isFetchingPrice {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking eBay prices...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let ebay = ebayResult {
                VStack(spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("eBay Lowest:")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSecondary)
                        Text(ebay.formattedPrice)
                            .font(Theme.display(28))
                            .foregroundStyle(Theme.brass)
                    }

                    if let condition = ebay.condition {
                        Text(condition)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 16) {
                        if let url = ebay.listingURL, let ebayURL = URL(string: url) {
                            Link(destination: ebayURL) {
                                Label("Lowest Listing", systemImage: "arrow.up.right.square")
                                    .font(.subheadline)
                            }
                        }
                        if let url = ebay.searchResultsURL, let searchURL = URL(string: url) {
                            Link(destination: searchURL) {
                                Label("All Listings", systemImage: "list.bullet.rectangle")
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            } else if !APIConfiguration.shared.ebayIsConfigured {
                Label("Configure eBay API in Settings for pricing", systemImage: "gearshape")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No eBay listings found")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Action buttons
            HStack(spacing: 16) {
                Button {
                    addToLibrary(book)
                } label: {
                    Label("Add to Library", systemImage: "plus.circle")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    clearResult()
                    showScanner = true
                } label: {
                    Label("Scan Next", systemImage: "barcode.viewfinder")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.rule.opacity(0.8), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        .padding(.horizontal)
    }

    // MARK: - Recent Checks

    private var recentChecksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionEyebrow(text: "Recent checks")
                Spacer()
                Button("Clear") {
                    withAnimation { recentChecks.removeAll() }
                }
                .font(.caption)
            }
            .padding(.horizontal)

            ForEach(recentChecks) { check in
                HStack(spacing: 10) {
                    if let urlString = check.coverURL, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                Theme.well
                            }
                        }
                        .frame(width: 35, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.well)
                            .frame(width: 35, height: 52)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(check.title)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text(check.authors)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if let price = check.ebayPrice {
                        Text(formatPrice(price))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.ink)
                    } else {
                        Text("—")
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func manualLookup() {
        let title = manualTitle.trimmingCharacters(in: .whitespaces)
        let author = manualAuthor.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty || !author.isEmpty else { return }
        clearResult()
        Task { await lookupByTitleAuthor(title: title, author: author) }
    }

    private func lookupByTitleAuthor(title: String, author: String) async {
        isLookingUp = true
        errorMessage = nil
        bookResult = nil
        ebayResult = nil

        await lookupService.searchByText(
            title: title.isEmpty ? nil : title,
            author: author.isEmpty ? nil : author
        )

        // Show search results if multiple, or use first result
        guard let firstResult = lookupService.searchResults.first else {
            isLookingUp = false
            errorMessage = "No books found. Try adjusting the title or author."
            return
        }

        bookResult = firstResult
        isLookingUp = false

        await fetchPriceAndRecord(for: firstResult)
    }

    private func lookup(code: String) async {
        isLookingUp = true
        errorMessage = nil
        bookResult = nil
        ebayResult = nil

        // Look up book info
        await lookupService.searchByISBN(code)

        guard let firstResult = lookupService.searchResults.first else {
            isLookingUp = false
            errorMessage = "Book not found. Try entering the title and author."
            return
        }

        bookResult = firstResult
        isLookingUp = false

        await fetchPriceAndRecord(for: firstResult)
    }

    private func fetchPriceAndRecord(for result: BookSearchResult) async {
        // Fetch eBay price
        guard APIConfiguration.shared.ebayIsConfigured else { return }

        isFetchingPrice = true
        let priceResult = await lookupService.fetchEbayPrice(
            isbn: result.isbn13 ?? result.isbn,
            title: result.title,
            author: result.authors
        )
        ebayResult = priceResult
        isFetchingPrice = false

        // Add to recent checks
        let check = PriceCheck(
            title: result.title,
            authors: result.authors,
            coverURL: result.coverImageURL,
            ebayPrice: priceResult?.lowestPrice,
            ebayURL: priceResult?.listingURL,
            searchResult: result
        )
        withAnimation {
            recentChecks.insert(check, at: 0)
            if recentChecks.count > 20 { recentChecks.removeLast() }
        }
    }

    private func addToLibrary(_ result: BookSearchResult) {
        if let existing = DuplicateDetector.findDuplicate(in: existingBooks, for: result) {
            duplicateBook = existing
            pendingAddResult = result
            showDuplicateAlert = true
        } else {
            insertBook(from: result)
        }
    }

    private func insertBook(from result: BookSearchResult) {
        Task {
            let book = await lookupService.createBook(from: result)
            if let ebay = ebayResult {
                book.ebayLowestPrice = ebay.lowestPrice
                book.ebayPriceURL = ebay.listingURL
                book.ebayPriceLastUpdated = Date()
            }
            modelContext.insert(book)
        }
    }

    private func clearResult() {
        bookResult = nil
        ebayResult = nil
        errorMessage = nil
        scannedCode = nil
    }

    private func formatPrice(_ price: Double) -> String {
        price.formattedAsPrice()
    }
}
