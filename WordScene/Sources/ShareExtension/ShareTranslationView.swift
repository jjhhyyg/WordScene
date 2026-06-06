import SwiftUI

struct ShareTranslationView: View {
    @StateObject var viewModel: ShareTranslationViewModel
    let onCopy: (String) -> Void
    let onOpen: (URL) -> Void

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 42, height: 5)
                .padding(.top, 8)

            Text(String(localized: "翻译"))
                .font(.headline.weight(.semibold))

            languageControls

            content

            actionGroups

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            card {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
        case .ready(let sourceText):
            card {
                sourcePreview(sourceText)
            }
        case .translating(let sourceText):
            card {
                sourcePreview(sourceText)
                Divider()
                ProgressView(String(localized: "翻译中..."))
                    .frame(maxWidth: .infinity, minHeight: 72)
            }
        case .translated(let record):
            card {
                sourcePreview(record.sourceText, languageText: record.sourceLanguage.title)
                Divider()
                translationPreview(record.translatedText, languageText: record.targetLanguage.title)
            }
        case .failed(let message, let sourceText):
            card {
                if let sourceText {
                    sourcePreview(sourceText)
                    Divider()
                }
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("shareTranslation.error")
            }
        }
    }

    private var languageControls: some View {
        HStack(spacing: 10) {
            Picker(
                String(localized: "源语言", comment: "Picker label for source language."),
                selection: sourceLanguageBinding
            ) {
                ForEach(LanguageSelection.sourceOptions) { language in
                    Text(language.title).tag(language)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("shareTranslation.sourceLanguage")

            Image(systemName: "arrow.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker(
                String(localized: "目标语言", comment: "Picker label for target language."),
                selection: targetLanguageBinding
            ) {
                ForEach(LanguageSelection.targetOptions(excluding: viewModel.sourceLanguage)) { language in
                    Text(language.title).tag(language)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("shareTranslation.targetLanguage")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var sourceLanguageBinding: Binding<LanguageSelection> {
        Binding(
            get: { viewModel.sourceLanguage },
            set: { viewModel.updateSourceLanguage($0) }
        )
    }

    private var targetLanguageBinding: Binding<LanguageSelection> {
        Binding(
            get: { viewModel.targetLanguage },
            set: { viewModel.updateTargetLanguage($0) }
        )
    }

    private func sourcePreview(_ text: String, languageText: String = String(localized: "原文")) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(languageText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 60, maxHeight: 120)
        }
        .accessibilityIdentifier("shareTranslation.source")
    }

    private func translationPreview(_ text: String, languageText: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(languageText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
            ScrollView {
                Text(text)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 120, maxHeight: 260)
        }
        .accessibilityIdentifier("shareTranslation.translation")
    }

    private var actionGroups: some View {
        VStack(spacing: 14) {
            if viewModel.shouldShowTranslateButton {
                actionGroup {
                    ShareTranslationActionRow(
                        title: String(localized: "翻译", comment: "Manual translate action title in the share extension."),
                        systemImage: "translate",
                        isEnabled: viewModel.canTranslateCurrentText
                    ) {
                        Task {
                            await viewModel.translateCurrentText()
                        }
                    }
                }
            }

            actionGroup {
                ShareTranslationActionRow(
                    title: viewModel.didCopy ? String(localized: "已复制") : String(localized: "复制译文"),
                    systemImage: "doc.on.doc",
                    isEnabled: isTranslated
                ) {
                    if case .translated(let record) = viewModel.state {
                        onCopy(record.translatedText)
                        viewModel.markCopied()
                    }
                }

                Divider().padding(.leading, 54)

                ShareTranslationActionRow(
                    title: viewModel.didFavorite ? String(localized: "已收藏") : String(localized: "收藏"),
                    systemImage: viewModel.didFavorite ? "bookmark.fill" : "bookmark",
                    isEnabled: isTranslated && !viewModel.didFavorite
                ) {
                    viewModel.markFavorite()
                }
            }

            actionGroup {
                ShareTranslationActionRow(
                    title: String(localized: "打开"),
                    systemImage: "arrow.up.forward.app",
                    isEnabled: viewModel.openURL() != nil
                ) {
                    if let url = viewModel.openURL() {
                        onOpen(url)
                    }
                }
            }
        }
    }

    private var isTranslated: Bool {
        if case .translated = viewModel.state {
            return true
        }
        return false
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityIdentifier("shareTranslation.card")
    }

    private func actionGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ShareTranslationActionRow: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 10)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 58)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
    }
}
