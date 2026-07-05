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
        NavigationStack {
            Group {
                if books.isEmpty {
                    emptyLibraryView
                } else {
                    booksView
                }
            }
            .navigationTitle("My Library")
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

                        Picker("Filter", selection: $filterStatus) {
                            Text("All Books").tag(ReadingStatus?.none)
                            ForEach(ReadingStatus.allCases) { status in
                                Label(status.rawValue, systemImage: status.systemImage)
                                    .tag(ReadingStatus?.some(status))
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
        }
    }

    // MARK: - Books Grid / List

    @ViewBuilder
    private var booksView: some View {
        switch viewMode {
        case .grid:
            ScrollView {
                bookCountHeader
                bookGrid
            }
        case .list:
            List {
                bookCountHeader
                    .listRowSeparator(.hidden)
                ForEach(filteredBooks) { book in
                    NavigationLink(
                        destination: BookDetailView(book: book)
                            .zoomTransitionDestination(id: book.id, in: zoomNamespace)
                    ) {
                        bookListRow(book)
                    }
                }
                .onDelete(perform: deleteBooks)
            }
            .listStyle(.plain)
        }
    }

    private var bookCountHeader: some View {
        HStack {
            Text("\(filteredBooks.count) book\(filteredBooks.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let status = filterStatus {
                Text("• \(status.rawValue)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private var bookGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 110, maximum: 140), spacing: 16)],
            spacing: 20
        ) {
            ForEach(filteredBooks) { book in
                NavigationLink(
                    destination: BookDetailView(book: book)
                        .zoomTransitionDestination(id: book.id, in: zoomNamespace)
                ) {
                    bookGridItem(book)
                }
                .buttonStyle(.plain)
                .zoomTransitionSource(id: book.id, in: zoomNamespace)
                .contextMenu {
                    bookContextMenu(book)
                }
            }
        }
        .padding()
    }

    // MARK: - Grid Item

    private func bookGridItem(_ book: Book) -> some View {
        VStack(spacing: 6) {
            ZStack {
                BookCoverView(book: book, width: 110, height: 165)

                // Copy count badge (top-left)
                if book.copyCount > 1 {
                    VStack {
                        HStack {
                            Text("\(book.copyCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.blue)
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
                                .offset(x: 4, y: 4)
                        }
                    }
                }
            }
            .frame(width: 110, height: 165)

            VStack(spacing: 2) {
                Text(book.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(book.authors)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 110)

            // Star rating
            if let rating = book.rating, rating > 0 {
                HStack(spacing: 1) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 8))
                            .foregroundStyle(star <= rating ? .yellow : .gray.opacity(0.3))
                    }
                }
            }
        }
    }

    // MARK: - List Row

    private func bookListRow(_ book: Book) -> some View {
        HStack(spacing: 12) {
            BookCoverView(book: book, width: 50, height: 75)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(book.authors)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Label(book.readingStatusEnum.rawValue, systemImage: book.readingStatusEnum.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if book.copyCount > 1 {
                        Text("\(book.copyCount) copies")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }

                    if let price = book.ebayLowestPrice {
                        PriceBadgeView(price: price, currency: "USD")
                    }
                }
            }

            Spacer()

            if let rating = book.rating, rating > 0 {
                HStack(spacing: 1) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 10))
                            .foregroundStyle(star <= rating ? .yellow : .gray.opacity(0.3))
                    }
                }
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

    private var emptyLibraryView: some View {
        ContentUnavailableView {
            Label("No Books Yet", systemImage: "books.vertical")
        } description: {
            Text("Tap the + button to add your first book by scanning a barcode, taking a photo, or searching manually.")
        } actions: {
            Button {
                showAddBook = true
            } label: {
                Label("Add a Book", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Delete

    private func deleteBooks(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredBooks[index])
        }
    }
}
