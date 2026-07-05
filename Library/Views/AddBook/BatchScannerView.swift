import SwiftUI
import SwiftData
import Vision
import VisionKit
import Observation
import os

/// Model tracking a batch of scanned barcodes and their lookup status
@Observable
final class BatchScanModel {
    struct ScannedItem: Identifiable {
        let id = UUID()
        var barcode: String
        var title: String?
        var authors: String?
        var coverURL: String?
        var searchResult: BookSearchResult?
        var state: LookupState = .pending

        enum LookupState {
            case pending
            case searching
            case found
            case notFound
            case error(String)
        }
    }

    var items: [ScannedItem] = []
    var isScanning = true
    private var scannedCodes: Set<String> = []

    var foundCount: Int { items.filter { if case .found = $0.state { return true }; return false }.count }
    var totalCount: Int { items.count }

    /// Returns true if this is a new barcode (not already scanned)
    func addBarcode(_ code: String) -> Bool {
        guard !scannedCodes.contains(code) else { return false }
        scannedCodes.insert(code)
        items.append(ScannedItem(barcode: code))
        return true
    }

    /// Add a manual ISBN entry
    func addManualISBN(_ isbn: String) {
        let cleaned = ISBN.normalize(isbn)
        guard !cleaned.isEmpty else { return }

        // Convert ISBN-10 to ISBN-13
        let code = cleaned.count == 10 ? ISBN.isbn13(fromISBN10: cleaned) : cleaned

        guard !scannedCodes.contains(code) else { return }
        scannedCodes.insert(code)
        items.append(ScannedItem(barcode: code))
    }

    /// Update an existing not-found item with a new ISBN (from OCR or manual entry)
    func updateBarcode(_ id: UUID, newISBN: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let cleaned = ISBN.normalize(newISBN)
        let code = cleaned.count == 10 ? ISBN.isbn13(fromISBN10: cleaned) : cleaned
        // Keep the dedup set in sync with the corrected barcode
        scannedCodes.remove(items[index].barcode)
        scannedCodes.insert(code)
        items[index].barcode = code
        items[index].state = .pending
    }

    func removeItem(_ id: UUID) {
        if let item = items.first(where: { $0.id == id }) {
            scannedCodes.remove(item.barcode)
        }
        items.removeAll { $0.id == id }
    }

    func updateItem(_ id: UUID, result: BookSearchResult) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].searchResult = result
        items[index].title = result.title
        items[index].authors = result.authors
        items[index].coverURL = result.coverImageURL
        items[index].state = .found
    }

    func markSearching(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = .searching
    }

    func markNotFound(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = .notFound
    }

}

// MARK: - Batch Scanner that stays open for multiple scans

struct BatchBarcodeScannerView: UIViewControllerRepresentable {
    var onBarcodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128, .code39])],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        if !uiViewController.isScanning {
            try? uiViewController.startScanning()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: BatchBarcodeScannerView
        private var processedBarcodes: Set<String> = []

        init(parent: BatchBarcodeScannerView) {
            self.parent = parent
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                switch item {
                case .barcode(let barcode):
                    handleBarcode(barcode)
                default:
                    break
                }
            }
        }

        private func handleBarcode(_ barcode: RecognizedItem.Barcode) {
            guard let payload = barcode.payloadStringValue else { return }
            let cleaned = ISBN.normalize(payload)
            guard !processedBarcodes.contains(cleaned),
                  let code = ISBN.lookupCode(fromScannedPayload: payload) else { return }

            processedBarcodes.insert(cleaned)
            DispatchQueue.main.async {
                self.parent.onBarcodeScanned(code)
            }
        }
    }
}

// MARK: - Batch Scanner Sheet

