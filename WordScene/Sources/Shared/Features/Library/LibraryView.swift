import SwiftUI

struct LibraryView: View {
    var body: some View {
        ContentUnavailableView(
            "还没有收藏",
            systemImage: "bookmark",
            description: Text("翻译后点收藏，将单词、短语或句子保存为可学习条目。")
        )
        .navigationTitle("收藏")
    }
}

#Preview("Library") {
    NavigationStack {
        LibraryView()
    }
}
