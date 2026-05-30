import Foundation

enum LocalPersistenceStoreError: Error, Equatable, LocalizedError {
    case unreadableDocument(key: String)
    case unsupportedSchemaVersion(key: String, version: Int)

    var errorDescription: String? {
        switch self {
        case .unreadableDocument(let key):
            return "本地数据文件无法读取：\(key)。"
        case .unsupportedSchemaVersion(let key, let version):
            return "本地数据文件版本不支持：\(key) schema_version \(version)。请升级 App 后重试。"
        }
    }
}
