import XCTest
@testable import WordScene

final class AppLocalizationTests: XCTestCase {
    private let supportedLocalizationCodes = [
        "zh-Hans",
        "zh-Hant",
        "en",
        "es",
        "fr",
        "de",
        "pt",
        "it",
        "ru",
        "ja",
        "ko",
        "nl",
        "pl",
        "ar",
        "tr",
        "vi",
        "id",
        "hi"
    ]
    private let translatedLocalizationCodes = [
        "zh-Hant",
        "en",
        "es",
        "fr",
        "de",
        "pt",
        "it",
        "ru",
        "ja",
        "ko",
        "nl",
        "pl",
        "ar",
        "tr",
        "vi",
        "id",
        "hi"
    ]

    func testAppThemeOptionsIncludeIPhone17Finishes() {
        XCTAssertEqual(
            AppTheme.allCases.map(\.rawValue),
            [
                "auto",
                "light",
                "dark",
                "black",
                "mistBlue",
                "sage",
                "lavender",
                "silver",
                "cosmicOrange"
            ]
        )
        XCTAssertEqual(
            AppTheme.allCases.map(\.displayNameLocalizationKey),
            [
                "Auto",
                "Light",
                "Dark",
                "Black",
                "Mist Blue",
                "Sage",
                "Lavender",
                "Silver",
                "Cosmic Orange"
            ]
        )
        XCTAssertEqual(AppTheme.fromStorageValue("blue"), .auto)
        XCTAssertEqual(AppTheme.fromStorageValue("deepBlue"), .auto)
        XCTAssertEqual(AppTheme.fromStorageValue("white"), .auto)
        XCTAssertEqual(AppTheme.cosmicOrange.palette.primaryHex, "#D85E24")
        XCTAssertTrue(AppTheme.lavender.palette.usesCustomPalette)
    }

    func testAppThemeOptionsAreLocalizedInStringCatalog() throws {
        let catalog = try localizableStringCatalog()

        for theme in AppTheme.allCases {
            let localizations = catalog.strings[theme.displayNameLocalizationKey]?.localizations ?? [:]
            XCTAssertEqual(
                Set(localizations.keys),
                Set(supportedLocalizationCodes),
                "Missing localizations for theme option: \(theme.displayNameLocalizationKey)"
            )
        }

        let themesLocalizations = catalog.strings["Themes"]?.localizations ?? [:]
        XCTAssertEqual(Set(themesLocalizations.keys), Set(supportedLocalizationCodes))
    }

    func testStringCatalogIsPrimaryLocalizationSource() throws {
        let resourcesDirectory = try sourceResourcesDirectory()
        let catalogURL = resourcesDirectory.appendingPathComponent("Localizable.xcstrings")

        guard FileManager.default.fileExists(atPath: catalogURL.path) else {
            XCTFail("Missing primary string catalog at \(catalogURL.path)")
            return
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: resourcesDirectory.appendingPathComponent("zh-Hans.lproj/Localizable.strings").path))
        for languageCode in translatedLocalizationCodes {
            XCTAssertFalse(FileManager.default.fileExists(atPath: resourcesDirectory.appendingPathComponent("\(languageCode).lproj/Localizable.strings").path))
        }

        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(StringCatalogFixture.self, from: data)

