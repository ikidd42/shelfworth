import SwiftUI
import SwiftData

/// Main library view showing all books in a visual grid with covers
struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]

    @State private var searchText = ""
    @State private var filterStatus: ReadingStatus?
    @State private var sortOption: SortOption = .dateAdded
    @State private var showAddBook = false
    @State private var showSettings = false
    @State private var viewMode: ViewMode = .grid
    @State private var searchScope: SearchScope = .all
    @State private var navigationPath = NavigationPath()
    @Namespace private var zoomNamespace

    enum ViewMode: String, CaseIterable {
        case grid = "square.grid.2x2"
        case list = "list.bullet"
    }

    enum SortOption: String, CaseIterable {
        case dateAdded = "Date Added"
        case title = "Title"
        case author = "Author"
        case rating = "Rating"
    }

    enum SearchScope: String, CaseIterable {
        case all = "All"
        case title = "Title"
        case author = "Author"
        case isbn = "ISBN"
    }

    var filteredBooks: [Book] {
        var result = books

        // Filter by search
        if !searchText.isEmpty {
            result = result.filter { book in
                switch searchScope {
                case .all:
                    book.title.localizedCaseInsensitiveContains(searchText) ||
                    book.authors.localizedCaseInsensitiveContains(searchText) ||
                    (book.isbn ?? "").contains(searchText) ||
                    (book.isbn13 ?? "").contains(searchText)
                case .title:
                    book.title.localizedCaseInsensitiveContains(searchText)
                case .author:
                    book.authors.localizedCaseInsensitiveContains(searchText)
                case .isbn:
                    (book.isbn ?? "").contains(searchText) ||
                    (book.isbn13 ?? "").contains(searchText)
                }
            }
        }

        // Filter by reading status
        if let status = filterStatus {
            result = result.filter { $0.readingStatusEnum == status }
        }

        // Sort
        switch sortOption {
        case .dateAdded:
            result.sort { $0.dateAdded > $1.dateAdded }
        case .title:
            result.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .author:
            result.sort { $0.authors.localizedCompare($1.authors) == .orderedAscending }
        case .rating:
            result.sort { ($0.rating ?? 0) > ($1.rating ?? 0) }
        }

        return result
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if books.isEmpty {
                    emptyLibraryView
                } else {
                    booksView
                }
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("My Library")
            .navigationDestination(for: Book.self) { book in
                BookDetailView(book: book)
            }
            .searchable(text: $searchText, prompt: "Search books...")
            .searchScopes($searchScope) {
                ForEach(SearchScope.allCases, id: \.self) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddBook = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }

                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Picker("View", selection: $viewMode.animation()) {
                            Label("Grid", systemImage: "square.grid.2x2").tag(ViewMode.grid)
                            Label("List", systemImage: "list.bullet").tag(ViewMode.list)
                        }

                        Picker("Sort by", selection: $sortOption) {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showAddBook) {
                AddBookView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .task {
                // DEBUG launch args for simulator screenshots:
                // `-openFirstBook YES` pushes the first book's detail page;
                // `-openBook <title prefix>` pushes a specific book.
                #if DEBUG
                guard navigationPath.isEmpty else { return }
                if let prefix = UserDefaults.standard.string(forKey: "openBook"),
                   let match = books.first(where: { $0.title.hasPrefix(prefix) }) {
                    navigationPath.append(match)
                } else if UserDefaults.standard.bool(forKey: "openFirstBook"),
                          let first = books.first {
                    navigationPath.append(first)
                }
                #endif
            }
        }
    }

    // MARK: - Books Grid / List

    @ViewBuilder
    private var booksView: some View {
        switch viewMode {
        case .grid:
            ScrollView {
                statusFilterRow
                    .padding(.top, 4)
                bookCountHeader
                bookGrid
            }
        case .list:
            List {
                Section {
                    statusFilterRow
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(filteredBooks) { book in
                        NavigationLink(
                            destination: BookDetailView(book: book)
                                .zoomTransitionDestination(id: book.id, in: zoomNamespace)
                        ) {
                            bookListRow(book)
                        }
                        .listRowBackground(Theme.card)
                    }
                    .onDelete(perform: deleteBooks)
                } header: {
                    bookCountHeader
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Status Filter Chips

    private var statusFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", systemImage: nil, isSelected: filterStatus == nil) {
                    filterStatus = nil
                }
                ForEach(ReadingStatus.allCases) { status in
                    FilterChip(
                        title: status.rawValue,
                        systemImage: status.systemImage,
                        isSelected: filterStatus == status
                    ) {
                        filterStatus = (filterStatus == status) ? nil : status
                    }
                }
            }
            .padding(.horizontal)
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }

    private var bookCountHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(filteredBooks.count) volume\(filteredBooks.count == 1 ? "" : "s")")
                .font(Theme.serif(15, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)

            if let status = filterStatus {
                Text("· \(status.rawValue)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkTertiary)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 6)
    }

    private var bookGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 110, maximum: 140), spacing: 16)],
            spacing: 24
        ) {
            ForEach(filteredBooks) { book in
                NavigationLink(
                    destination: BookDetailView(book: book)
                        .zoomTransitionDestination(id: book.id, in: zoomNamespace)
                ) {
                    bookGridItem(book)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    bookContextMenu(book)
                }
                .zoomTransitionSource(id: book.id, in: zoomNamespace)
            }
        }
        .padding()
        .padding(.bottom, 8)
    }

    // MARK: - Grid Item

    private func bookGridItem(_ book: Book) -> some View {
        VStack(spacing: 8) {
            ZStack {
                BookCoverView(book: book, width: 110, height: 165)

                // Copy count badge (top-left)
                if book.copyCount > 1 {
                    VStack {
                        HStack {
                            Text("×\(book.copyCount)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.card)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.ink.opacity(0.85))
                                .clipShape(Capsule())
                                .offset(x: -4, y: -4)
                            Spacer()
                        }
                        Spacer()
                    }
                }

                // eBay price badge (bottom-right)
                if let price = book.ebayLowestPrice {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            PriceBadgeView(price: price, currency: "USD")
                                .offset(x: 5, y: 5)
                        }
                    }
                }
            }
            .frame(width: 110, height: 165)

            VStack(spacing: 2) {
                Text(book.title)
                    .font(Theme.serif(13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(book.authors)
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)

                // Star rating
                if let rating = book.rating, rating > 0 {
                    StarRatingView(rating: rating, size: 8)
                        .padding(.top, 1)
                }
            }
            .frame(width: 118)
        }
    }

    // MARK: - List Row

    private func bookListRow(_ book: Book) -> some View {
        HStack(spacing: 12) {
            BookCoverView(book: book, width: 46, height: 69)
                .zoomTransitionSource(id: book.id, in: zoomNamespace)

            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(Theme.serif(16, weight: .semibold))
                    .lineLimit(2)

                Text(book.authors)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label(book.readingStatusEnum.rawValue, systemImage: book.readingStatusEnum.systemImage)
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)

                    if book.copyCount > 1 {
                        Text("\(book.copyCount) copies")
                            .font(.caption)
                            .foregroundStyle(Theme.brass)
                    }

                    if let price = book.ebayLowestPrice {
                        PriceBadgeView(price: price, currency: "USD")
                    }
                }
            }

            Spacer()

            if let rating = book.rating, rating > 0 {
                StarRatingView(rating: rating, size: 10)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func bookContextMenu(_ book: Book) -> some View {
        Section {
            ForEach(ReadingStatus.allCases) { status in
                Button {
                    book.readingStatusEnum = status
                } label: {
                    Label(status.rawValue, systemImage: status.systemImage)
                }
            }
        }

        Section {
            Button(role: .destructive) {
                withAnimation {
                    modelContext.delete(book)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Empty State

    @State private var emptyMarble: UIImage?
    @Environment(\.colorScheme) private var colorScheme

    private var emptyLibraryView: some View {
        VStack(spacing: 20) {
            Spacer()

            // Stacked book spines motif — cloth with one marbled half-leather
            HStack(alignment: .bottom, spacing: 5) {
                spine(color: 0x7A3B2E, height: 64)
                marbledSpine(height: 80)
                spine(color: 0x3D5A44, height: 72)
                spine(color: 0xA97B2F, height: 58)
            }
            .padding(.bottom, 4)
            .task {
                emptyMarble = await Marbling.image(
                    kind: .indigo,
                    pattern: .nonpareil,
                    seed: Marbling.stableSeed("library-empty-state"),
                    size: CGSize(width: 22, height: 80)
                )
            }

            Text("Your shelves are empty")
                .font(Theme.display(26))

            Text("Scan a barcode, photograph a title page,\nor search to add your first book.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)

            Button {
                showAddBook = true
            } label: {
                Label("Add a Book", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.green)
            .padding(.top, 6)

            Spacer()
            Spacer()
        }
        .padding()
    }

    private func spine(color: UInt32, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color(UIColor(hex: color)))
            .frame(width: 22, height: height)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }

    private func marbledSpine(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color(UIColor(hex: 0x2B190E)))
            .frame(width: 22, height: height)
            .overlay {
                if let emptyMarble {
                    Image(uiImage: emptyMarble)
                        .resizable()
                        .scaledToFill()
                        .overlay {
                            if colorScheme == .dark {
                                CoverPalette.lamplightScrim.opacity(0.34)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }
            .overlay {
                // Gilt bands across the marbled spine
                VStack {
                    Rectangle().fill(CoverPalette.giltColor.opacity(0.9)).frame(height: 1.5)
                        .padding(.top, height * 0.14)
                    Spacer()
                    Rectangle().fill(CoverPalette.giltColor.opacity(0.9)).frame(height: 1.5)
                        .padding(.bottom, height * 0.14)
                }
            }
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }

    // MARK: - Delete

    private func deleteBooks(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredBooks[index])
        }
    }
}