struct BatchScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var existingBooks: [Book]

    @State private var model = BatchScanModel()
    @State private var lookupService = BookLookupService()
    @State private var showReview = false

    // Manual ISBN entry
    @State private var manualISBN = ""
    @State private var showManualEntry = false

    // Snap ISBN (OCR)
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var snapTargetItemId: UUID?  // which item we're snapping for (nil = new item)
    @State private var ocrMissCount = 0

    var body: some View {
        NavigationStack {
            ZStack {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    BatchBarcodeScannerView { code in
                        handleScannedCode(code)
                    }
                    .ignoresSafeArea()

                    VStack {
                        Spacer()
                        scannedItemsOverlay
                    }
                } else {
                    ContentUnavailableView(
                        "Scanner Not Available",
                        systemImage: "barcode.viewfinder",
                        description: Text("Barcode scanning requires a device with a camera.")
                    )
                }
            }
            .navigationTitle("Batch Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done (\(model.foundCount))") {
                        showReview = true
                    }
                    .disabled(model.items.isEmpty)
                }
            }
            .sheet(isPresented: $showReview) {
                BatchReviewSheet(model: model, existingBooks: existingBooks, lookupService: lookupService) {
                    dismiss()
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView(capturedImage: $capturedImage)
                    .ignoresSafeArea()
            }
            .onChange(of: capturedImage) { _, image in
                if let image = image {
                    Task { await processSnapISBN(image) }
                    capturedImage = nil
                }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: model.totalCount)
            .sensoryFeedback(.error, trigger: ocrMissCount)
        }
    }

    private var scannedItemsOverlay: some View {
        VStack(spacing: 0) {
            // Count header + action buttons
            HStack {
                Image(systemName: "barcode.viewfinder")
                Text("\(model.totalCount) scanned")
                    .font(.headline)
                if model.foundCount > 0 {
                    Text("• \(model.foundCount) found")
                        .foregroundStyle(.green)
                }
                Spacer()

                // Snap ISBN from photo
                Button {
                    snapTargetItemId = nil
                    showCamera = true
                } label: {
                    Image(systemName: "camera.viewfinder")
                        .font(.title3)
                }

                // Type ISBN manually
                Button {
                    withAnimation { showManualEntry.toggle() }
                } label: {
                    Image(systemName: "keyboard")
                        .font(.title3)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Manual ISBN entry field
            if showManualEntry {
                HStack(spacing: 8) {
                    TextField("Type ISBN", text: $manualISBN)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .submitLabel(.go)
                        .onSubmit { addManualISBN() }

                    Button {
                        addManualISBN()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .disabled(manualISBN.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            if !model.items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(model.items.reversed()) { item in
                            scannedItemChip(item)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
            }

            Text("Scan barcodes, snap ISBN text, or type manually")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private func scannedItemChip(_ item: BatchScanModel.ScannedItem) -> some View {
        VStack(spacing: 4) {
            switch item.state {
            case .pending, .searching:
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 50, height: 70)
            case .found:
                if let urlString = item.coverURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.green.opacity(0.2))
                                .overlay { Image(systemName: "checkmark").foregroundStyle(.green) }
                        }
                    }
                    .frame(width: 50, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 50, height: 70)
                        .overlay { Image(systemName: "checkmark").foregroundStyle(.green) }
                }
            case .notFound:
                // Tappable — snap ISBN to retry
                Button {
                    snapTargetItemId = item.id
                    showCamera = true
                } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 50, height: 70)
                        .overlay {
                            VStack(spacing: 2) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.caption)
                                Text("Snap")
                                    .font(.system(size: 8))
                            }
                            .foregroundStyle(.orange)
                        }
                }
                .buttonStyle(.plain)
            case .error:
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 50, height: 70)
                    .overlay { Image(systemName: "xmark").foregroundStyle(.red) }
            }

            Text(item.title ?? item.barcode)
                .font(.system(size: 9))
                .lineLimit(1)
                .frame(width: 55)
        }
    }

    // MARK: - Actions

    private func handleScannedCode(_ code: String) {
        guard model.addBarcode(code), let item = model.items.last else { return }
        lookupItem(item.id, code: code)
    }

    private func addManualISBN() {
        let isbn = manualISBN.trimmingCharacters(in: .whitespaces)
        guard !isbn.isEmpty else { return }
        model.addManualISBN(isbn)
        manualISBN = ""

        if let item = model.items.last {
            lookupItem(item.id, code: item.barcode)
        }
    }

    private func processSnapISBN(_ image: UIImage) async {
        let ocrService = OCRService()
        do {
            let lines = try await ocrService.recognizeText(in: image)
            if let isbn = ocrService.extractISBN(from: lines) {
                if let targetId = snapTargetItemId {
                    // Update an existing not-found item
                    model.updateBarcode(targetId, newISBN: isbn)
                    lookupItem(targetId, code: model.items.first(where: { $0.id == targetId })?.barcode ?? isbn)
                } else {
                    // Add as new item
                    model.addManualISBN(isbn)
                    if let item = model.items.last {
                        lookupItem(item.id, code: item.barcode)
                    }
                }
            } else {
                ocrMissCount += 1
            }
        } catch {
            Logger.ocr.error("Batch scan OCR failed: \(error)")
        }
        snapTargetItemId = nil
    }

    private func lookupItem(_ itemId: UUID, code: String) {
        Task {
            model.markSearching(itemId)
            await lookupService.searchByISBN(code)
            if let result = lookupService.searchResults.first {
                model.updateItem(itemId, result: result)
            } else {
                model.markNotFound(itemId)
            }
        }
    }
}

