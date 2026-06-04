# Share Extension Translation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an iOS Share Extension named `翻译到译笺` that receives shared text, translates it, lets the user copy or favorite the translation, and opens WordScene with the original text and translated result already loaded.

**Architecture:** Add an iOS share extension target plus a small set of extension-safe shared services. The extension performs text extraction and translation, then writes handoff and pending history/favorite operations into App Group storage; the main app consumes those operations when opened and commits them through the existing repositories. System local notifications are explicitly out of scope.

**Tech Stack:** Swift 6, SwiftUI, UIKit share extension hosting, XcodeGen, Core Data repositories already in WordScene, App Group `UserDefaults`/JSON file storage, Keychain, DeepSeek OpenAI-compatible translation client, `Localizable.xcstrings`.

---

## File Structure

- Create `WordScene/Sources/Shared/Services/ShareExtensionSupport.swift`: shared constants, handoff model, pending operation model, App Group file store.
- Create `WordScene/Tests/ShareExtensionSupportTests.swift`: validates handoff round trip, pending operation append/consume, missing App Group fallback through temporary directory injection.
- Create `WordScene/Sources/Shared/Services/SharedContentExtractor.swift`: extracts plain text, attributed text plain strings, and URL strings from `NSItemProvider`.
- Create `WordScene/Tests/SharedContentExtractorTests.swift`: validates plain text, URL, empty providers, and priority order.
- Create `WordScene/Sources/ShareExtension/ShareViewController.swift`: UIKit entry point that hosts the SwiftUI share view.
- Create `WordScene/Sources/ShareExtension/ShareTranslationView.swift`: lightweight panel UI for original text, target language, translated text, copy, favorite, and open actions.
- Create `WordScene/Sources/ShareExtension/ShareTranslationViewModel.swift`: extraction, translation workflow, pending favorite/history writes, and open URL coordination.
- Create `WordScene/ShareExtension/ShareExtensionInfo.plist`: extension metadata and activation rule.
- Create `WordScene/WordSceneShareExtension.entitlements`: App Group and network entitlement.
- Modify `WordScene/WordSceneiOS.entitlements`: add the same App Group.
- Modify `project.yml`: add `WordSceneShareExtension`, embed it in the iOS app, add URL scheme for main app handoff.
- Modify `WordScene/Sources/Shared/App/WordSceneApp.swift`: install `.onOpenURL` and an app-level route coordinator.
- Create `WordScene/Sources/Shared/App/AppRouteCoordinator.swift`: stores a pending share handoff id and exposes it to `RootView`.
- Modify `WordScene/Sources/Shared/App/RootView.swift`: switch to Translate tab when a share handoff is opened.
- Modify `WordScene/Sources/Shared/Features/Translate/TranslationView.swift`: load a handoff record, show original and existing translation, and consume pending history/favorite operations.
- Modify `WordScene/Resources/Localizable.xcstrings`: add all new localized strings.
- Modify `WordScene/Tests/AppLocalizationTests.swift`: require complete localizations for Share Extension keys.

## Task 1: Shared Handoff Store

**Files:**
- Create: `WordScene/Sources/Shared/Services/ShareExtensionSupport.swift`
- Create: `WordScene/Tests/ShareExtensionSupportTests.swift`

- [ ] **Step 1: Write failing tests for handoff and pending operations**

Add `WordScene/Tests/ShareExtensionSupportTests.swift`:

```swift
import Foundation
import XCTest
@testable import WordScene

final class ShareExtensionSupportTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WordSceneShareExtensionSupportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testSaveAndLoadHandoffRecord() throws {
        let store = ShareExtensionHandoffStore(directoryURL: temporaryDirectory)
        let record = ShareExtensionHandoffRecord(
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            isFavoritePending: true
        )

        try store.save(record)

        XCTAssertEqual(try store.load(id: record.id), record)
    }

    func testConsumePendingOperationsReturnsAndClearsQueuedOperations() throws {
        let store = ShareExtensionHandoffStore(directoryURL: temporaryDirectory)
        let record = ShareExtensionHandoffRecord(
            sourceText: "good morning",
            translatedText: "早上好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            isFavoritePending: false
        )

        try store.appendPendingOperation(.history(record))
        try store.appendPendingOperation(.favorite(record))

        let operations = try store.consumePendingOperations()

        XCTAssertEqual(operations, [.history(record), .favorite(record)])
        XCTAssertEqual(try store.consumePendingOperations(), [])
    }

    func testDeleteHandoffRemovesStoredRecord() throws {
        let store = ShareExtensionHandoffStore(directoryURL: temporaryDirectory)
        let record = ShareExtensionHandoffRecord(
            sourceText: "thanks",
            translatedText: "谢谢",
            sourceLanguage: .en,
            targetLanguage: .zh,
            isFavoritePending: false
        )

        try store.save(record)
        try store.delete(id: record.id)

        XCTAssertNil(try store.load(id: record.id))
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test -project WordScene.xcodeproj -scheme WordScene -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:WordSceneTests/ShareExtensionSupportTests
```

