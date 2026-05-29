import Foundation

enum LocalPersistenceStoreError: Error, Equatable, LocalizedError {
    case unreadableDocument(key: String)

    var errorDescription: String? {
        switch self {
        case .unreadableDocument(let key):
            return "本地数据文件无法读取：\(key)。"
        }
    }
}
