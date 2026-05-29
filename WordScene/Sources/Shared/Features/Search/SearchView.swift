import SwiftUI

struct SearchView: View {
    @State private var query = ""

    var body: some View {
        VStack {
            if query.isEmpty {
                ContentUnavailableView(
                    "搜索收藏",
                    systemImage: "magnifyingglass",
                    description: Text("支持原文、译文、标签、分类和中文拼音搜索。")
                )
            } else {
                ContentUnavailableView(
                    "没有找到匹配内容",
                    systemImage: "magnifyingglass",
                    description: Text("可以缩短关键词，或尝试拼音、汉字、标签等不同搜索方式。")
                )
            }
        }
        .navigationTitle("搜索")
        .searchable(text: $query, prompt: "搜索单词、短语、句子")
    }
}