Expected: build fails because `ShareExtensionHandoffStore`, `ShareExtensionHandoffRecord`, and `ShareExtensionPendingOperation` do not exist.

- [ ] **Step 3: Implement shared handoff support**

Add `WordScene/Sources/Shared/Services/ShareExtensionSupport.swift`:

```swift
import Foundation

enum ShareExtensionConfiguration {
    static let appGroupIdentifier = "group.com.erikssonhou.leximemory"
    static let urlScheme = "wordscene"
    static let handoffHost = "share-translation"
}

struct ShareExtensionHandoffRecord: Codable, Equatable, Identifiable {
    let id: UUID
    var sourceText: String
    var translatedText: String
    var sourceLanguage: LanguageSelection
    var targetLanguage: LanguageSelection
    var isFavoritePending: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        sourceText: String,
        translatedText: String,
        sourceLanguage: LanguageSelection,
        targetLanguage: LanguageSelection,
        isFavoritePending: Bool,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.isFavoritePending = isFavoritePending
        self.createdAt = createdAt
    }

    var translationRecord: TranslationRecord {
        TranslationRecord(
            sourceText: sourceText,
            translatedText: translatedText,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            createdAt: createdAt
        )
    }
}

enum ShareExtensionPendingOperation: Codable, Equatable {
    case history(ShareExtensionHandoffRecord)
    case favorite(ShareExtensionHandoffRecord)

    private enum CodingKeys: String, CodingKey {
        case kind
        case record
    }

    private enum Kind: String, Codable {
        case history
        case favorite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let record = try container.decode(ShareExtensionHandoffRecord.self, forKey: .record)
        switch kind {
        case .history:
            self = .history(record)
        case .favorite:
            self = .favorite(record)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .history(let record):
            try container.encode(Kind.history, forKey: .kind)
            try container.encode(record, forKey: .record)
        case .favorite(let record):
            try container.encode(Kind.favorite, forKey: .kind)
            try container.encode(record, forKey: .record)
        }
    }
}

struct ShareExtensionHandoffStore {
    private let directoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init?() {
        guard let directoryURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ShareExtensionConfiguration.appGroupIdentifier
        ) else {
            return nil
        }
        self.init(directoryURL: directoryURL)
    }

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func save(_ record: ShareExtensionHandoffRecord) throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(record)
        try data.write(to: handoffURL(id: record.id), options: [.atomic])
    }

    func load(id: UUID) throws -> ShareExtensionHandoffRecord? {
        let url = handoffURL(id: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(ShareExtensionHandoffRecord.self, from: data)
    }

    func delete(id: UUID) throws {
        let url = handoffURL(id: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func appendPendingOperation(_ operation: ShareExtensionPendingOperation) throws {
        try ensureDirectoryExists()
        var operations = try pendingOperations()
        operations.append(operation)
        let data = try encoder.encode(operations)
        try data.write(to: pendingOperationsURL, options: [.atomic])
    }

    func consumePendingOperations() throws -> [ShareExtensionPendingOperation] {
        let operations = try pendingOperations()
        if FileManager.default.fileExists(atPath: pendingOperationsURL.path) {
            try FileManager.default.removeItem(at: pendingOperationsURL)
        }
        return operations
    }

    private func pendingOperations() throws -> [ShareExtensionPendingOperation] {
        guard FileManager.default.fileExists(atPath: pendingOperationsURL.path) else {
            return []
        }
        let data = try Data(contentsOf: pendingOperationsURL)
        return try decoder.decode([ShareExtensionPendingOperation].self, from: data)
    }

    private func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func handoffURL(id: UUID) -> URL {
        directoryURL.appendingPathComponent("share-handoff-\(id.uuidString).json")
    }

    private var pendingOperationsURL: URL {
        directoryURL.appendingPathComponent("share-pending-operations.json")
    }
}
```

