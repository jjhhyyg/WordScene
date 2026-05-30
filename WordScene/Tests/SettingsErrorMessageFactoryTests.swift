import XCTest
@testable import WordScene

final class SettingsErrorMessageFactoryTests: XCTestCase {
    func testImportExportMessageExplainsUnreadableLocalDocumentRecovery() {
        let message = SettingsErrorMessageFactory.importExportMessage(
            for: LocalPersistenceStoreError.unreadableDocument(key: "memoryLibrary")
        )

        XCTAssertEqual(
            message,
            String(localized: "本地旧缓存无法读取。请先在“数据存储”导出旧缓存原始备份，再重置旧缓存文档。")
        )
    }

    func testImportExportMessageExplainsUnsupportedLocalSchemaRecovery() {
        let message = SettingsErrorMessageFactory.importExportMessage(
            for: LocalPersistenceStoreError.unsupportedSchemaVersion(key: "memoryLibrary", version: 99)
        )

        XCTAssertEqual(
            message,
            String(localized: "本地旧缓存来自更新版本的 App。请先升级 WordScene；不要直接重置，除非已经导出旧缓存原始备份。")
        )
    }

    func testImportExportMessageKeepsImportFileSchemaMessage() {
        XCTAssertEqual(
            SettingsErrorMessageFactory.importExportMessage(
                for: MemoryImportExportError.unsupportedSchemaVersion("99")
            ),
            String(localized: "导入文件版本不支持，请升级 App 后重试。")
        )
    }
}
