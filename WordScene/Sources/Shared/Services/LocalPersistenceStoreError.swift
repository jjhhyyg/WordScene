import Foundation

enum LocalPersistenceStoreError: Error, Equatable, LocalizedError {
    case unreadableDocument(key: String)
    case unsupportedSchemaVersion(key: String, version: Int)

    var errorDescription: String? {
        switch self {
        case .unreadableDocument(let key):
            let format = String(localized: "本地数据文件无法读取：%@。", comment: "Local persistence error when a legacy data document cannot be read. The placeholder is the document key.")
            return String(format: format, key)
        case .unsupportedSchemaVersion(let key, let version):
            let format = String(localized: "本地数据文件版本不支持：%@ schema_version %lld。请升级 App 后重试。", comment: "Local persistence error when a legacy data document schema is too new. Placeholders are document key and schema version.")
            return String(format: format, key, Int64(version))
        }
    }
}