- [ ] **Step 4: Run tests and verify pass**

Run:

```bash
xcodebuild test -project WordScene.xcodeproj -scheme WordScene -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:WordSceneTests/ShareExtensionSupportTests
```

Expected: `ShareExtensionSupportTests` pass.

- [ ] **Step 5: Commit**

```bash
git add WordScene/Sources/Shared/Services/ShareExtensionSupport.swift WordScene/Tests/ShareExtensionSupportTests.swift
git commit -m "Add share extension handoff store"
```

## Task 2: Shared Content Extraction

**Files:**
- Create: `WordScene/Sources/Shared/Services/SharedContentExtractor.swift`
- Create: `WordScene/Tests/SharedContentExtractorTests.swift`

- [ ] **Step 1: Write failing tests**

Add `WordScene/Tests/SharedContentExtractorTests.swift`:

```swift
import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import WordScene

final class SharedContentExtractorTests: XCTestCase {
    func testExtractsPlainText() async throws {
        let provider = NSItemProvider(item: "shared phrase" as NSString, typeIdentifier: UTType.plainText.identifier)

        let result = try await SharedContentExtractor().extractText(from: [provider])

        XCTAssertEqual(result.text, "shared phrase")
        XCTAssertNil(result.sourceURL)
    }

    func testExtractsURLWhenTextIsMissing() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/article"))
        let provider = NSItemProvider(item: url as NSURL, typeIdentifier: UTType.url.identifier)

        let result = try await SharedContentExtractor().extractText(from: [provider])

        XCTAssertEqual(result.text, "https://example.com/article")
        XCTAssertEqual(result.sourceURL, url)
    }

    func testPlainTextBeatsURL() async throws {
        let textProvider = NSItemProvider(item: "selected words" as NSString, typeIdentifier: UTType.plainText.identifier)
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let urlProvider = NSItemProvider(item: url as NSURL, typeIdentifier: UTType.url.identifier)

        let result = try await SharedContentExtractor().extractText(from: [urlProvider, textProvider])

        XCTAssertEqual(result.text, "selected words")
        XCTAssertNil(result.sourceURL)
    }

    func testThrowsWhenNoReadableContentExists() async {
        do {
            _ = try await SharedContentExtractor().extractText(from: [])
            XCTFail("Expected unreadable content to throw")
        } catch SharedContentExtractorError.noReadableContent {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test -project WordScene.xcodeproj -scheme WordScene -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:WordSceneTests/SharedContentExtractorTests
```

Expected: build fails because `SharedContentExtractor` does not exist.

- [ ] **Step 3: Implement extractor**

Add `WordScene/Sources/Shared/Services/SharedContentExtractor.swift`:

```swift
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
        if let text = try await firstString(from: providers, type: .plainText) {
            return SharedContentExtractionResult(text: text, sourceURL: nil)
        }

        if let text = try await firstString(from: providers, type: .text) {
            return SharedContentExtractionResult(text: text, sourceURL: nil)
        }

        if let url = try await firstURL(from: providers) {
            return SharedContentExtractionResult(text: url.absoluteString, sourceURL: url)
        }

        throw SharedContentExtractorError.noReadableContent
    }

    private func firstString(from providers: [NSItemProvider], type: UTType) async throws -> String? {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            if let value = try await loadString(from: provider, typeIdentifier: type.identifier) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private func firstURL(from providers: [NSItemProvider]) async throws -> URL? {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let item = try await loadItem(from: provider, typeIdentifier: UTType.url.identifier) {
                if let url = item as? URL {
                    return url
                }
                if let url = item as? NSURL {
                    return url as URL
                }
                if let text = item as? String, let url = URL(string: text) {
                    return url
                }
            }
        }
        return nil
    }

    private func loadString(from provider: NSItemProvider, typeIdentifier: String) async throws -> String? {
        let item = try await loadItem(from: provider, typeIdentifier: typeIdentifier)
        if let string = item as? String {
            return string
        }
        if let string = item as? NSString {
            return string as String
        }
        if let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        if let attributed = item as? NSAttributedString {
            return attributed.string
        }
        return nil
    }

    private func loadItem(from provider: NSItemProvider, typeIdentifier: String) async throws -> NSSecureCoding? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: item as? NSSecureCoding)
            }
        }
    }
}
```

