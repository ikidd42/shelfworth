import SwiftUI

/// Shows search results and lets the user pick which book to add
struct SearchResultsSheet: View {
    let lookupService: BookLookupService
    let onBookSelected: (Book) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isAddingBook = false
    @State private var selectedResult: BookSearchResult?

    var body: some View {
        NavigationStack {
            List(lookupService.searchResults) { result in
                Button {
                    selectedResult = result
                    addBook(result)
                } label: {
                    searchResultRow(result)
                }
                .disabled(isAddingBook)
            }
            .navigationTitle("Select a Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if isAddingBook {
                    ZStack {
                        Color.black.opacity(0.2)
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Adding to library...")
                                .font(.callout)
                        }
                        .padding(24)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .ignoresSafeArea()
                }
            }
        }
    }

    private func searchResultRow(_ result: BookSearchResult) -> some View {
        HStack(spacing: 12) {
            // Cover thumbnail
            if let urlString = result.coverImageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        thumbnailPlaceholder
                    }
                }
                .frame(width: 50, height: 75)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                thumbnailPlaceholder
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(Theme.serif(16, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                Text(result.authors)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    if let isbn = result.isbn13 ?? result.isbn {
                        Text("ISBN: \(isbn)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if let year = result.publishedDate?.prefix(4) {
                        Text(String(year))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Text(result.source.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Theme.green.opacity(0.1))
                        .foregroundStyle(Theme.green)
                        .clipShape(Capsule())
                }
            }

            Spacer()

            if selectedResult?.id == result.id && isAddingBook {
                ProgressView()
            } else {
                Image(systemName: "plus.circle")
                    .foregroundStyle(Theme.green)
                    .font(.title3)
            }
        }
        .padding(.vertical, 4)
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Theme.well)
            .frame(width: 50, height: 75)
            .overlay {
                Image(systemName: "book.closed")
                    .foregroundStyle(Theme.inkSecondary)
            }
    }

    private func addBook(_ result: BookSearchResult) {
        isAddingBook = true
        Task {
            let book = await lookupService.createBook(from: result)
            await MainActor.run {
                onBookSelected(book)
                dismiss()
            }
        }
    }
}
