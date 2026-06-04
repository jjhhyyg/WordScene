import Foundation
import UniformTypeIdentifiers

struct SharedContentExtractionResult: Equatable {
    let text: String
    let sourceURL: URL?
}

enum SharedContentExtractorError: Error, Equatable {
    case noReadableContent
}

struct SharedContentExtractor {
    func extractText(from providers: [NSItemProvider]) async throws -> SharedContentExtractionResult {
        for provider in providers {
            if let text = await loadText(from: provider, typeIdentifier: UTType.plainText.identifier) {
                return SharedContentExtractionResult(text: text, sourceURL: nil)
            }
        }

        for provider in providers {
            if let text = await loadText(from: provider, typeIdentifier: UTType.text.identifier) {
                return SharedContentExtractionResult(text: text, sourceURL: nil)
            }
        }

        for provider in providers {
            if let url = await loadURL(from: provider) {
                return SharedContentExtractionResult(text: url.absoluteString, sourceURL: url)
            }
        }

        throw SharedContentExtractorError.noReadableContent
    }

    private func loadText(from provider: NSItemProvider, typeIdentifier: String) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(typeIdentifier) else {
            return nil
        }

        do {
            let item = try await loadItem(from: provider, typeIdentifier: typeIdentifier)
            return trimmedText(from: item)
        } catch {
            return nil
        }
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else {
            return nil
        }

        do {
            let item = try await loadItem(from: provider, typeIdentifier: UTType.url.identifier)
            return url(from: item)
        } catch {
            return nil
        }
    }

    private func loadItem(from provider: NSItemProvider, typeIdentifier: String) async throws -> LoadedItem? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: loadedItem(from: item))
                }
            }
        }
    }

    private func loadedItem(from item: NSSecureCoding?) -> LoadedItem? {
        switch item {
        case let value as String:
            return .text(value)
        case let value as NSString:
            return .text(value as String)
        case let value as Data:
            return .data(value)
        case let value as NSAttributedString:
            return .text(value.string)
        case let value as URL:
            return .url(value)
        case let value as NSURL:
            return .url(value as URL)
        default:
            return nil
        }
    }

    private func trimmedText(from item: LoadedItem?) -> String? {
        let text: String?

        switch item {
        case let .text(value):
            text = value
        case let .data(value):
            text = String(data: value, encoding: .utf8)
        default:
            text = nil
        }

        return text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func url(from item: LoadedItem?) -> URL? {
        switch item {
        case let .url(value):
            return value
        case let .text(value):
            return trimmedURL(from: value)
        case let .data(value):
            guard let string = String(data: value, encoding: .utf8) else {
                return nil
            }
            return trimmedURL(from: string)
        default:
            return nil
        }
    }

    private func trimmedURL(from string: String) -> URL? {
        let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }
        return URL(string: text)
    }
}

private enum LoadedItem: Sendable {
    case text(String)
    case data(Data)
    case url(URL)
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
