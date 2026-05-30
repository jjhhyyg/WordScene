import XCTest
@testable import WordScene

final class SettingsErrorMessageFactoryTests: XCTestCase {
    func testImportExportMessageExplainsUnreadableLocalDocumentRecovery() {
        let message = SettingsErrorMessageFactory.importExportMessage(
            for: LocalPersistenceStoreError.unreadableDocument(key: "memoryLibrary")
        )

        XCTAssertTrue(message.contains("本地旧缓存无法读取"))
        XCTAssertTrue(message.contains("导出旧缓存原始备份"))
        XCTAssertTrue(message.contains("重置旧缓存文档"))
    }

    func testImportExportMessageExplainsUnsupportedLocalSchemaRecovery() {
        let message = SettingsErrorMessageFactory.importExportMessage(
            for: LocalPersistenceStoreError.unsupportedSchemaVersion(key: "memoryLibrary", version: 99)
        )

        XCTAssertTrue(message.contains("来自更新版本的 App"))
        XCTAssertTrue(message.contains("升级 WordScene"))
        XCTAssertTrue(message.contains("不要直接重置"))
    }

    func testImportExportMessageKeepsImportFileSchemaMessage() {
        XCTAssertEqual(
            SettingsErrorMessageFactory.importExportMessage(
                for: MemoryImportExportError.unsupportedSchemaVersion("99")
            ),
            "导入文件版本不支持，请升级 App 后重试。"
        )
    }
}
