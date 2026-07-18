import SwiftUI
import SwiftData

/// Form for manually entering book details when search doesn't find the book
struct ManualEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingBooks: [Book]

    @State private var title = ""
    @State private var authors = ""
    @State private var isbn = ""
    @State private var publisher = ""
    @State private var publishedDate = ""
    @State private var pageCount = ""
    @State private var description = ""
    @State private var readingStatus: ReadingStatus = .wantToRead
    @State private var coverImage: UIImage?
    @State private var showCoverCapture = false

    // Duplicate detection
    @State private var duplicateBook: Book?
    @State private var showDuplicateAlert = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Required") {
                    TextField("Title", text: $title)
                    TextField("Author(s)", text: $authors)
                        .textContentType(.name)
                }

                Section("Details") {
                    TextField("ISBN", text: $isbn)
                        .keyboardType(.numberPad)
                    TextField("Publisher", text: $publisher)
                    TextField("Published Date", text: $publishedDate)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Page Count", text: $pageCount)
                        .keyboardType(.numberPad)
                }

                Section("Description") {
                    TextEditor(text: $description)
                        .frame(minHeight: 80)
                }

                Section("Status") {
                    Picker("Reading Status", selection: $readingStatus) {
                        ForEach(ReadingStatus.allCases) { status in
                            Label(status.rawValue, systemImage: status.systemImage)
                                .tag(status)
                        }
                    }
                }

                Section("Cover Image") {
                    if let image = coverImage {
                        HStack {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            Spacer()

                            Button("Change") {
                                showCoverCapture = true
                            }
                        }
                    } else {
                        Button {
                            showCoverCapture = true
                        } label: {
                            Label("Add Cover Photo", systemImage: "camera")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)

            // Save button
            Button {
                saveBook()
            } label: {
                Text("Add to Library")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .disabled(title.isEmpty || authors.isEmpty)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.canvas.ignoresSafeArea())
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .sheet(isPresented: $showCoverCapture) {
            CoverImageCaptureSheet(capturedImage: $coverImage)
        }
        .alert("Duplicate Book", isPresented: $showDuplicateAlert) {
            Button("Add Copy") {
                if let existing = duplicateBook {
                    existing.copyCount += 1
                }
                duplicateBook = nil
                dismiss()
            }
            Button("Add Anyway") {
                insertBook()
                duplicateBook = nil
            }
            Button("Cancel", role: .cancel) {
                duplicateBook = nil
            }
        } message: {
            if let existing = duplicateBook {
                Text("\"\(existing.title)\" is already in your library\(existing.copyCount > 1 ? " (\(existing.copyCount) copies)" : ""). Add another copy or add as a separate entry?")
            }
        }
    }

    private func saveBook() {
        // Check for duplicates
        if let existing = DuplicateDetector.findDuplicate(
            in: existingBooks,
            title: title,
            authors: authors,
            isbn: isbn.isEmpty ? nil : isbn,
            isbn13: nil
        ) {
            duplicateBook = existing
            showDuplicateAlert = true
        } else {
            insertBook()
        }
    }

    private func insertBook() {
        let book = Book(
            title: title,
            authors: authors,
            isbn: isbn.isEmpty ? nil : isbn,
            publisher: publisher.isEmpty ? nil : publisher,
            publishedDate: publishedDate.isEmpty ? nil : publishedDate,
            bookDescription: description.isEmpty ? nil : description,
            pageCount: Int(pageCount),
            readingStatus: readingStatus
        )

        if let image = coverImage {
            book.coverImageData = image.jpegData(compressionQuality: 0.8)
        }

        modelContext.insert(book)
        dismiss()
    }
}
