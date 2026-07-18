import SwiftUI
import SwiftData
import Charts

/// Detailed view for a single book showing all info, cover, eBay pricing, and editing
struct BookDetailView: View {
    @Bindable var book: Book
    @Environment(\.modelContext) private var modelContext

    @State private var lookupService = BookLookupService()
    @State private var isFetchingPrice = false
    @State private var priceError: String?
    @State private var showCoverCapture = false
    @State private var newCoverImage: UIImage?
    @State private var showDeleteConfirmation = false
    @State private var showEditSheet = false
    @State private var heroMarble: UIImage?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Cover & title header
                headerSection

                // Reading status
                quickActionsBar

                // eBay price section
                ebayPriceSection

                // Book details
                detailsSection

                // Description
                if let description = book.bookDescription, !description.isEmpty {
                    descriptionSection(description)
                }

                // Personal notes
                notesSection

                Spacer(minLength: 40)
            }
            .padding()
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showEditSheet = true
                    } label: {
                        Label("Edit Details", systemImage: "pencil")
                    }

                    Button {
                        showCoverCapture = true
                    } label: {
                        Label("Change Cover", systemImage: "camera")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Book", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showCoverCapture) {
            CoverImageCaptureSheet(capturedImage: $newCoverImage)
        }
        .sheet(isPresented: $showEditSheet) {
            BookEditSheet(book: book)
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .confirmationDialog("Delete Book", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                modelContext.delete(book)
            }
        } message: {
            Text("Are you sure you want to remove \"\(book.title)\" from your library?")
        }
        .onChange(of: newCoverImage) { _, image in
            if let image = image {
                book.coverImageData = image.jpegData(compressionQuality: 0.8)
            }
        }
        .task {
            // Auto-fetch eBay price if stale (older than 24h) or never fetched
            if shouldRefreshPrice {
                await fetchEbayPrice()
            }
            // Marbled endpaper for books with generated covers
            if book.coverImageData == nil && book.coverImageURL == nil {
                let kind = Marbling.kind(forTitle: book.title) ?? .forest
                heroMarble = await Marbling.image(
                    kind: kind,
                    seed: Marbling.stableSeed(book.title),
                    size: CGSize(width: 420, height: 300)
                )
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 18) {
            BookCoverView(book: book, width: 168, height: 252)
                .padding(.top, 8)

            VStack(spacing: 7) {
                Text(book.title)
                    .font(Theme.display(26))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)

                Text(book.authors)
                    .font(Theme.serif(18, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)

                // Rating
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { star in
                        Button {
                            withAnimation(.snappy(duration: 0.25)) {
                                book.rating = (book.rating == star) ? nil : star
                            }
                        } label: {
                            Image(systemName: star <= (book.rating ?? 0) ? "star.fill" : "star")
                                .foregroundStyle(star <= (book.rating ?? 0) ? Theme.brass : Theme.inkTertiary.opacity(0.5))
                                .font(.title3)
                                .symbolEffect(.bounce, value: book.rating ?? 0)
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 12)
        .background {
            ZStack {
                if let data = book.coverImageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 70, opaque: true)
                        .opacity(0.30)
                } else if let heroMarble {
                    // Marbled endpaper behind books with generated covers
                    Image(uiImage: heroMarble)
                        .resizable()
                        .scaledToFill()
                        .opacity(0.22)
                }
                LinearGradient(
                    colors: [Theme.card.opacity(0.4), Theme.card],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.rule.opacity(0.8), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
    }

    // MARK: - Reading Status

    private var quickActionsBar: some View {
        HStack(spacing: 10) {
            ForEach(ReadingStatus.allCases) { status in
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        book.readingStatusEnum = status
                        if status == .reading && book.dateStartedReading == nil {
                            book.dateStartedReading = Date()
                        }
                        if status == .read {
                            book.dateFinishedReading = Date()
                        }
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: status.systemImage)
                            .font(.body.weight(.semibold))
                            .symbolEffect(.bounce, value: book.readingStatusEnum == status)
                        Text(status.rawValue)
                            .font(.caption2.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        book.readingStatusEnum == status
                        ? Theme.green
                        : Theme.well
                    )
                    .foregroundStyle(book.readingStatusEnum == status ? Theme.card : Theme.inkSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                book.readingStatusEnum == status ? .clear : Theme.rule,
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - eBay Price Section

    private var ebayPriceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionEyebrow(text: "Valuation")

                Spacer()

                Button {
                    Task { await fetchEbayPrice() }
                } label: {
                    if isFetchingPrice {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.medium))
                    }
                }
                .tint(Theme.green)
                .disabled(isFetchingPrice)
            }

            if let price = book.ebayLowestPrice {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(formatPrice(price))
                        .font(Theme.display(38))
                        .foregroundStyle(Theme.brass)
                        .contentTransition(.numericText())

                    Text("lowest on eBay")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)

                    if let change = book.recentPriceChange {
                        PriceDeltaBadge(change: change, perspective: .owning)
                    }
                }

                if let lastUpdated = book.ebayPriceLastUpdated {
                    Text("Appraised \(lastUpdated.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(Theme.inkTertiary)
                }

                HStack(spacing: 16) {
                    if let url = book.ebayPriceURL, let ebayURL = URL(string: url) {
                        Link(destination: ebayURL) {
                            Label("Lowest Listing", systemImage: "arrow.up.right.square")
                                .font(.subheadline)
                        }
                    }
                    if let url = ebaySearchURL, let searchURL = URL(string: url) {
                        Link(destination: searchURL) {
                            Label("All Listings", systemImage: "list.bullet.rectangle")
                                .font(.subheadline)
                        }
                    }
                }
                .tint(Theme.green)
            } else if let error = priceError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.brass)
            } else if !isFetchingPrice {
                Text("No appraisal yet — refresh to check eBay.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
            }

            // Price history chart
            if !book.priceHistory.isEmpty {
                Rectangle()
                    .fill(Theme.rule)
                    .frame(height: 1)

                DisclosureGroup {
                    PriceHistoryChartView(entries: book.priceHistory)
                        .padding(.top, 6)
                } label: {
                    Text("Price history")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.inkSecondary)
            }
        }
        .cardStyle()
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionEyebrow(text: "Details")

            LazyVGrid(columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading)
            ], alignment: .leading, spacing: 14) {
                if let isbn = book.isbn13 ?? book.isbn {
                    detailItem(label: "ISBN", value: isbn)
                }
                if let publisher = book.publisher {
                    detailItem(label: "Publisher", value: publisher)
                }
                if let date = book.publishedDate {
                    detailItem(label: "Published", value: date)
                }
                if let pages = book.pageCount {
                    detailItem(label: "Pages", value: "\(pages)")
                }
                if let categories = book.categories {
                    detailItem(label: "Categories", value: categories)
                }
                if let language = book.language {
                    detailItem(label: "Language", value: language.uppercased())
                }

                detailItem(label: "Added", value: book.dateAdded.formatted(date: .abbreviated, time: .omitted))

                if let start = book.dateStartedReading {
                    detailItem(label: "Started", value: start.formatted(date: .abbreviated, time: .omitted))
                }
                if let end = book.dateFinishedReading {
                    detailItem(label: "Finished", value: end.formatted(date: .abbreviated, time: .omitted))
                }
                if let start = book.dateStartedReading, let end = book.dateFinishedReading {
                    let days = max(1, Calendar.current.dateComponents([.day], from: start, to: end).day ?? 1)
                    detailItem(label: "Reading Time", value: days == 1 ? "1 day" : "\(days) days")
                }

                if book.copyCount > 1 {
                    detailItem(label: "Copies", value: "\(book.copyCount)")
                }
            }
        }
        .cardStyle()
    }

    private func detailItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.inkTertiary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
        }
    }

    // MARK: - Description

    private func descriptionSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "About this book")
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .lineSpacing(4)
        }
        .cardStyle()
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Marginalia")

            TextEditor(text: Binding(
                get: { book.personalNotes ?? "" },
                set: { book.personalNotes = $0.isEmpty ? nil : $0 }
            ))
            .frame(minHeight: 88)
            .padding(10)
            .background(Theme.well)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.rule, lineWidth: 1)
            }
        }
        .cardStyle()
    }

    // MARK: - Helpers

    /// Build an eBay web search URL from the book's title + author (or ISBN if available)
    private var ebaySearchURL: String? {
        let query: String
        if let isbn = book.isbn13 ?? book.isbn, !isbn.isEmpty {
            query = isbn
        } else {
            query = "\(book.title) \(book.authors)"
        }
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return "https://www.ebay.com/sch/i.html?_nkw=\(encoded)"
    }

    private var shouldRefreshPrice: Bool {
        guard APIConfiguration.shared.ebayIsConfigured else { return false }
        guard let lastUpdated = book.ebayPriceLastUpdated else { return true }
        return Date().timeIntervalSince(lastUpdated) > 86400 // 24 hours
    }

    private func fetchEbayPrice() async {
        isFetchingPrice = true
        priceError = nil

        if let result = await lookupService.fetchEbayPrice(for: book) {
            withAnimation {
                book.ebayLowestPrice = result.lowestPrice
                book.ebayPriceURL = result.listingURL
                book.ebayPriceLastUpdated = Date()
            }

            // Record price history
            let entry = PriceHistoryEntry(price: result.lowestPrice, currency: result.currency)
            book.priceHistory.append(entry)
        } else {
            priceError = APIConfiguration.shared.ebayIsConfigured
                ? "No listings found"
                : "Configure eBay API keys in Settings"
        }

        isFetchingPrice = false
    }

    private func formatPrice(_ price: Double) -> String {
        price.formattedAsPrice()
    }
}