- [ ] **Step 4: Run tests and verify pass**

Run:

```bash
xcodebuild test -project WordScene.xcodeproj -scheme WordScene -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:WordSceneTests/SharedContentExtractorTests
```

Expected: `SharedContentExtractorTests` pass.

- [ ] **Step 5: Commit**

```bash
git add WordScene/Sources/Shared/Services/SharedContentExtractor.swift WordScene/Tests/SharedContentExtractorTests.swift
git commit -m "Add shared content extraction"
```

## Task 3: Project Target, Entitlements, and Extension Metadata

**Files:**
- Modify: `project.yml`
- Modify: `WordScene/WordSceneiOS.entitlements`
- Create: `WordScene/WordSceneShareExtension.entitlements`
- Create: `WordScene/ShareExtension/ShareExtensionInfo.plist`
- Create: `WordScene/Sources/ShareExtension/ShareViewController.swift`

- [ ] **Step 1: Add placeholder extension controller**

Create `WordScene/Sources/ShareExtension/ShareViewController.swift`:

```swift
import UIKit

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }
}
```

- [ ] **Step 2: Add Share Extension Info.plist**

Create `WordScene/ShareExtension/ShareExtensionInfo.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>翻译到译笺</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.share-services</string>
        <key>NSExtensionPrincipalClass</key>
        <string>$(PRODUCT_MODULE_NAME).ShareViewController</string>
        <key>NSExtensionAttributes</key>
        <dict>
            <key>NSExtensionActivationRule</key>
            <dict>
                <key>NSExtensionActivationSupportsText</key>
                <true/>
                <key>NSExtensionActivationSupportsWebURLWithMaxCount</key>
                <integer>1</integer>
            </dict>
        </dict>
    </dict>
</dict>
</plist>
```

- [ ] **Step 3: Add extension entitlements**

Create `WordScene/WordSceneShareExtension.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.erikssonhou.leximemory</string>
    </array>
</dict>
</plist>
```

Add the same App Group key to `WordScene/WordSceneiOS.entitlements`.

- [ ] **Step 4: Modify `project.yml`**

Add `WordSceneShareExtension` under `targets`:

```yaml
  WordSceneShareExtension:
    type: app-extension
    platform: iOS
    deploymentTarget: "18.0"
    sources:
      - path: WordScene/Sources/ShareExtension
      - path: WordScene/Sources/Shared
      - path: WordScene/Resources
    resources:
      - path: WordScene/Resources
    info:
      path: WordScene/ShareExtension/ShareExtensionInfo.plist
    entitlements:
      path: WordScene/WordSceneShareExtension.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.erikssonhou.leximemory
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.erikssonhou.leximemory.share
        PRODUCT_NAME: Translate to WordScene
        PRODUCT_MODULE_NAME: WordSceneShareExtension
        APPLICATION_EXTENSION_API_ONLY: YES
        GENERATE_INFOPLIST_FILE: NO
```

Add the extension dependency to the `WordScene` target:

```yaml
    dependencies:
      - target: WordSceneShareExtension
        embed: true
```

Add the App Group entitlement property to the `WordScene` target entitlements block:

```yaml
        com.apple.security.application-groups:
          - group.com.erikssonhou.leximemory
```

Add URL scheme support under the `WordScene` target Info properties:

```yaml
        CFBundleURLTypes:
          - CFBundleURLName: com.erikssonhou.leximemory.share
            CFBundleURLSchemes:
              - wordscene
```

- [ ] **Step 5: Generate project and verify target**

Run:

```bash
xcodegen generate
xcodebuild -list -project WordScene.xcodeproj
```

Expected: target list includes `WordSceneShareExtension`; no `TRUEPREDICATE` appears in `WordScene/ShareExtension/ShareExtensionInfo.plist`.

- [ ] **Step 6: Commit**

```bash
git add project.yml WordScene.xcodeproj WordScene/WordSceneiOS.entitlements WordScene/WordSceneShareExtension.entitlements WordScene/ShareExtension/ShareExtensionInfo.plist WordScene/Sources/ShareExtension/ShareViewController.swift
git commit -m "Add share extension target"
```

## Task 4: Share Extension UI and Workflow