        XCTAssertEqual(catalog.sourceLanguage, "zh-Hans")
        let translationLocalizations = catalog.strings["翻译"]?.localizations ?? [:]
        XCTAssertEqual(Set(translationLocalizations.keys), Set(supportedLocalizationCodes))
        XCTAssertEqual(translationLocalizations["en"]?.stringUnit?.value, "Translate")
        XCTAssertEqual(translationLocalizations["es"]?.stringUnit?.value, "Traducir")
        XCTAssertEqual(translationLocalizations["zh-Hant"]?.stringUnit?.value, "翻譯")
    }

    func testAppBundleAdvertisesSystemSelectableLanguages() throws {
        let bundle = Bundle.main

        for languageCode in translatedLocalizationCodes {
            XCTAssertTrue(bundle.localizations.contains(languageCode), "Missing selectable app language: \(languageCode)")
        }
    }

    func testLocalizedDisplayNamesAreAvailable() throws {
        let bundle = Bundle.main

        XCTAssertEqual(localizedDisplayName(languageCode: "en", bundle: bundle), "Word Scene")
        XCTAssertEqual(localizedDisplayName(languageCode: "es", bundle: bundle), "Escena de Palabras")
        XCTAssertEqual(localizedDisplayName(languageCode: "zh-Hant", bundle: bundle), "譯箋")
    }

    func testBuiltBundleResolvesLocalizedRuntimeStrings() throws {
        let bundle = Bundle.main

        XCTAssertEqual(localizedString("翻译", languageCode: "zh-Hans", bundle: bundle), "翻译")
        XCTAssertEqual(localizedString("翻译", languageCode: "en", bundle: bundle), "Translate")
        XCTAssertEqual(localizedString("翻译", languageCode: "es", bundle: bundle), "Traducir")
        XCTAssertEqual(localizedString("翻译", languageCode: "zh-Hant", bundle: bundle), "翻譯")
        XCTAssertEqual(localizedString("开始翻译", languageCode: "en", bundle: bundle), "Start Translation")
        XCTAssertEqual(localizedString("开始翻译", languageCode: "es", bundle: bundle), "Iniciar traducción")
        XCTAssertEqual(localizedString("设置", languageCode: "en", bundle: bundle), "Settings")
        XCTAssertEqual(localizedString("设置", languageCode: "es", bundle: bundle), "Ajustes")
    }

    func testBuiltBundleContainsCompiledLocalizationResources() throws {
        let bundle = Bundle.main

        for languageCode in supportedLocalizationCodes {
            let localizationDirectory = try XCTUnwrap(
                bundle.url(forResource: languageCode, withExtension: "lproj"),
                "Missing built \(languageCode).lproj resources"
            )
            XCTAssertTrue(FileManager.default.fileExists(atPath: localizationDirectory.appendingPathComponent("InfoPlist.strings").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: localizationDirectory.appendingPathComponent("Localizable.strings").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: localizationDirectory.appendingPathComponent("Localizable.stringsdict").path))
        }
    }

    func testSourceLocalizedStringKeysHaveCompleteCatalogCoverage() throws {
        let catalog = try localizableStringCatalog()
        let sourceKeys = try sourceLocalizedStringKeys()
        XCTAssertGreaterThan(sourceKeys.count, 200)

        for key in sourceKeys.sorted() {
            let localizations = try XCTUnwrap(catalog.strings[key]?.localizations, "Missing Localizable.xcstrings key for \(key)")
            XCTAssertEqual(Set(localizations.keys), Set(supportedLocalizationCodes), "Incomplete localizations for \(key)")
        }
    }

    func testSourceLocalizedStringsPreservePlaceholdersAndDoNotLeakChineseIntoNonCJKLanguages() throws {
        let catalog = try localizableStringCatalog()
        let sourceKeys = try sourceLocalizedStringKeys()
        let nonCJKLocalizationCodes = Set(supportedLocalizationCodes).subtracting(["zh-Hans", "zh-Hant", "ja", "ko"])

        for key in sourceKeys.sorted() {
            let expectedPlaceholders = placeholderTokens(in: key)
            let localizations = try XCTUnwrap(catalog.strings[key]?.localizations, "Missing Localizable.xcstrings key for \(key)")
            for languageCode in supportedLocalizationCodes {
                let localization = try XCTUnwrap(localizations[languageCode], "Missing \(languageCode) translation for \(key)")
                for value in localization.translatedValues {
                    XCTAssertEqual(
                        placeholderTokens(in: value),
                        expectedPlaceholders,
                        "Placeholder mismatch for \(key) in \(languageCode): \(value)"
                    )
                    if nonCJKLocalizationCodes.contains(languageCode) {
                        XCTAssertFalse(
                            value.containsCJKIdeograph,
                            "Likely untranslated Chinese fragment for \(key) in \(languageCode): \(value)"
                        )
                    }
                }
            }
        }
    }


    func testHighRiskDynamicStringsHaveEnglishAndSpanishTranslations() throws {
        let catalogURL = try sourceResourcesDirectory().appendingPathComponent("Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(StringCatalogFixture.self, from: data)
        let requiredKeys = [
            "请先在设置中保存 DeepSeek API Token。",
            "请输入需要翻译的文本。",
            "DeepSeek 没有返回可用译文。",
            "DeepSeek 输出被截断，请缩短文本后重试。",
            "DeepSeek 拒绝了该内容，请调整文本后重试。",
            "DeepSeek 暂时资源不足，请稍后重试。",
            "DeepSeek 返回无效响应。",
            "DeepSeek Token 无效或已过期。",
            "DeepSeek 请求失败：HTTP %lld。",
            "DeepSeek 响应超时，请稍后重试或缩短文本。",
            "读取系统凭据失败：%lld。",
            "系统凭据存储失败：%lld。",
            "翻译请求失败，请检查网络后重试。",
            "等待翻译",
            "翻译中",
            "已翻译",
            "需要处理",
            "粘贴 DeepSeek Token，保存后即可翻译。",
            "Token 已保存在本机。",
            "Token 可认证，但账户余额不可用。请检查 DeepSeek 余额。",
            "正在测试 DeepSeek 连接...",
            "连接成功，Token 已保存。",
            "删除 DeepSeek Token？",
            "删除后这台设备上的翻译 Token 会被移除，之后需要重新保存 Token 才能继续翻译。",
            "导出文件包含收藏内容，请妥善保管。",
            "备份或迁移收藏内容。",
            "正在准备导出文件...",
            "已准备 %lld 条记忆，请在系统面板中选择保存位置。%@",
            "已导出 %@。%@",
            "已取消导出，未写入文件。",
            "请选择要导入的 JSON 文件。",
            "已取消导入，未读取文件。",
            "导入文件不是有效的 WordScene JSON。",
            "导入文件版本不支持，请升级 App 后重试。",
            "导入文件校验失败，文件可能已被修改或损坏。",
            "导入导出失败，请稍后重试。",
            "未导入新内容，已跳过 %lld 条重复项。",
            "已导入 %lld 条，覆盖 %lld 条，跳过 %lld 条。",
            "覆盖重复项",
            "保留现有项",
            "旧缓存维护只处理早期本机文档，可先导出原始备份再重置。",
            "正在准备旧缓存原始备份...",
            "没有发现旧缓存文档，无需导出原始备份。",
            "已准备 %lld 个旧缓存文档，请在系统面板中选择保存位置。",
            "已导出旧缓存原始备份 %@。",
            "已取消旧缓存原始备份导出，未写入文件。",
            "没有旧缓存文档需要重置。",
            "已重置 %lld 个旧缓存文档。",
            "本地旧缓存无法读取。请先在“数据存储”导出旧缓存原始备份，再重置旧缓存文档。",
            "本地旧缓存来自更新版本的 App。请先升级 WordScene；不要直接重置，除非已经导出旧缓存原始备份。",
            "翻译到译笺",
            "原文",
            "译文",
            "翻译中...",
            "复制译文",
            "已复制",
            "收藏",
            "已收藏",
            "打开",
            "无法读取分享内容",
            "翻译失败，请稍后重试。",
            "收藏失败，请打开译笺后重试。",
            "翻译历史保存失败：%@",
            "收藏保存失败：%@"
        ]

        try assertCatalog(catalog, containsCompleteLocalizationsFor: requiredKeys)
    }

    func testPrimarySurfaceStringsHaveEnglishAndSpanishTranslations() throws {
        let catalogURL = try sourceResourcesDirectory().appendingPathComponent("Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(StringCatalogFixture.self, from: data)
        let requiredKeys = [
            "译笺",
            "正在加载翻译历史...",
            "正在加载收藏...",
            "删除全部翻译历史？",
            "删除全部收藏？",
            "此操作会清空本机历史，并通过同步删除其他设备上的历史记录。",
            "此操作会删除全部收藏，并同步到其他设备。",
            "无法读取翻译历史",
            "无法读取收藏",
            "还没有翻译历史",
            "还没有收藏",
            "没有找到匹配内容",
            "没有星标收藏",
            "完成翻译后，最近 100 条记录会显示在这里。",
            "可以缩短关键词，或尝试拼音、汉字、语言等不同搜索方式。",
            "翻译历史 %lld 条",
            "已收藏 %lld 条",
            "%lld 个结果",
            "收藏 %lld",
            "%@ 到 %@",
            "搜索翻译历史",
            "搜索单词、短语、句子",
            "清空搜索",
            "手动新增",
            "编辑收藏",
            "原文",
            "译文",
            "备注",
            "可选",
            "保存到收藏",
            "删除历史",
            "历史",
            "编辑收藏",
            "删除收藏",
            "数据存储",
            "隐私",
            "关于",
            "导入导出",
            "翻译服务",
            "使用 iCloud 同步",
            "收藏和历史会在登录同一 Apple ID 的设备间同步。",
            "收藏和历史只保存在这台设备。",
            "重启 App 后生效，已有内容不会被删除。",
            "iCloud 同步已开启。",
            "当前只保存在本机。"
        ]

        try assertCatalog(catalog, containsCompleteLocalizationsFor: requiredKeys)
    }

    func testTranslationSurfaceStringsHaveEnglishAndSpanishTranslations() throws {
        let catalogURL = try sourceResourcesDirectory().appendingPathComponent("Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(StringCatalogFixture.self, from: data)
        let requiredKeys = [
            "开始翻译",
            "源语言",
            "目标语言",
            "清空输入",
            "输入要翻译的文本",
            "待翻译文本",
            "交换翻译方向",
            "输入",
            "输入字符数 %lld",
            "清空输入和译文",
            "输入要翻译的单词、短语或句子",
            "结果",
            "还没有翻译结果",
            "配置 DeepSeek Token 后，输入内容即可开始翻译。",
            "正在翻译...",
            "译文",
            "已复制",
            "译文，点击复制",
            "翻译失败",
            "translation.result.savedToMemory",
            "translation.result.saveToMemory",
            "translation.result.removeFromMemory.accessibility",
            "translation.result.saveToMemory.accessibility",
            "翻译历史读取失败：%@",
            "收藏数据读取失败：%@",
            "收藏保存失败：%@",
            "译文已生成，但翻译历史保存失败：%@"
        ]

        try assertCatalog(catalog, containsCompleteLocalizationsFor: requiredKeys)
    }

    func testSystemStatusStringsHaveEnglishAndSpanishTranslations() throws {
        let catalogURL = try sourceResourcesDirectory().appendingPathComponent("Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(StringCatalogFixture.self, from: data)
        let requiredKeys = [
            "Core Data 已启用",
            "兼容存储模式",
            "本机数据正在写入主存储。",
            "主存储初始化失败，当前使用兼容存储：%@",
            "iCloud 同步已配置",
            "仅本机存储",
            "同步不可用",
            "已配置通过 %@ 写入 iCloud 私有数据库。同步不是实时承诺，具体时间取决于系统、网络和 Apple ID 状态。",
            "当前进程没有可用的 CloudKit entitlement，数据仍可本机使用，但不会通过 iCloud 同步。",
            "iCloud 同步存储初始化失败，已切换为仅本机存储。数据仍可本机使用，但不会通过 iCloud 同步：%@",
            "主存储初始化失败，当前无法使用 iCloud 同步：%@",
            "网络状态检测中",
            "网络可用",
            "网络不可用",
            "正在检测网络状态。本机收藏和搜索仍可使用。",
            "当前处于低数据模式，同步和翻译可能由系统延后。本机收藏和搜索不受影响。",
            "当前可能使用蜂窝或热点网络，同步和翻译可能产生流量。本机收藏和搜索不受影响。",
            "网络可用于翻译请求和 iCloud 同步。本机数据仍会先写入本地存储。",
            "当前离线。翻译请求和 iCloud 同步会暂停，但本机收藏、搜索和删除仍可使用。",
            "准备 iCloud 同步",
            "从 iCloud 导入",
            "向 iCloud 上传",
            "当前为仅本机存储，不会收到 iCloud 同步事件。",
            "同步不可用：%@",
            "没有同步事件",
            "等待 iCloud 同步事件",
            "最近同步成功",
            "同步出现错误",
            "还没有收到 iCloud 同步事件。完成签名设备测试前，这不能证明多端已同步。",
            "%@中，开始于 %@。",
            "%@已完成：%@。",
            "%@失败：%@。%@",
            "已同步云端",
            "同步未完成",
            "已保存",
            "失败原因",
            "恢复建议",
            "详细错误",
            "底层错误",
            "部分失败 %@",
            "本地数据文件无法读取：%@。",
            "本地数据文件版本不支持：%@ schema_version %lld。请升级 App 后重试。"
        ]

        try assertCatalog(catalog, containsCompleteLocalizationsFor: requiredKeys)
    }

    func testCountStringsUsePluralVariations() throws {
        let catalogURL = try sourceResourcesDirectory().appendingPathComponent("Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(StringCatalogFixture.self, from: data)
        let pluralKeys = [
            "%lld 个结果",
            "翻译历史 %lld 条",
            "收藏 %lld",
            "输入字符数 %lld",
            "未导入新内容，已跳过 %lld 条重复项。",
            "已收藏 %lld 条",
            "已重置 %lld 个旧缓存文档。",
            "已准备 %lld 个旧缓存文档，请在系统面板中选择保存位置。",
            "已准备 %lld 条记忆，请在系统面板中选择保存位置。%@"
        ]

        for key in pluralKeys {
            let localizations = try XCTUnwrap(catalog.strings[key]?.localizations, "Missing plural string catalog key: \(key)")
            for language in supportedLocalizationCodes {
                let plural = try XCTUnwrap(localizations[language]?.variations?.plural, "Missing plural variations for \(key) in \(language)")
                XCTAssertNotNil(plural["one"]?.stringUnit.value, "Missing singular plural variation for \(key) in \(language)")
                XCTAssertNotNil(plural["other"]?.stringUnit.value, "Missing other plural variation for \(key) in \(language)")
            }
        }

        XCTAssertNil(catalog.strings["翻译历史 1 条"])
        XCTAssertNil(catalog.strings["1 个结果"])
        XCTAssertNil(catalog.strings["已收藏 1 条"])
        XCTAssertNil(catalog.strings["收藏 1"])
    }

    func testSettingsDeepSeekTokenDeleteUsesConfirmationDialog() throws {
        let source = try settingsViewSource()

        XCTAssertTrue(source.contains("@State private var isConfirmingDeepSeekTokenDeletion = false"))
        XCTAssertTrue(source.contains("isPresented: $isConfirmingDeepSeekTokenDeletion"))
        XCTAssertTrue(source.contains("confirmDeepSeekTokenDeletion()"))
        XCTAssertFalse(source.contains("Button(role: .destructive) {\n            deleteToken()"))
    }

    func testMobileSettingsDoesNotShowAppInfoCard() throws {
        let source = try settingsViewSource()

        let mobileBodyRange = try XCTUnwrap(source.range(of: "private var mobileSettingsBody: some View"))
        let macBodyRange = try XCTUnwrap(source.range(of: "#if os(macOS)\n    private var macSettingsBody: some View"))
        let mobileBody = String(source[mobileBodyRange.lowerBound..<macBodyRange.lowerBound])

        XCTAssertFalse(mobileBody.contains("appInfoCard"))
    }

    private func assertCatalog(
        _ catalog: StringCatalogFixture,
        containsCompleteLocalizationsFor requiredKeys: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for key in requiredKeys {
            let localizations = try XCTUnwrap(catalog.strings[key]?.localizations, "Missing string catalog key: \(key)")
            for language in supportedLocalizationCodes {
                let localization = try XCTUnwrap(localizations[language], "Missing \(language) translation for \(key)")
                let values = localization.translatedValues
                XCTAssertFalse(values.isEmpty, "Missing \(language) translation for \(key)", file: file, line: line)
                for value in values {
                    XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, file: file, line: line)
                }
            }
        }
    }

    private func localizedDisplayName(languageCode: String, bundle: Bundle) -> String? {
        guard let path = bundle.path(forResource: languageCode, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else {
            return nil
        }

        return localizedBundle.localizedString(forKey: "CFBundleDisplayName", value: nil, table: "InfoPlist")
    }

    private func localizedString(_ key: String, languageCode: String, bundle: Bundle) -> String? {
        guard let path = bundle.path(forResource: languageCode, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else {
            return nil
        }

        return localizedBundle.localizedString(forKey: key, value: nil, table: nil)
    }

    private func localizableStringCatalog() throws -> StringCatalogFixture {
        let catalogURL = try sourceResourcesDirectory().appendingPathComponent("Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        return try JSONDecoder().decode(StringCatalogFixture.self, from: data)
    }

    private func sourceLocalizedStringKeys() throws -> Set<String> {
        let sourceRoot = try projectRootDirectory().appendingPathComponent("WordScene/Sources/Shared", isDirectory: true)
        let swiftFiles = try FileManager.default.subpathsOfDirectory(atPath: sourceRoot.path)
            .filter { $0.hasSuffix(".swift") }
            .map { sourceRoot.appendingPathComponent($0) }
        let patterns = [
            #"String\s*\(\s*localized:\s*"((?:[^"\\]|\\.)*)""#,
            #"\b(?:Text|Button|Label|Picker|Section|Toggle|TextField|SecureField|Menu|navigationTitle)\(\s*"((?:[^"\\]|\\.)*)""#,
            #"\.accessibilityLabel\(\s*"((?:[^"\\]|\\.)*)""#
        ]
        let regexes = try patterns.map { try NSRegularExpression(pattern: $0) }
        var keys = Set<String>()
        let excludedVerbatimKeys = Set(["sk-..."])

        for fileURL in swiftFiles {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let nsRange = NSRange(source.startIndex..<source.endIndex, in: source)
            for regex in regexes {
                for match in regex.matches(in: source, range: nsRange) {
                    guard let keyRange = Range(match.range(at: 1), in: source) else {
                        continue
                    }
                    let rawKey = String(source[keyRange])
                    guard !rawKey.contains(#"\("#) else {
                        continue
                    }
                    let keyData = Data("\"\(rawKey)\"".utf8)
                    let key = try JSONDecoder().decode(String.self, from: keyData)
                    guard !excludedVerbatimKeys.contains(key) else {
                        continue
                    }
                    keys.insert(key)
                }
            }
        }

        return keys
    }

    private func placeholderTokens(in string: String) -> [String] {
        let pattern = #"%(?:\d+\$)?(?:@|lld|ld|d|f|s|u)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let nsRange = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.matches(in: string, range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: string) else {
                return nil
            }
            return String(string[range])
        }.sorted()
    }

    private func sourceResourcesDirectory() throws -> URL {
        try projectRootDirectory().appendingPathComponent("WordScene/Resources", isDirectory: true)
    }

    private func settingsViewSource() throws -> String {
        let sourceURL = try projectRootDirectory().appendingPathComponent("WordScene/Sources/Shared/Features/Settings/SettingsView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func projectRootDirectory() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while !FileManager.default.fileExists(atPath: url.appendingPathComponent("project.yml").path) {
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path {
                throw XCTSkip("Unable to locate WordScene project root from \(#filePath)")
            }
            url = parent
        }
        return url
    }
}

private struct StringCatalogFixture: Decodable {
    let sourceLanguage: String
    let strings: [String: StringCatalogEntryFixture]
}

private struct StringCatalogEntryFixture: Decodable {
    let localizations: [String: StringCatalogLocalizationFixture]?
}

private struct StringCatalogLocalizationFixture: Decodable {
    let stringUnit: StringCatalogStringUnitFixture?
    let variations: StringCatalogVariationsFixture?

    var translatedValues: [String] {
        var values: [String] = []
        if let stringUnit {
            values.append(stringUnit.value)
        }
        if let plural = variations?.plural {
            values.append(contentsOf: plural.values.compactMap { $0.stringUnit.value })
        }
        return values
    }
}

private struct StringCatalogVariationsFixture: Decodable {
    let plural: [String: StringCatalogVariationFixture]?
}

private struct StringCatalogVariationFixture: Decodable {
    let stringUnit: StringCatalogStringUnitFixture
}

private struct StringCatalogStringUnitFixture: Decodable {
    let value: String
}

private extension String {
    var containsCJKIdeograph: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        }
    }
}