// MARK: - Edit Sheet

struct BookEditSheet: View {
    @Bindable var book: Book
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Info") {
                    TextField("Title", text: $book.title)
                    TextField("Authors", text: $book.authors)
                    TextField("ISBN", text: Binding(
                        get: { book.isbn ?? "" },
                        set: { book.isbn = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("ISBN-13", text: Binding(
                        get: { book.isbn13 ?? "" },
                        set: { book.isbn13 = $0.isEmpty ? nil : $0 }
                    ))
                }

                Section("Details") {
                    TextField("Publisher", text: Binding(
                        get: { book.publisher ?? "" },
                        set: { book.publisher = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Published Date", text: Binding(
                        get: { book.publishedDate ?? "" },
                        set: { book.publishedDate = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Page Count", value: Binding(
                        get: { book.pageCount },
                        set: { book.pageCount = $0 }
                    ), format: .number)
                    TextField("Categories", text: Binding(
                        get: { book.categories ?? "" },
                        set: { book.categories = $0.isEmpty ? nil : $0 }
                    ))
                }

                Section("Reading Dates") {
                    Toggle("Started Reading", isOn: Binding(
                        get: { book.dateStartedReading != nil },
                        set: { if !$0 { book.dateStartedReading = nil } else { book.dateStartedReading = Date() } }
                    ))
                    if book.dateStartedReading != nil {
                        DatePicker("Start Date", selection: Binding(
                            get: { book.dateStartedReading ?? Date() },
                            set: { book.dateStartedReading = $0 }
                        ), displayedComponents: .date)
                    }

                    Toggle("Finished Reading", isOn: Binding(
                        get: { book.dateFinishedReading != nil },
                        set: { if !$0 { book.dateFinishedReading = nil } else { book.dateFinishedReading = Date() } }
                    ))
                    if book.dateFinishedReading != nil {
                        DatePicker("Finish Date", selection: Binding(
                            get: { book.dateFinishedReading ?? Date() },
                            set: { book.dateFinishedReading = $0 }
                        ), displayedComponents: .date)
                    }
                }

                Section("Copies") {
                    Stepper("Copies: \(book.copyCount)", value: $book.copyCount, in: 1...99)
                }

                Section("Description") {
                    TextEditor(text: Binding(
                        get: { book.bookDescription ?? "" },
                        set: { book.bookDescription = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(minHeight: 80)
                }
            }
            .navigationTitle("Edit Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
