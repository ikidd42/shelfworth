import SwiftUI
import SwiftData

/// Main "Add a Book" flow with multiple entry methods:
/// barcode scan, title page OCR, manual search, or manual entry
struct AddBookView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingBooks: [Book]

    @State private var lookupService = BookLookupService()
    @State private var selectedTab: AddMethod = .scan
    @State private var showSearchResults = false

    // Duplicate detection
    @State private var duplicateBook: Book?
    @State private var pendingBook: Book?
    @State private var showDuplicateAlert = false

    // Scan state
    @State private var showBarcodeScanner = false
    @State private var showBatchScanner = false
    @State private var scannedISBN: String?

    // OCR state
    @State private var showCamera = false
    @State private var capturedTitlePage: UIImage?
    @State private var ocrResult: TitlePageInfo?
    @State private var isProcessingOCR = false
    @State private var editableOCRTitle = ""
    @State private var editableOCRAuthor = ""

    // Manual search state
    @State private var searchTitle = ""
    @State private var searchAuthor = ""
    @State private var searchISBN = ""

    enum AddMethod: String, CaseIterable {
        case scan = "Scan"
        case photo = "Photo"
        case search = "Search"
        case manual = "Manual"

        var icon: String {
            switch self {
            case .scan: return "barcode.viewfinder"
            case .photo: return "camera"
            case .search: return "magnifyingglass"
            case .manual: return "square.and.pencil"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Method picker
                Picker("Add Method", selection: $selectedTab) {
                    ForEach(AddMethod.allCases, id: \.self) { method in
                        Label(method.rawValue, systemImage: method.icon)
                            .tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                // Content based on selected method
                ScrollView {
                    switch selectedTab {
                    case .scan:
                        scanView
                    case .photo:
                        photoOCRView
                    case .search:
                        manualSearchView
                    case .manual:
                        ManualEntryView()
                    }
                }
            }
            .navigationTitle("Add a Book")
            .navigationBarTitleDisplayMode(.inline)
            .background(Theme.canvas.ignoresSafeArea())
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .sheet(isPresented: $showBarcodeScanner) {
                BarcodeScannerSheet(scannedISBN: $scannedISBN)
            }
            .fullScreenCover(isPresented: $showBatchScanner) {
                BatchScannerSheet()
            }
            .sheet(isPresented: $showSearchResults) {
                SearchResultsSheet(
                    lookupService: lookupService,
                    onBookSelected: { book in
                        addBookToLibrary(book)
                    }
                )
            }
            .onChange(of: scannedISBN) { _, isbn in
                if let isbn = isbn {
                    Task { await handleScannedISBN(isbn) }
                }
            }
            .sensoryFeedback(.success, trigger: scannedISBN) { _, new in new != nil }
            .alert("Duplicate Book", isPresented: $showDuplicateAlert) {
                Button("Add Copy") {
                    if let existing = duplicateBook {
                        existing.copyCount += 1
                    }
                    pendingBook = nil
                    duplicateBook = nil
                    dismiss()
                }
                Button("Add Anyway") {
                    if let book = pendingBook {
                        modelContext.insert(book)
                    }
                    pendingBook = nil
                    duplicateBook = nil
                    dismiss()
                }
                Button("Cancel", role: .cancel) {
                    pendingBook = nil
                    duplicateBook = nil
                }
            } message: {
                if let existing = duplicateBook {
                    Text("\"\(existing.title)\" is already in your library\(existing.copyCount > 1 ? " (\(existing.copyCount) copies)" : ""). Add another copy or add as a separate entry?")
                }
            }
        }
    }

    // MARK: - Barcode Scan View

    private var scanView: some View {
        VStack(spacing: 24) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 80))
                .foregroundStyle(Theme.green)
                .padding(.top, 40)

            Text("Scan an ISBN Barcode")
                .font(Theme.display(24))

            Text("Point your camera at the barcode on the back of a book to automatically look it up.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                scannedISBN = nil
                showBarcodeScanner = true
            } label: {
                Label("Scan One Book", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)

            Button {
                showBatchScanner = true
            } label: {
                Label("Batch Scan", systemImage: "square.stack.3d.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.horizontal, 40)

            if lookupService.isSearching {
                ProgressView("Looking up book...")
                    .padding()
            }

            if let error = lookupService.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.loss)
                    .font(.caption)
            }

            Spacer()
        }
    }

    // MARK: - Photo OCR View

    private var photoOCRView: some View {
        VStack(spacing: 24) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 80))
                .foregroundStyle(Theme.brass)
                .padding(.top, 40)

            Text("Snap the Title Page")
                .font(Theme.display(24))

            Text("Take a photo of the book's title page and we'll extract the title and author to search for it.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                capturedTitlePage = nil
                ocrResult = nil
                showCamera = true
            } label: {
                Label("Take Photo", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.brass)
            .controlSize(.large)
            .padding(.horizontal, 40)

            if isProcessingOCR {
                ProgressView("Reading text from image...")
                    .padding()
            }

            if let result = ocrResult {
                ocrResultCard(result)
            }

            if lookupService.isSearching {
                ProgressView("Searching for book...")
                    .padding()
            }

            if let error = lookupService.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.loss)
                    .font(.caption)
            }

            Spacer()
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView(capturedImage: $capturedTitlePage)
                .ignoresSafeArea()
        }
        .onChange(of: capturedTitlePage) { _, image in
            if let image = image {
                Task { await processOCRImage(image) }
            }
        }
    }

    private func ocrResultCard(_ result: TitlePageInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Extracted Text", systemImage: "text.magnifyingglass")
                .font(.headline)

            Text("Edit if needed before searching:")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Title", text: $editableOCRTitle)
                .textFieldStyle(.roundedBorder)

            TextField("Author", text: $editableOCRAuthor)
                .textFieldStyle(.roundedBorder)

            // Show raw OCR text for reference
            DisclosureGroup("Raw OCR text") {
                Text(result.rawText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption)

            Button {
                Task { await searchFromOCR(result) }
            } label: {
                Label("Search for This Book", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(editableOCRTitle.isEmpty && editableOCRAuthor.isEmpty)
        }
        .padding()
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Manual Search View

    private var manualSearchView: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Search by Title, Author, or ISBN")
                    .font(.headline)

                TextField("Title", text: $searchTitle)
                    .textFieldStyle(.roundedBorder)

                TextField("Author", text: $searchAuthor)
                    .textFieldStyle(.roundedBorder)

                TextField("ISBN (optional)", text: $searchISBN)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
            }
            .padding()

            Button {
                Task { await performManualSearch() }
            } label: {
                Label("Search", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
            .disabled(searchTitle.isEmpty && searchAuthor.isEmpty && searchISBN.isEmpty)

            if lookupService.isSearching {
                ProgressView("Searching...")
                    .padding()
            }

            if let error = lookupService.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.loss)
                    .font(.caption)
            }

            Spacer()
        }
        .padding(.top)
    }

    // MARK: - Actions

    private func handleScannedISBN(_ isbn: String) async {
        await lookupService.searchByISBN(isbn)
        if !lookupService.searchResults.isEmpty {
            showSearchResults = true
        } else {
            // If barcode didn't find anything, it's probably a UPC code.
            // Pre-fill the manual search tab so the user can enter the ISBN printed on the book.
            lookupService.errorMessage = "Barcode not recognized as an ISBN. Check the book for a printed ISBN number and try the Search tab."
            searchISBN = ""
            selectedTab = .search
        }
    }

    private func processOCRImage(_ image: UIImage) async {
        isProcessingOCR = true
        let ocrService = OCRService()

        do {
            // Use metadata-aware recognition for better parsing
            let richLines = try await ocrService.recognizeTextWithMetadata(in: image)
            let plainLines = richLines.map { $0.text }

            // Check for ISBN first — if found, skip parsing and search directly
            if let isbn = ocrService.extractISBN(from: plainLines) {
                ocrResult = TitlePageInfo(title: "ISBN: \(isbn)", author: nil, rawText: plainLines.joined(separator: "\n"), searchQueries: [isbn])
                editableOCRTitle = ""
                editableOCRAuthor = ""
                isProcessingOCR = false
                await lookupService.searchByISBN(isbn)
                if !lookupService.searchResults.isEmpty {
                    showSearchResults = true
                }
                return
            }

            // Smart parse using text size and position
            let parsed = ocrService.parseTitlePageSmart(lines: richLines)
            ocrResult = parsed
            editableOCRTitle = parsed.title ?? ""
            editableOCRAuthor = parsed.author ?? ""
            isProcessingOCR = false
        } catch {
            isProcessingOCR = false
            lookupService.errorMessage = "OCR failed: \(error.localizedDescription)"
        }
    }

    private func searchFromOCR(_ result: TitlePageInfo) async {
        // First try the user-edited fields (they may have corrected OCR errors)
        let userTitle = editableOCRTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let userAuthor = editableOCRAuthor.trimmingCharacters(in: .whitespacesAndNewlines)

        if !userTitle.isEmpty || !userAuthor.isEmpty {
            await lookupService.searchByText(
                title: userTitle.isEmpty ? nil : userTitle,
                author: userAuthor.isEmpty ? nil : userAuthor
            )
            if !lookupService.searchResults.isEmpty {
                showSearchResults = true
                return
            }
        }

        // If user-edited fields didn't work, try each pre-built query
        for query in result.searchQueries {
            await lookupService.searchFreeText(query)
            if !lookupService.searchResults.isEmpty {
                showSearchResults = true
                return
            }
        }

        // Nothing worked
        lookupService.errorMessage = "No books found. Try editing the title/author and searching again."
    }

    private func performManualSearch() async {
        if !searchISBN.isEmpty {
            await lookupService.searchByISBN(searchISBN)
        } else {
            await lookupService.searchByText(
                title: searchTitle.isEmpty ? nil : searchTitle,
                author: searchAuthor.isEmpty ? nil : searchAuthor
            )
        }
        if !lookupService.searchResults.isEmpty {
            showSearchResults = true
        }
    }

    private func addBookToLibrary(_ book: Book) {
        // Check for duplicates before adding
        if let existing = DuplicateDetector.findDuplicate(
            in: existingBooks,
            title: book.title,
            authors: book.authors,
            isbn: book.isbn,
            isbn13: book.isbn13
        ) {
            duplicateBook = existing
            pendingBook = book
            showDuplicateAlert = true
        } else {
            modelContext.insert(book)
            dismiss()
        }
    }
}
