import SwiftUI
import SwiftData

/// App settings — primarily API key configuration
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var config = APIConfiguration.shared
    @Query private var books: [Book]

    @State private var showClearConfirmation = false
    @State private var showExport = false

    // Google Books test state
    @State private var isTestingGoogle = false
    @State private var googleTestResult: TestResult?

    // eBay test state
    @State private var isTestingEbay = false
    @State private var ebayTestResult: TestResult?

    enum TestResult {
        case success(String)
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Library stats
                Section("Library") {
                    HStack {
                        Text("Total Books")
                        Spacer()
                        Text("\(books.count)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("With Covers")
                        Spacer()
                        Text("\(books.filter { $0.coverImageData != nil || $0.coverImageURL != nil }.count)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("With eBay Prices")
                        Spacer()
                        Text("\(books.filter { $0.ebayLowestPrice != nil }.count)")
                            .foregroundStyle(.secondary)
                    }
                }

                // Google Books API
                Section {
                    SecureField("API Key (optional)", text: Binding(
                        get: { config.googleBooksAPIKey },
                        set: { config.googleBooksAPIKey = $0 }
                    ))

                    Button {
                        Task { await testGoogleBooks() }
                    } label: {
                        HStack {
                            if isTestingGoogle {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Testing...")
                            } else {
                                Label("Test Connection", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                    }
                    .disabled(isTestingGoogle)

                    if let result = googleTestResult {
                        testResultRow(result)
                    }
                } header: {
                    Text("Google Books API")
                } footer: {
                    Text("Optional — Google Books works without a key but with lower rate limits. Get a key at console.cloud.google.com")
                }

                // eBay API
                Section {
                    SecureField("Client ID (App ID)", text: Binding(
                        get: { config.ebayClientID },
                        set: { config.ebayClientID = $0 }
                    ))

                    SecureField("Client Secret", text: Binding(
                        get: { config.ebayClientSecret },
                        set: { config.ebayClientSecret = $0 }
                    ))

                    SecureField("App Token (if using direct token)", text: Binding(
                        get: { config.ebayAppToken },
                        set: { config.ebayAppToken = $0 }
                    ))

                    Toggle("Use Sandbox", isOn: Binding(
                        get: { config.ebayUseSandbox },
                        set: { config.ebayUseSandbox = $0 }
                    ))

                    Button {
                        Task { await testEbay() }
                    } label: {
                        HStack {
                            if isTestingEbay {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Testing...")
                            } else {
                                Label("Test Connection", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                    }
                    .disabled(isTestingEbay || !config.ebayIsConfigured)

                    if let result = ebayTestResult {
                        testResultRow(result)
                    }
                } header: {
                    Text("eBay API")
                } footer: {
                    Text("Required for pricing data. Get credentials at developer.ebay.com. You can use either Client ID + Secret (recommended) or a direct App Token.")
                }

                // Data management
                Section {
                    Button {
                        showExport = true
                    } label: {
                        Label("Export Library", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Label("Clear All Books", systemImage: "trash")
                    }
                } header: {
                    Text("Data")
                }

                // About
                Section("About") {
                    HStack {
                        Text("App")
                        Spacer()
                        Text("Shelfworth v1.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("APIs Used")
                        Spacer()
                        Text("Google Books, Open Library, eBay")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Settings")
            .scrollContentBackground(.hidden)
            .background(Theme.canvas.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .sheet(isPresented: $showExport) {
                ExportView()
            }
            .confirmationDialog("Clear Library", isPresented: $showClearConfirmation) {
                Button("Delete All Books", role: .destructive) {
                    for book in books {
                        modelContext.delete(book)
                    }
                }
            } message: {
                Text("This will permanently remove all \(books.count) books from your library. This cannot be undone.")
            }
        }
    }

    // MARK: - Test Result Row

    @ViewBuilder
    private func testResultRow(_ result: TestResult) -> some View {
        switch result {
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.gain)
                .font(.subheadline)
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(Theme.loss)
                .font(.subheadline)
        }
    }

    // MARK: - Test Google Books

    private func testGoogleBooks() async {
        isTestingGoogle = true
        googleTestResult = nil

        do {
            // Try a known-good ISBN search
            let service = GoogleBooksService()
            let results = try await service.searchByISBN("9780451524935") // 1984 by Orwell
            if !results.isEmpty {
                googleTestResult = .success("Connected — found \(results.count) result(s)")
            } else {
                googleTestResult = .failure("Connected but returned no results")
            }
        } catch BookServiceError.rateLimited {
            googleTestResult = .failure("Rate limited (429) — add an API key for higher limits")
        } catch {
            googleTestResult = .failure(error.localizedDescription)
        }

        isTestingGoogle = false
    }

    // MARK: - Test eBay

    private func testEbay() async {
        isTestingEbay = true
        ebayTestResult = nil

        let service = EbayPriceService()
        let result = await service.testCredentials()

        if result.success {
            ebayTestResult = .success(result.message)
        } else {
            ebayTestResult = .failure(result.message)
        }

        isTestingEbay = false
    }
}