**Files:**
- Create: `WordScene/Sources/ShareExtension/ShareTranslationView.swift`
- Create: `WordScene/Sources/ShareExtension/ShareTranslationViewModel.swift`
- Modify: `WordScene/Sources/ShareExtension/ShareViewController.swift`

- [ ] **Step 1: Implement view model**

Create `WordScene/Sources/ShareExtension/ShareTranslationViewModel.swift`:

```swift
import Foundation

@MainActor
final class ShareTranslationViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case ready(String)
        case translating(String)
        case translated(ShareExtensionHandoffRecord)
        case failed(String, sourceText: String?)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var didCopy = false
    @Published private(set) var didFavorite = false
    @Published var targetLanguage: LanguageSelection = .zh

    private let extractor: SharedContentExtractor
    private let credentialStore: any CredentialStoring
    private let translationClient: any TranslationClienting
    private let handoffStore: ShareExtensionHandoffStore?

    init(
        extractor: SharedContentExtractor = SharedContentExtractor(),
        credentialStore: any CredentialStoring = KeychainCredentialStore(),
        translationClient: any TranslationClienting = DeepSeekTranslationClient(),
        handoffStore: ShareExtensionHandoffStore? = ShareExtensionHandoffStore()
    ) {
        self.extractor = extractor
        self.credentialStore = credentialStore
        self.translationClient = translationClient
        self.handoffStore = handoffStore
    }

    func load(providers: [NSItemProvider]) {
        Task {
            do {
                let extracted = try await extractor.extractText(from: providers)
                state = .ready(extracted.text)
                await translate(sourceText: extracted.text)
            } catch {
                state = .failed(String(localized: "无法读取分享内容"), sourceText: nil)
            }
        }
    }

    func translate(sourceText: String) async {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .failed(String(localized: "无法读取分享内容"), sourceText: nil)
            return
        }

        state = .translating(trimmed)
        do {
            guard let rawToken = try credentialStore.read(account: DeepSeekCredential.tokenAccount),
                  !rawToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TranslationWorkflowError.missingToken
            }
            let sourceLanguage = TranslationLanguageDetector.detect(trimmed) ?? .auto
            let translatedText = try await translationClient.translate(
                text: trimmed,
                source: sourceLanguage,
                target: targetLanguage,
                apiToken: rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let record = ShareExtensionHandoffRecord(
                sourceText: trimmed,
                translatedText: translatedText,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                isFavoritePending: false
            )
            try handoffStore?.save(record)
            try handoffStore?.appendPendingOperation(.history(record))
            state = .translated(record)
        } catch TranslationWorkflowError.missingToken {
            state = .failed(String(localized: "请先在设置中保存 DeepSeek API Token。"), sourceText: trimmed)
        } catch {
            state = .failed(String(localized: "翻译失败"), sourceText: trimmed)
        }
    }

    func markFavorite() {
        guard case .translated(var record) = state else {
            return
        }
        record.isFavoritePending = true
        do {
            try handoffStore?.save(record)
            try handoffStore?.appendPendingOperation(.favorite(record))
            didFavorite = true
            state = .translated(record)
        } catch {
            state = .failed(String(localized: "收藏失败"), sourceText: record.sourceText)
        }
    }

    func openURL() -> URL? {
        guard case .translated(let record) = state else {
            return nil
        }
        return URL(string: "\(ShareExtensionConfiguration.urlScheme)://\(ShareExtensionConfiguration.handoffHost)?id=\(record.id.uuidString)")
    }
}
```

- [ ] **Step 2: Implement SwiftUI share panel**

Create `WordScene/Sources/ShareExtension/ShareTranslationView.swift`:

