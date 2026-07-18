import SwiftUI
import SwiftData

/// Export/backup view for saving the library as CSV or JSON
struct ExportView: View {
    @Query(sort: \Book.title) private var books: [Book]
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFormat: ExportService.ExportFormat = .csv
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Format") {
                    Picker("Export Format", selection: $selectedFormat) {
                        ForEach(ExportService.ExportFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Library Summary") {
                    summaryRow(label: "Total books", value: "\(books.count)")
                    summaryRow(label: "With ISBN", value: "\(books.filter { $0.isbn13 != nil || $0.isbn != nil }.count)")
                    summaryRow(label: "With eBay prices", value: "\(books.filter { $0.ebayLowestPrice != nil }.count)")
                    summaryRow(label: "With ratings", value: "\(books.filter { ($0.rating ?? 0) > 0 }.count)")
                    summaryRow(label: "With notes", value: "\(books.filter { $0.personalNotes != nil }.count)")
                }

                Section("What's Included") {
                    Label("Book metadata (title, author, ISBN, publisher)", systemImage: "book.closed")
                        .font(.caption)
                    Label("Reading status and dates", systemImage: "bookmark")
                        .font(.caption)
                    Label("Ratings and personal notes", systemImage: "star")
                        .font(.caption)
                    Label("eBay pricing data", systemImage: "tag")
                        .font(.caption)
                    Label("Copy counts", systemImage: "doc.on.doc")
                        .font(.caption)
                    if selectedFormat == .json {
                        Label("Price history", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.caption)
                    }
                }

                Section {
                    if selectedFormat == .csv {
                        Text("CSV format works with Excel, Google Sheets, and Numbers. Great for viewing and editing your data in a spreadsheet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("JSON format preserves all data including price history. Best for full backups and importing into other apps.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Preview") {
                    previewSection
                }
            }
            .navigationTitle("Export Library")
            .scrollContentBackground(.hidden)
            .background(Theme.canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        exportLibrary()
                    } label: {
                        if isExporting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    }
                    .disabled(books.isEmpty || isExporting)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var previewSection: some View {
        Group {
            if books.isEmpty {
                Text("No books to export")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let preview = ExportService.export(
                    books: Array(books.prefix(3)),
                    format: selectedFormat
                )
                Text(String(preview.prefix(500)) + (preview.count > 500 ? "\n..." : ""))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(12)
            }
        }
    }

    private func exportLibrary() {
        isExporting = true

        // SwiftData models aren't thread-safe, so serialize on the main actor.
        // Export is string building over a few hundred rows — fast enough here.
        let url = ExportService.exportToFile(books: books, format: selectedFormat)
        isExporting = false
        if let url = url {
            exportURL = url
            showShareSheet = true
        }
    }
}

// MARK: - UIKit Share Sheet Wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
