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
            .navigationBarTitleDisplayMode(.inline)
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
                .frame(maxWidth: .infinity, alignment: .center)
        case .translated(let record):
            languageSummary(record)
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

    private func languageSummary(_ record: ShareExtensionHandoffRecord) -> some View {
        Text("\(record.sourceLanguage.title) -> \(record.targetLanguage.title)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func sourceSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "原文"))
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 86, maxHeight: 150)
        }
    }

    private func translationSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "译文"))
                .font(.caption)
                .foregroundStyle(.secondary)
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
                Label(
                    viewModel.didCopy ? String(localized: "已复制") : String(localized: "复制译文"),
                    systemImage: "doc.on.doc"
                )
            }
            .disabled(!isTranslated)

            Button {
                viewModel.markFavorite()
            } label: {
                Label(
                    viewModel.didFavorite ? String(localized: "已收藏") : String(localized: "收藏"),
                    systemImage: viewModel.didFavorite ? "bookmark.fill" : "bookmark"
                )
            }
            .disabled(!isTranslated || viewModel.didFavorite)

            Button {
                if let url = viewModel.openURL() {
                    onOpen(url)
                }
            } label: {
                Label(String(localized: "打开"), systemImage: "arrow.up.forward.app")
            }
            .disabled(viewModel.openURL() == nil)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    private var isTranslated: Bool {
        if case .translated = viewModel.state {
            return true
        }
        return false
    }
}