```swift
import SwiftUI

struct ShareTranslationView: View {
    @StateObject var viewModel: ShareTranslationViewModel
    let onCopy: (String) -> Void
    let onOpen: (URL) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                content
                Spacer(minLength: 0)
                actionBar
            }
            .padding(18)
            .navigationTitle(String(localized: "翻译到译笺"))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready(let sourceText), .translating(let sourceText):
            sourceSection(sourceText)
            ProgressView(String(localized: "翻译中..."))
        case .translated(let record):
            sourceSection(record.sourceText)
            translationSection(record.translatedText)
        case .failed(let message, let sourceText):
            if let sourceText {
                sourceSection(sourceText)
            }
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    private func sourceSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "原文")).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                Text(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 90, maxHeight: 160)
        }
    }

    private func translationSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "译文")).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                Text(text)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 110, maxHeight: 220)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                if case .translated(let record) = viewModel.state {
                    onCopy(record.translatedText)
                }
            } label: {
                Label(viewModel.didCopy ? String(localized: "已复制") : String(localized: "复制译文"), systemImage: "doc.on.doc")
            }
            .disabled(!isTranslated)

            Button {
                viewModel.markFavorite()
            } label: {
                Label(viewModel.didFavorite ? String(localized: "已收藏") : String(localized: "收藏"), systemImage: viewModel.didFavorite ? "bookmark.fill" : "bookmark")
            }
            .disabled(!isTranslated || viewModel.didFavorite)

            Button {
                if let url = viewModel.openURL() {
                    onOpen(url)
                }
            } label: {
                Label(String(localized: "打开译笺"), systemImage: "arrow.up.forward.app")
            }
            .disabled(viewModel.openURL() == nil)
        }
        .buttonStyle(.bordered)
    }

    private var isTranslated: Bool {
        if case .translated = viewModel.state {
            return true
        }
        return false
    }
}
```

- [ ] **Step 3: Host SwiftUI in extension controller**

Replace `WordScene/Sources/ShareExtension/ShareViewController.swift` with:

```swift
import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    private let viewModel = ShareTranslationViewModel()

    override func viewDidLoad() {
        super.viewDidLoad()

        let view = ShareTranslationView(
            viewModel: viewModel,
            onCopy: { [weak self] text in
                UIPasteboard.general.string = text
                self?.viewModel.didCopy = true
            },
            onOpen: { [weak self] url in
                self?.extensionContext?.open(url) { _ in
                    self?.extensionContext?.completeRequest(returningItems: nil)
                }
            }
        )
        let hosting = UIHostingController(rootView: view)
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hosting.didMove(toParent: self)

        let providers = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []
        viewModel.load(providers: providers)
    }
}
```

- [ ] **Step 4: Build extension**

Run:

```bash
xcodebuild build -project WordScene.xcodeproj -scheme WordScene -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'
```

Expected: iOS app builds and embeds the share extension. If `extensionContext.open` is unavailable for the extension target, replace the open implementation with the documented responder-chain URL opening path after verifying it does not use private API.

- [ ] **Step 5: Commit**

```bash
git add WordScene/Sources/ShareExtension/ShareTranslationView.swift WordScene/Sources/ShareExtension/ShareTranslationViewModel.swift WordScene/Sources/ShareExtension/ShareViewController.swift
git commit -m "Add share extension translation UI"
```

## Task 5: Main App Handoff Consumption

**Files:**
- Create: `WordScene/Sources/Shared/App/AppRouteCoordinator.swift`
- Modify: `WordScene/Sources/Shared/App/WordSceneApp.swift`
- Modify: `WordScene/Sources/Shared/App/RootView.swift`
- Modify: `WordScene/Sources/Shared/Features/Translate/TranslationView.swift`

- [ ] **Step 1: Add route coordinator**

Create `WordScene/Sources/Shared/App/AppRouteCoordinator.swift`:

```swift
import Foundation

@MainActor
final class AppRouteCoordinator: ObservableObject {
    @Published var pendingShareHandoffID: UUID?

    func open(url: URL) {
        guard url.scheme == ShareExtensionConfiguration.urlScheme,
              url.host == ShareExtensionConfiguration.handoffHost,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let idValue = components.queryItems?.first(where: { $0.name == "id" })?.value,
              let id = UUID(uuidString: idValue) else {
            return
        }
        pendingShareHandoffID = id
    }

    func consumePendingShareHandoffID() -> UUID? {
        let id = pendingShareHandoffID
        pendingShareHandoffID = nil
        return id
    }
}
```

- [ ] **Step 2: Wire coordinator into app**

Modify `WordScene/Sources/Shared/App/WordSceneApp.swift`:

```swift
@StateObject private var routeCoordinator = AppRouteCoordinator()
```

Add `.environmentObject(routeCoordinator)` to `RootView()` and `SettingsView()`, and add:

```swift
.onOpenURL { url in
    routeCoordinator.open(url: url)
}
```

on the `RootView()` scene content.

- [ ] **Step 3: Switch to Translate tab on handoff**

Modify `RootView` to include:

