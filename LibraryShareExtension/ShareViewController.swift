//
//  ShareViewController.swift
//  LibraryShareExtension
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers
import os

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "LibraryShareExtension",
    category: "share"
)

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        extractSharedURL()
    }

    private func extractSharedURL() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem else {
            logger.error("No extension item found")
            showResult(success: false, message: "Couldn't read the shared item.")
            return
        }

        let urlType = UTType.url.identifier
        let textType = UTType.plainText.identifier
        let providers = extensionItem.attachments ?? []

        let rawTitle = extensionItem.attributedTitle?.string
                    ?? extensionItem.attributedContentText?.string
                    ?? ""

        // Prefer a proper URL attachment; fall back to plain text (some apps share links as text)
        if let urlProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(urlType) }) {
            urlProvider.loadItem(forTypeIdentifier: urlType, options: nil) { [weak self] item, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let error {
                        logger.error("loadItem(url) error: \(error)")
                        self.showResult(success: false, message: "Couldn't load the URL.")
                        return
                    }
                    if let url = item as? URL {
                        self.processURL(url, rawTitle: rawTitle)
                    } else if let str = item as? String, let url = URL(string: str) {
                        self.processURL(url, rawTitle: rawTitle)
                    } else {
                        logger.error("Item is not a URL — got: \(type(of: item))")
                        self.showResult(success: false, message: "Couldn't load the URL.")
                    }
                }
            }
        } else if let textProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(textType) }) {
            textProvider.loadItem(forTypeIdentifier: textType, options: nil) { [weak self] item, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let error {
                        logger.error("loadItem(text) error: \(error)")
                        self.showResult(success: false, message: "Couldn't load the URL.")
                        return
                    }
                    guard let text = item as? String else {
                        logger.error("Text item is not a String: \(type(of: item))")
                        self.showResult(success: false, message: "No URL found in the shared content.")
                        return
                    }
                    // Extract the first http/https URL from the text
                    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
                    let matches = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
                    if let first = matches.first, let url = first.url {
                        self.processURL(url, rawTitle: rawTitle.isEmpty ? text : rawTitle)
                    } else {
                        logger.error("No URL found in shared text")
                        self.showResult(success: false, message: "No eBay link found in the shared content.")
                    }
                }
            }
        } else {
            logger.error("No URL or text attachment found among: \(providers.map(\.registeredTypeIdentifiers))")
            showResult(success: false, message: "No URL found. Please share an eBay listing link.")
        }
    }

    private func processURL(_ url: URL, rawTitle: String) {
        logger.debug("Processing URL: \(url.absoluteString)")

        guard url.host?.contains("ebay") == true else {
            logger.error("Not an eBay URL: \(url.absoluteString)")
            showResult(success: false, message: "This doesn't look like an eBay listing. Please share a link from the eBay app or website.")
            return
        }

        guard let itemID = SharedContainer.parseItemID(from: url) else {
            logger.error("Could not parse item ID from URL: \(url.absoluteString)")
            showResult(success: false, message: "Couldn't find an eBay item ID in this link.")
            return
        }

        let cleanTitle = rawTitle
            .replacingOccurrences(of: " | eBay", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let pending = PendingWatchItem(
            ebayItemID: itemID,
            ebayListingURL: url.absoluteString,
            listingTitle: cleanTitle.isEmpty ? "eBay Item \(itemID)" : cleanTitle
        )

        SharedContainer.appendPendingItem(pending)
        showResult(success: true, message: cleanTitle.isEmpty ? "Added to Watchlist" : "\"\(cleanTitle)\" added to your Watchlist.")
    }

    // MARK: - Result UI

    private func showResult(success: Bool, message: String) {
        let hostingController = UIHostingController(
            rootView: ShareResultView(
                success: success,
                message: message,
                onDismiss: { [weak self] in
                    self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                }
            )
        )
        hostingController.view.backgroundColor = .clear
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)
    }
}