// MARK: - Batch Review Sheet

struct BatchReviewSheet: View {
    let model: BatchScanModel
    let existingBooks: [Book]
    let lookupService: BookLookupService
    let onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItems: Set<UUID> = []

    // Snap ISBN for not-found items during review
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var snapTargetItemId: UUID?
    @State private var ocrMissCount = 0

    private var foundItems: [BatchScanModel.ScannedItem] {
        model.items.filter { if case .found = $0.state { return true }; return false }
    }

    private var notFoundItems: [BatchScanModel.ScannedItem] {
        model.items.filter { if case .found = $0.state { return false }; return true }
    }

    var body: some View {
        NavigationStack {
            List {
                if !foundItems.isEmpty {
                    Section("Found (\(foundItems.count))") {
                        ForEach(foundItems) { item in
                            reviewRow(item)
                        }
                    }
                }

                if !notFoundItems.isEmpty {
                    Section("Not Found (\(notFoundItems.count))") {
                        ForEach(notFoundItems) { item in
                            notFoundRow(item)
                        }
                    }
                }
            }
            .navigationTitle("Review (\(foundItems.count) books)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Selected (\(selectedItems.count))") {
                        addAllBooks()
                    }
                    .disabled(selectedItems.isEmpty)
                }
            }
            .onAppear {
                selectedItems = Set(foundItems.map { $0.id })
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView(capturedImage: $capturedImage)
                    .ignoresSafeArea()
            }
            .onChange(of: capturedImage) { _, image in
                if let image = image {
                    Task { await processSnapISBN(image) }
                    capturedImage = nil
                }
            }
            .sensoryFeedback(.error, trigger: ocrMissCount)
        }
    }

    private func reviewRow(_ item: BatchScanModel.ScannedItem) -> some View {
        HStack(spacing: 12) {
            if let urlString = item.coverURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                    }
                }
                .frame(width: 40, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 40, height: 60)
                    .overlay { Image(systemName: "book.closed").font(.caption).foregroundStyle(.secondary) }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title ?? "Unknown")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(item.authors ?? "Unknown Author")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let result = item.searchResult,
                   DuplicateDetector.findDuplicate(in: existingBooks, for: result) != nil {
                    Text("Already in library")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            Button {
                if selectedItems.contains(item.id) {
                    selectedItems.remove(item.id)
                } else {
                    selectedItems.insert(item.id)
                }
            } label: {
                Image(systemName: selectedItems.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedItems.contains(item.id) ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
    }

    private func notFoundRow(_ item: BatchScanModel.ScannedItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.barcode)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if case .searching = item.state {
                    Text("Searching...")
                        .font(.caption)
                        .foregroundStyle(.blue)
                } else {
                    Text("Not found in book databases")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button {
                snapTargetItemId = item.id
                showCamera = true
            } label: {
                Label("Snap ISBN", systemImage: "camera.viewfinder")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func processSnapISBN(_ image: UIImage) async {
        let ocrService = OCRService()
        do {
            let lines = try await ocrService.recognizeText(in: image)
            if let isbn = ocrService.extractISBN(from: lines) {
                if let targetId = snapTargetItemId {
                    model.updateBarcode(targetId, newISBN: isbn)
                    let code = model.items.first(where: { $0.id == targetId })?.barcode ?? isbn
                    model.markSearching(targetId)
                    await lookupService.searchByISBN(code)
                    if let result = lookupService.searchResults.first {
                        model.updateItem(targetId, result: result)
                        selectedItems.insert(targetId)
                    } else {
                        model.markNotFound(targetId)
                    }
                }
            } else {
                ocrMissCount += 1
            }
        } catch {
            Logger.ocr.error("Batch review OCR failed: \(error)")
        }
        snapTargetItemId = nil
    }

    private func addAllBooks() {
        for item in foundItems where selectedItems.contains(item.id) {
            guard let result = item.searchResult else { continue }

            if let existing = DuplicateDetector.findDuplicate(in: existingBooks, for: result) {
                existing.copyCount += 1
            } else {
                Task {
                    let book = await lookupService.createBook(from: result)
                    modelContext.insert(book)
                }
            }
        }

        dismiss()
        onComplete()
    }
}