```swift
@EnvironmentObject private var routeCoordinator: AppRouteCoordinator
```

Add:

```swift
.onReceive(routeCoordinator.$pendingShareHandoffID.compactMap { $0 }) { _ in
    selectedSection = .translate
}
```

to the root container.

- [ ] **Step 4: Consume handoff in TranslationView**

Modify `TranslationView` to add:

```swift
@EnvironmentObject private var routeCoordinator: AppRouteCoordinator
@State private var consumedHandoffIDs: Set<UUID> = []
```

Add an `.onReceive(routeCoordinator.$pendingShareHandoffID.compactMap { $0 })` handler that calls:

```swift
private func applyShareHandoff(id: UUID) {
    guard !consumedHandoffIDs.contains(id),
          let store = ShareExtensionHandoffStore(),
          let handoff = try? store.load(id: id) else {
        return
    }
    consumedHandoffIDs.insert(id)
    sourceLanguage = handoff.sourceLanguage
    targetLanguage = handoff.targetLanguage
    inputText = handoff.sourceText
    lastTranslatedRecord = handoff.translationRecord
    translationState = .translated(handoff.translatedText)
    consumePendingShareOperations(using: store)
    try? store.delete(id: id)
    _ = routeCoordinator.consumePendingShareHandoffID()
}
```

Add:

```swift
private func consumePendingShareOperations(using store: ShareExtensionHandoffStore) {
    guard let operations = try? store.consumePendingOperations() else {
        return
    }
    for operation in operations {
        switch operation {
        case .history(let handoff):
            let updatedHistory = historyStore.adding(handoff.translationRecord, to: history)
            try? historyStore.saveOrThrow(updatedHistory)
            history = updatedHistory
        case .favorite(let handoff):
            let updatedItems = memoryStore.adding(MemoryItem(record: handoff.translationRecord), to: memoryItems)
            try? memoryStore.saveOrThrow(updatedItems)
            memoryItems = updatedItems
        }
    }
}
```

- [ ] **Step 5: Add tests for route parsing**

Add a test method to `WordScene/Tests/AppDataControllerTests.swift` or create `WordScene/Tests/AppRouteCoordinatorTests.swift`:

```swift
@MainActor
func testRouteCoordinatorParsesShareTranslationURL() throws {
    let coordinator = AppRouteCoordinator()
    let id = UUID()

    coordinator.open(url: try XCTUnwrap(URL(string: "wordscene://share-translation?id=\(id.uuidString)")))

    XCTAssertEqual(coordinator.pendingShareHandoffID, id)
    XCTAssertEqual(coordinator.consumePendingShareHandoffID(), id)
    XCTAssertNil(coordinator.pendingShareHandoffID)
}
```

- [ ] **Step 6: Run route tests**

Run:

```bash
xcodebuild test -project WordScene.xcodeproj -scheme WordScene -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:WordSceneTests/AppRouteCoordinatorTests
```

Expected: route coordinator tests pass.

- [ ] **Step 7: Commit**

```bash
git add WordScene/Sources/Shared/App/AppRouteCoordinator.swift WordScene/Sources/Shared/App/WordSceneApp.swift WordScene/Sources/Shared/App/RootView.swift WordScene/Sources/Shared/Features/Translate/TranslationView.swift WordScene/Tests/AppRouteCoordinatorTests.swift
git commit -m "Handle share translation handoff"
```

## Task 6: Localization

**Files:**
- Modify: `WordScene/Resources/Localizable.xcstrings`
- Modify: `WordScene/Tests/AppLocalizationTests.swift`
- Create or modify localized extension display resources if XcodeGen requires separate `InfoPlist.strings` entries.

- [ ] **Step 1: Add required localization test keys**

Modify `testHighRiskDynamicStringsHaveEnglishAndSpanishTranslations` in `WordScene/Tests/AppLocalizationTests.swift` and append:

```swift
"翻译到译笺",
"原文",
"目标语言",
"译文",
"翻译中...",
"复制译文",
"已复制",
"收藏",
"已收藏",
"打开译笺",
"无法读取分享内容",
"翻译失败",
"收藏失败",
"已保存到收藏"
```

- [ ] **Step 2: Run localization test and verify failure**

Run:

```bash
xcodebuild test -project WordScene.xcodeproj -scheme WordScene -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:WordSceneTests/AppLocalizationTests/testHighRiskDynamicStringsHaveEnglishAndSpanishTranslations
```

Expected: fails for missing Share Extension localization keys.

- [ ] **Step 3: Add Localizable.xcstrings keys**

Add complete localizations for the keys above to `WordScene/Resources/Localizable.xcstrings`. Required English and Spanish values:

```text
翻译到译笺 -> Translate to WordScene / Traducir a WordScene
原文 -> Original / Original
目标语言 -> Target Language / Idioma de destino
译文 -> Translation / Traducción
翻译中... -> Translating... / Traduciendo...
复制译文 -> Copy Translation / Copiar traducción
已复制 -> Copied / Copiado
收藏 -> Save / Guardar
已收藏 -> Saved / Guardado
打开译笺 -> Open WordScene / Abrir WordScene
无法读取分享内容 -> Cannot read shared content / No se puede leer el contenido compartido
翻译失败 -> Translation Failed / Error de traducción
收藏失败 -> Save Failed / Error al guardar
已保存到收藏 -> Saved to Library / Guardado en favoritos
```

All supported localization codes must be present because `testSourceLocalizedStringKeysHaveCompleteCatalogCoverage` checks every source key.

- [ ] **Step 4: Run localization tests**

Run:

```bash
xcodebuild test -project WordScene.xcodeproj -scheme WordScene -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:WordSceneTests/AppLocalizationTests
```

Expected: `AppLocalizationTests` pass.

- [ ] **Step 5: Commit**

```bash
git add WordScene/Resources/Localizable.xcstrings WordScene/Tests/AppLocalizationTests.swift
git commit -m "Localize share extension strings"
```

## Task 7: Full Verification

**Files:**
- No new files expected; fixes may touch files from earlier tasks.

- [ ] **Step 1: Regenerate project**

Run:

```bash
xcodegen generate
```

Expected: exits 0.

- [ ] **Step 2: Run focused unit tests**

Run:

```bash
xcodebuild test -project WordScene.xcodeproj -scheme WordScene -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:WordSceneTests/ShareExtensionSupportTests -only-testing:WordSceneTests/SharedContentExtractorTests -only-testing:WordSceneTests/AppRouteCoordinatorTests -only-testing:WordSceneTests/AppLocalizationTests
```

Expected: all focused tests pass.

- [ ] **Step 3: Run iOS build**

Run:

```bash
xcodebuild build -project WordScene.xcodeproj -scheme WordScene -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'
```

Expected: build succeeds and embeds `WordSceneShareExtension.appex`.

- [ ] **Step 4: Validate activation rule**

Run:

```bash
plutil -p WordScene/ShareExtension/ShareExtensionInfo.plist | rg 'TRUEPREDICATE|NSExtensionActivationSupportsText|NSExtensionActivationSupportsWebURLWithMaxCount'
```

Expected: output includes text and URL activation keys; output does not include `TRUEPREDICATE`.

- [ ] **Step 5: Validate notification scope is absent**

Run:

```bash
rg -n 'UNUserNotificationCenter|译文已生成|翻译完成通知|本地通知' WordScene/Sources WordScene/Resources project.yml
```

Expected: no matches for Share Extension notification implementation. Existing unrelated strings may appear only if they predate this feature; investigate any match before accepting it.

- [ ] **Step 6: Commit verification fixes if needed**

If verification required fixes:

```bash
git add <fixed-files>
git commit -m "Fix share extension verification issues"
```

If no fixes were needed, do not create an empty commit.

## Self-Review

Spec coverage:

- Share Sheet display name `翻译到译笺`: Task 3 and Task 6.
- Share Extension receives text/URL and extracts content: Task 2 and Task 3 activation rule.
- Extension panel translates text: Task 4.
- Copy button: Task 4.
- Favorite button: Task 4 and Task 5 pending operation consumption.
- Open WordScene with existing original and translation: Task 1 handoff, Task 4 URL, Task 5 app consumption.
- Localized strings: Task 6.
- No system notifications: Task 7 validation.

Placeholder scan:

- The plan contains concrete files, commands, expected outcomes, and code blocks for each implementation task.

Type consistency:

- `ShareExtensionHandoffRecord`, `ShareExtensionPendingOperation`, `ShareExtensionHandoffStore`, `SharedContentExtractor`, `AppRouteCoordinator`, and `ShareTranslationViewModel` names are used consistently across tasks.
