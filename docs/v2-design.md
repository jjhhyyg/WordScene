# 单词、短语、句子记忆软件 v2 设计方案

## 1. 文档目标

本文档在 `v1-design.md` 基础上，把第一版产品方向细化为可开工的产品、前端、客户端服务层、数据、同步、检索、LLM Provider、导入导出和验收规格。

本项目第一版不建议自建服务端。所谓“后端设计”在本阶段主要指 App 内部的业务服务层、数据访问层、本地搜索服务、CloudKit 同步层和第三方大模型 API 适配层。除非后续要做账号体系、共享词库、团队协作或自建翻译代理，否则第一版自建服务器只会增加隐私、成本和审核复杂度。

## 2. 产品定位

本软件第一版定位为 Apple 生态内的个人多语种翻译收藏与记忆资料库。翻译只是入口，核心价值是把用户认为值得长期保存的单词、短语、句子沉淀为结构化、可离线查看、可快速检索、可跨设备同步的学习条目。

第一版优先支持中文、英文、西班牙语，但底层数据模型和 LLM Provider 抽象不能被这三个语种锁死。

第一版核心能力：

- 用户自行配置 DeepSeek API Token。
- DeepSeek 第一版固定使用 `deepseek-v4-flash` 非思考模式。
- DeepSeek base URL 固定为 `https://api.deepseek.com`，不允许用户自定义。
- 代码层提供 DeepSeek Provider 和 OpenAI-compatible 通用 Provider 适配器。
- 支持中、英、西之间翻译、收藏、自动分类。
- 收藏项以“可学习条目”为单位。
- 支持本地离线查看和本地快速搜索。
- 中文拼音搜索进入第一版。
- 标签由 LLM 给出初步结果，用户可删除和修改。
- 使用 Core Data + CloudKit 同步结构化数据。
- 使用独立本地搜索索引做全文检索。
- 支持删除后的多端同步删除。
- 支持 JSON 导入导出，用于用户主动备份和恢复。
- Release build 保留匿名崩溃日志能力，并另写隐私说明；第一版预留用户选择接口。
- iOS 26 及以上默认采用系统 Liquid Glass/液态玻璃视觉能力。
- iOS、iPadOS、macOS 共享核心能力，但界面按平台优化。

第一版明确不做：

- 不允许用户手动编辑翻译结果。
- 不做复习计划、遗忘曲线、每日任务。
- 不做发音、TTS、音标展示，但预留字段。
- 不做收藏项智能合并。
- 不自建用户账号系统。
- 不把 CloudKit 当主检索引擎。
- 不把每次搜索交给大模型。
- 不允许自定义 DeepSeek base URL，避免第三方中转站带来的中间人攻击和 Token 泄露风险。
- 不支持加密导出。
- 第一版不做 Face ID / Touch ID 应用锁。

## 3. 总体架构

### 3.1 架构图

```text
SwiftUI UI Layer
  -> ViewModel / State
  -> Use Case Layer
  -> Service Layer
      -> TranslationService
      -> ClassificationService
      -> SearchService
      -> ImportExportService
      -> SyncStateService
      -> CredentialService
  -> Repository Layer
      -> CoreDataRepository
      -> SearchIndexRepository
      -> ProviderConfigRepository
  -> Infrastructure Layer
      -> NSPersistentCloudKitContainer
      -> Independent SQLite FTS Store
      -> Keychain
      -> URLSession LLM Provider
      -> File Import / Export
```

### 3.2 关键原则

- Core Data 是业务数据权威来源。
- CloudKit 只负责结构化数据同步，不负责主搜索。
- 独立 SQLite FTS store 负责本地搜索，可重建，不同步。
- Keychain 负责 API Token，不进入 CloudKit，不进入导出文件。
- LLM 输出必须结构化、校验、容错。
- UI 不直接调用网络或数据库，必须通过 Use Case / Service。

### 3.3 为什么不直接在 Core Data SQLite 里建 FTS

`NSPersistentCloudKitContainer` 管理 Core Data 的 SQLite store。第一版不应直接在 Core Data 管理的 SQLite 文件里手工创建 FTS 表、trigger 或外部索引。

推荐方案：

```text
Core Data store
  - TranslationItem
  - TranslationAlternative
  - Classification
  - ProviderConfigPublic
  - Sync metadata

Independent Search SQLite store
  - FTS virtual table
  - Search metadata table
  - Rebuild marker
```

这样做的好处：

- 不污染 Core Data store。
- 不影响 CloudKit 同步。
- 搜索索引损坏时可以从 Core Data 重建。
- 后续替换为更强搜索引擎或向量索引时影响范围小。

## 4. 前端设计

### 4.1 设计风格

本产品不适合儿童教育或游戏化视觉。更合适的方向是 Productivity Tool + Knowledge Base：

- Apple 原生风格优先。
- iOS 26 及以上默认采用系统 Liquid Glass/液态玻璃；iOS 25 及以下保持系统原生样式。
- 信息密度适中。
- 搜索优先。
- 使用系统字体。
- 主色克制，功能色清晰。
- 不使用夸张渐变、卡通字体、重装饰卡片。
- 不手写仿 Liquid Glass 的自定义毛玻璃效果；优先使用 SwiftUI 标准组件和 Apple 提供的 Liquid Glass API。
- 液态玻璃效果不得影响文本可读性；需要尊重系统的辅助功能设置，例如增加对比度、减少透明度、减少动态效果。

建议视觉关键词：

```text
原生
安静
清晰
搜索优先
知识库
高可读性
低干扰
系统液态玻璃
```

Liquid Glass 使用边界：

- SwiftUI 标准导航、工具栏、Tab、sheet、popover 等系统组件在 iOS 26+ 下优先使用系统默认 Liquid Glass 行为。
- 自定义按钮、筛选 chip、搜索工具条等确有需要时，才使用 Apple 官方 Liquid Glass API。
- 列表正文、长句译文、候选译文说明等阅读密集区域不主动叠加强玻璃材质。
- 不为了视觉效果牺牲搜索、输入和译文阅读效率。

### 4.2 主要导航

第一版建议使用 4 个一级入口：

```text
翻译
收藏
搜索
设置
```

iPhone 上可使用 TabView。iPadOS 和 macOS 上建议使用 NavigationSplitView。

### 4.3 iOS 界面

iOS 重点是快速输入、快速翻译、快速收藏、快速搜索。

翻译页：

- 顶部为 source / target 语言选择器。
- 中间为输入框。
- 下方为翻译按钮。
- 结果区显示主译文、候选译文、分类标签。
- 收藏按钮固定在结果区明显位置。

收藏页：

- 默认按收藏时间倒序。
- 支持语言方向 chip 过滤。
- 支持内容类型过滤。
- 列表项显示原文、主译文、方向、标签、收藏时间。

搜索页：

- 搜索框常驻顶部。
- 输入时 debounce 查询。
- 支持搜索建议。
- 无结果时显示可行动建议。

设置页：

- 使用 SwiftUI `Form` 和 `Section`。
- DeepSeek API Token 单独一节。
- DeepSeek 模型固定显示为 `deepseek-v4-flash`，base URL 固定显示为 `https://api.deepseek.com`，不可编辑。
- API 连通性测试单独一行，调用 `GET https://api.deepseek.com/user/balance`，根据 `is_available` 判断 Token 是否可用于 API 调用。
- 导入导出、安全设置、匿名崩溃日志设置分组展示。
- Debug build 可显示 RawAPIResponse 调试开关；Release build 不显示也不保存原始响应。

### 4.4 iPadOS 界面

iPadOS 重点是并排阅读和对比。

建议结构：

```text
Sidebar: 收藏分类 / 搜索入口 / 设置入口
Content: 搜索结果或收藏列表
Detail: 条目详情 / 翻译结果
```

要求：

- 支持横屏三栏。
- 支持键盘快捷键。
- 支持焦点状态。
- 长句详情页要优先保证阅读宽度，不要挤压成窄列。

### 4.5 macOS 界面

macOS 重点是高效检索、批量查看、导入导出、快捷键。

建议结构：

```text
Sidebar: 语言方向、标签、内容类型
List: 搜索结果 / 收藏列表
Detail: 条目详情
Toolbar: 搜索框、过滤器、导入、导出、设置
Menu: File / Edit / View / Window / Help
```

快捷键建议：

```text
Command+N: 新建翻译
Command+F: 聚焦搜索
Command+S: 收藏当前结果
Command+Delete: 删除当前条目
Command+,: 打开设置
```

### 4.6 状态设计

必须覆盖以下状态：

- 首次使用空状态。
- 没有收藏的空状态。
- 搜索无结果状态。
- 翻译加载状态。
- API Token 未配置状态。
- API 请求失败状态。
- iCloud 不可用状态。
- 离线状态。
- 导入成功、导入部分失败、导入完全失败状态。

示例：

```text
没有收藏：
  还没有收藏任何内容
  先翻译一个单词、短语或句子，然后点收藏保存到资料库。

搜索无结果：
  没有找到匹配内容
  可以尝试去掉重音符号、缩短关键词，或切换语言方向过滤。

Token 未配置：
  需要配置 DeepSeek API Token 后才能翻译
  已收藏内容仍可离线查看和搜索。
```

### 4.7 可访问性

SwiftUI 实现必须满足：

- 图标按钮必须有 `.accessibilityLabel`。
- 可点击图片不能只用 `Image`，应使用 `Button`。
- 表单输入必须有明确 label。
- 错误状态不能只依赖颜色。
- 支持 Dynamic Type。
- 动画必须尊重 `accessibilityReduceMotion`。
- macOS 和 iPadOS 需要键盘导航与可见 focus state。

## 5. 客户端服务层设计

### 5.1 Use Case 划分

建议 Use Case：

```text
TranslateTextUseCase
FavoriteTranslationUseCase
SearchItemsUseCase
DeleteItemUseCase
ExportLibraryUseCase
ImportLibraryUseCase
ValidateProviderCredentialUseCase
RebuildSearchIndexUseCase
```

### 5.2 Service 划分

```text
TranslationService
  - 组装请求
  - 调用 LLMProvider
  - 解析结构化结果
  - 做本地校验

ClassificationService
  - 使用 LLM 输出分类
  - 规范化标签
  - 限制标签数量

SearchService
  - 查询 FTS store
  - 合并过滤条件
  - 计算排序分数
  - 回查 Core Data 条目
  - 构建中文拼音查询扩展

ImportExportService
  - 生成 JSON 导出文件
  - 校验导入文件 schema
  - 处理重复项
  - 触发索引重建

CredentialService
  - Keychain 读写
  - Token 校验
  - 不允许 Token 进入 CloudKit 或导出文件

SyncStateService
  - 观察 CloudKit 同步状态
  - 暴露 iCloud 可用性
  - 暴露最近同步时间

CrashLogConsentService
  - 保存用户是否允许匿名崩溃日志上传
  - 第一版只预留设置项和隐私说明
  - 后续发布后再接入自动上传链路
```

## 6. 数据模型设计

### 6.1 Core Data 实体总览

第一版 Core Data 实体：

```text
TranslationItem
TranslationAlternative
ClassificationRecord
ProviderConfigPublic
RawAPIResponse
DeletionTombstone
```

不进入 Core Data 或不进入 CloudKit 的内容：

- Keychain Token。
- 独立 SearchIndex。
- 临时请求状态。
- 可重建缓存。

### 6.2 TranslationItem

```text
id: UUID
sourceText: String
sourceLanguageMode: String
detectedSourceLanguage: String?
confirmedSourceLanguage: String
targetLanguage: String
translatedText: String
contentType: String
direction: String
provider: String
modelName: String
createdAt: Date
updatedAt: Date
favoritedAt: Date
lastViewedAt: Date?
deletedAt: Date?
isDeleted: Bool
duplicateKey: String
note: String?
userEdited: Bool
rawResponseStoragePolicy: String
rawResponseID: UUID?
phoneticText: String?
pronunciationRef: String?
ttsAudioRef: String?
schemaVersion: Int
```

约束：

- `id` 由客户端生成。
- `duplicateKey` 必须唯一索引，但软删除项是否参与重复判断需明确。第一版建议软删除项不参与默认重复提示。
- `direction` 不由 LLM 决定，必须由本地计算。
- `confirmedSourceLanguage != targetLanguage`。
- `schemaVersion` 用于未来迁移。
- `phoneticText` 第一版不展示发音，但可保存中文拼音或未来音标信息；真正用于搜索的拼音字段仍以独立 SearchIndex 为准。

### 6.3 TranslationAlternative

```text
id: UUID
itemID: UUID
text: String
explanation: String?
partOfSpeech: String?
register: String
confidence: Double?
sortOrder: Int
createdAt: Date
```

第一版覆盖旧条目时，候选译文采用整组替换，不做合并。

### 6.4 ClassificationRecord

Core Data + CloudKit 对数组字段要谨慎。第一版建议把数组型分类字段存为 JSON string，同时同步一份可展示文本。

```text
id: UUID
itemID: UUID
topic: String?
subtopic: String?
tagsJSON: String
tagsDisplayText: String
userTagsJSON: String?
tagsLastEditedAt: Date?
tagsEditedByUser: Bool
usageScenarioJSON: String
grammarFocusJSON: String
semanticGroup: String?
difficulty: String
confidence: Double?
provider: String
modelName: String
createdAt: Date
manuallyOverridden: Bool
reasonSummary: String?
schemaVersion: Int
```

说明：

- `tagsJSON` 用于完整恢复。
- `tagsDisplayText` 用于列表展示和搜索索引构建。
- `userTagsJSON` 用于保存用户修改后的标签；如果存在，以用户标签作为展示和搜索权威。
- `tagsEditedByUser` 为 true 时，后续重新翻译或覆盖操作不得静默覆盖用户标签，必须提示。
- 第一版不依赖 CloudKit 对 tags 做服务端过滤。
- 后续如果需要标签统计和独立管理，再拆出 `Tag` 实体。

### 6.5 ProviderConfigPublic 与 ProviderSecret

Provider 配置必须拆成可同步与不可同步两部分。

可同步：

```text
ProviderConfigPublic
  id: UUID
  provider: String
  displayName: String
  baseURL: String
  defaultModel: String
  isBaseURLUserEditable: Bool
  enabled: Bool
  createdAt: Date
  updatedAt: Date
```

不可同步，仅 Keychain / 本地状态：

```text
ProviderSecret
  provider: String
  apiKeyKeychainRef: String
  credentialState: valid / invalid / untested
  lastValidatedAt: Date?
```

原则：

- `apiKeyKeychainRef` 不同步。
- API Token 不导出。
- 新设备同步到 ProviderConfigPublic 后，仍需用户在该设备配置 Token。
- DeepSeek 的 `baseURL` 固定为 `https://api.deepseek.com`，`isBaseURLUserEditable = false`。
- OpenAI-compatible 通用适配器可在未来允许自定义 base URL，但第一版 UI 不开放给 DeepSeek，且必须明显标识第三方服务风险。

### 6.6 RawAPIResponse

RawAPIResponse 只允许 Debug build 保存，Release build 不保存、不同步、不导出。

```text
id: UUID
itemID: UUID?
provider: String
modelName: String
requestPayloadRedacted: String?
responsePayload: String
createdAt: Date
environment: String
schemaVersion: Int
```

要求：

- 仅 Debug build 编译启用。
- request payload 必须脱敏。
- 不能保存 Authorization header。
- 用户删除条目时，关联 RawAPIResponse 应同步软删除或本地删除。
- 默认不进入 CloudKit。

### 6.7 DeletionTombstone

用于跨设备删除和未来冲突处理。

```text
id: UUID
entityName: String
entityID: UUID
deletedAt: Date
sourceDeviceID: String
reason: String?
```

第一版可以只依赖 `isDeleted + deletedAt`，但建议保留 tombstone 设计，便于导入导出和冲突排查。

## 7. 本地搜索设计

### 7.1 搜索 store

使用独立 SQLite 文件，例如：

```text
Application Support/SearchIndex/search.sqlite
```

建议表：

```sql
CREATE VIRTUAL TABLE item_fts USING fts5(
  item_id UNINDEXED,
  source_text,
  translated_text,
  normalized_source,
  normalized_translated,
  accent_folded,
  source_pinyin_full,
  source_pinyin_compact,
  source_pinyin_initials,
  translated_pinyin_full,
  translated_pinyin_compact,
  translated_pinyin_initials,
  tags,
  classification,
  search_blob,
  tokenize = 'unicode61 remove_diacritics 2'
);

CREATE TABLE item_search_meta (
  item_id TEXT PRIMARY KEY,
  updated_at TEXT NOT NULL,
  content_hash TEXT NOT NULL
);
```

注意：

- FTS store 可重建，不同步。
- 搜索结果必须回查 Core Data，避免返回已删除或已过期条目。
- CloudKit 同步完成后，应异步更新索引。

### 7.2 文本归一化

```text
英文：
  lowercase
  trim
  collapse whitespace

西班牙语：
  lowercase
  remove diacritics for auxiliary field
  keep original text for display

中文：
  keep original
  remove extra whitespace
  generate full pinyin
  generate pinyin initials
  keep original Chinese text for display
```

第一版中文拼音检索必须实现。要求：

- 对 `sourceText` 和 `translatedText` 中的中文内容生成全拼字段。
- 同时生成拼音首字母字段。
- 用户搜索汉字时匹配汉字字段。
- 用户搜索拼音时匹配拼音字段。
- 用户使用英文或西班牙语搜索时，也应同时匹配条目中的中文原文、中文译文和对应拼音字段。
- 多音字第一版可采用系统或第三方拼音库默认读音；不要承诺语境级多音字完美消歧。

### 7.2.1 拼音转换方案

第一版确定使用 Apple 原生字符串转换能力，不引入第三方拼音库。

实现方案：

```text
PinyinTransliterator 协议
  -> AppleSystemPinyinTransliterator
      - 使用 StringTransform.mandarinToLatin 或 CFStringTransform
      - 再 stripDiacritics
      - lowercase
      - collapse whitespace
  -> FutureCustomPinyinTransliterator
      - 预留给未来多音字词典或第三方库
```

原因：

- Apple 原生能力无需额外依赖，适合 iOS、iPadOS、macOS 第一版。
- 拼音只是搜索召回字段，不是教学发音功能，第一版不需要追求语境级多音字完美。
- 第三方 Swift 拼音库多为 CocoaPods/Carthage 时代项目，第一版不引入这类依赖风险。
- 用协议隔离实现，未来如果发现系统转换质量不足，可以替换为自研词典或第三方库，不影响 SearchService。

验收重点：

- 生成 `fullPinyinWithSpaces`，如 `yi ge`。
- 生成 `fullPinyinCompact`，如 `yige`。
- 生成 `pinyinInitials`，如 `yg`。
- 搜索时对 query 也做同样归一化。
- 多音字错误只作为第一版已知限制记录，不阻塞上线。

示例：

```text
条目文本：一个
索引字段：
  source_text: 一个
  source_pinyin_full: yi ge
  source_pinyin_initials: yg

查询：
  一个 -> 命中
  yi ge -> 命中
  yige -> 应通过无空格归一化命中
  yg -> 可命中但排序低于完整拼音
```

### 7.3 搜索 ranking

搜索结果排序建议：

```text
100 原文精确匹配
90  原文前缀匹配
80  译文精确匹配
70  译文前缀匹配
60  标签精确匹配
50  分类/场景匹配
45  中文拼音完整匹配
42  中文拼音首字母匹配
40  FTS 全文匹配
10  最近查看加权
5   最近收藏加权
```

同分排序：

```text
lastViewedAt desc
favoritedAt desc
createdAt desc
```

### 7.4 搜索过滤

第一版过滤条件：

- direction
- sourceLanguage
- targetLanguage
- contentType
- topic
- tag
- createdAt / favoritedAt 范围

### 7.5 搜索体验验收

必须满足：

- 收藏 5000 条以内，本地搜索感知上接近即时。
- 搜索 `cancion` 能命中 `canción`。
- 搜索 `一个`、`yi ge`、`yige` 都能命中包含“一个”的条目。
- 搜索标签能命中对应条目。
- 删除条目后搜索结果不再展示。
- iCloud 同步新条目后，本机索引能异步更新。
- 搜索无结果必须展示建议，不允许空白。

## 8. LLM Provider 设计

### 8.1 DeepSeek 官方约束

根据 DeepSeek 官方文档，第一版采用：

```text
baseURL: https://api.deepseek.com
endpoint: POST /chat/completions
model: deepseek-v4-flash
format: OpenAI-compatible Chat Completions
thinking: {"type": "disabled"}
response_format: {"type": "json_object"}
stream: false
```

关键注意事项：

- DeepSeek 模型默认启用思考模式；第一版必须显式传 `thinking: {"type": "disabled"}`。
- 非思考模式下可以使用 `temperature`；翻译任务默认 `temperature = 0.2`。
- JSON Output 必须设置 `response_format: {"type": "json_object"}`。
- system 或 user prompt 中必须包含 `json` 字样，并给出 JSON 示例。
- 必须设置足够的 `max_tokens`，避免 JSON 被截断。
- JSON Output 仍可能返回空 content，必须做空内容检查和一次重试。
- `finish_reason = "length"` 时视为失败，不得写入收藏。
- `finish_reason = "content_filter"`、`"insufficient_system_resource"` 时应给出可理解错误提示。

第一版不使用：

- streaming。
- tool calls。
- Anthropic 格式接口。
- beta prefix completion。
- 自定义 DeepSeek base URL。

### 8.2 Provider 抽象

```swift
protocol LLMProvider {
    var providerID: String { get }
    func translate(_ request: TranslationRequest) async throws -> TranslationLLMResult
    func validateCredential(_ credential: ProviderCredential) async -> CredentialValidationResult
}
```

第一版 UI 只开放 DeepSeek，但代码层同时提供 `OpenAICompatibleChatProvider`，DeepSeekProvider 基于该适配器封装。

```text
OpenAICompatibleChatProvider
  - baseURL
  - model
  - authorization bearer token
  - response_format
  - provider-specific extra body

DeepSeekProvider
  - baseURL 固定 https://api.deepseek.com
  - model 固定 deepseek-v4-flash
  - extra_body.thinking.type = disabled
  - 不暴露 baseURL 编辑入口
  - credential validation 使用 GET /user/balance
```

DeepSeek Token 连通性测试：

```text
GET https://api.deepseek.com/user/balance
Authorization: Bearer <token>
Accept: application/json
```

响应字段：

```json
{
  "is_available": true,
  "balance_infos": [
    {
      "currency": "CNY",
      "total_balance": "110.00",
      "granted_balance": "10.00",
      "topped_up_balance": "100.00"
    }
  ]
}
```

判断规则：

- HTTP 200 且 `is_available = true`：Token 有效且账户可用于 API 调用。
- HTTP 200 但 `is_available = false`：Token 可认证，但余额不可用，提示用户检查余额。
- HTTP 401：Token 错误或失效。
- 其他网络或 5xx 错误：提示稍后重试。

### 8.3 Request

```text
requestID: UUID
inputText: String
sourceLanguageMode: auto / zh / en / es
targetLanguage: zh / en / es
schemaVersion: String
modelName: String
temperature: Double
timeoutSeconds: Int
maxAlternatives: Int
contextHint: String?
```

建议：

- 翻译 temperature 默认 0.2。
- 请求超时默认 30 秒。
- `max_tokens` 第一版建议 1200 到 2000，并根据 schema 扩展调整。
- `maxAlternatives` 默认 3，允许设置范围 0 到 5。
- 网络失败可重试 1 次。
- JSON 解析失败可进行一次“修复格式”重试，但不能无限重试。

### 8.4 Response Schema

```json
{
  "schema_version": "2.0",
  "detected_source_language": "es",
  "detected_source_language_confidence": 0.91,
  "confirmed_source_language": "es",
  "target_language": "zh",
  "content_type": "phrase",
  "main_translation": "不用客气",
  "alternatives": [
    {
      "text": "没关系",
      "explanation": "较口语化的回应感谢表达。",
      "part_of_speech": null,
      "register": "casual",
      "confidence": 0.82
    }
  ],
  "classification": {
    "topic": "daily",
    "subtopic": "polite_expression",
    "tags": ["日常表达", "礼貌用语"],
    "difficulty": "beginner",
    "usage_scenario": ["日常对话"],
    "grammar_focus": [],
    "semantic_group": "reply_to_thanks",
    "confidence": 0.86,
    "reason_summary": "该短语常用于回应感谢。"
  },
  "warnings": [
    {
      "code": "short_text_language_ambiguous",
      "message": "短文本语言识别可能不稳定。"
    }
  ]
}
```

### 8.5 Prompt 设计

Prompt 设计是翻译质量的核心，不要把它写成“请翻译并解释一下”。第一版必须严格分离：

- system prompt：定义模型职责、输出格式、翻译原则、禁止事项。
- user prompt：传入本次输入、语言方向、候选上限、可选语境。
- App 本地逻辑：校验 JSON、计算 direction、决定是否收藏。

#### 8.5.1 System Prompt

建议 system prompt：

```text
You are a precise multilingual translation engine for a personal language memory app.

You must output valid json only. Do not output markdown, comments, explanations outside json, or extra text.

Task:
- Translate the user's input from the source language mode to the target language.
- Produce a natural, accurate, context-aware main translation.
- The main_translation field must contain only the translated text itself.
- Do not include labels such as "Translation:", notes, explanations, quotes, bullet points, or alternatives inside main_translation.
- If the source language is auto, detect it among zh, en, es when possible.
- If the input is ambiguous, choose the most likely interpretation and add a warning.
- Generate a small number of useful alternatives only when they add real value.
- Alternatives should differ by meaning, register, tone, or usage context, not by trivial wording.
- Never invent grammar facts, part of speech, or usage scenarios when uncertain.
- Keep tags short, stable, and reusable.

Output json schema:
{
  "schema_version": "2.0",
  "detected_source_language": "zh|en|es",
  "detected_source_language_confidence": 0.0,
  "confirmed_source_language": "zh|en|es",
  "target_language": "zh|en|es",
  "content_type": "word|phrase|sentence|paragraph|unknown",
  "main_translation": "string",
  "alternatives": [
    {
      "text": "string",
      "explanation": "string|null",
      "part_of_speech": "string|null",
      "register": "neutral|formal|casual|academic|technical|slang|unknown",
      "confidence": 0.0
    }
  ],
  "classification": {
    "topic": "string|null",
    "subtopic": "string|null",
    "tags": ["string"],
    "difficulty": "beginner|intermediate|advanced|unknown",
    "usage_scenario": ["string"],
    "grammar_focus": ["string"],
    "semantic_group": "string|null",
    "confidence": 0.0,
    "reason_summary": "string|null"
  },
  "warnings": [
    {
      "code": "string",
      "message": "string"
    }
  ]
}
```

#### 8.5.2 User Prompt

建议 user prompt 用 JSON 传入任务，不要拼自然语言长段落：

```json
{
  "task": "translate_for_memory_item",
  "source_language_mode": "auto",
  "target_language": "zh",
  "max_alternatives": 3,
  "context_hint": null,
  "input_text": "de nada",
  "requirements": {
    "main_translation_only_translated_text": true,
    "no_extra_text_outside_json": true,
    "prefer_natural_translation": true,
    "preserve_meaning_over_literalness": true
  }
}
```

#### 8.5.3 候选译文数量策略

候选译文不应固定数量。固定 3 个会导致模型为了凑数输出垃圾候选；固定 0 个又会浪费多义词、语体差异和短语场景。

第一版策略：

```text
App 设置 maxAlternatives，默认 3，范围 0..5。
模型在 0..maxAlternatives 内自行决定数量。
单义、明确、短文本：0 到 1 个候选。
多义词、语气差异明显、正式/口语差异明显：2 到 3 个候选。
只有在用户显式提高上限时，最多允许 5 个候选。
```

候选译文必须满足：

- 不与主译文重复。
- 每个候选必须有明确差异点。
- `explanation` 说明差异，而不是复述译文。
- 不为了凑数量生成低质量同义改写。

#### 8.5.4 风格与语境

候选译文风格应根据语境调整：

- 输入是正式邮件、学术句子、工作表达时，主译文偏正式自然。
- 输入是日常口语时，主译文偏自然口语。
- 输入包含俚语或非正式表达时，候选可给出 neutral/casual/slang 差异。
- 没有明确语境时，主译文使用 neutral register。
- 不要把风格说明混入 `main_translation`，只放在 `alternatives[].register` 和 `explanation`。

### 8.6 本地校验

必须校验：

- schema_version 支持。
- target_language 等于用户选择。
- confirmed_source_language 不等于 target_language。
- content_type 在枚举内。
- main_translation 非空。
- tags 最多 8 个。
- alternatives 最多 5 个。
- confidence 在 0 到 1 之间。
- direction 由本地计算，不接受模型提供值作为权威。
- `main_translation` 不得包含明显的前缀说明，例如 `Translation:`、`译文：`。
- `alternatives` 超过用户设置的 `maxAlternatives` 时截断并记录调试信息。
- content 为空、非 JSON、被截断或 finish_reason 非 stop 时，不得写入收藏。

### 8.7 错误码

App 内部错误码建议：

```text
providerCredentialMissing
providerCredentialInvalid
providerRateLimited
providerInsufficientBalance
providerTimeout
providerNetworkUnavailable
providerInvalidResponse
providerSchemaValidationFailed
providerContentRejected
providerServerError
providerBusy
sourceTargetLanguageConflict
```

UI 必须把错误翻译成人能处理的动作，例如：

- 配置 Token。
- 稍后重试。
- 检查网络。
- 缩短输入。
- 更换目标语言。

## 9. 收藏、重复与覆盖

### 9.1 duplicateKey

```text
duplicateKey = sha256(
  normalizeForDuplicate(sourceText)
  + "|"
  + confirmedSourceLanguage
  + "|"
  + targetLanguage
)
```

`normalizeForDuplicate`：

- trim
- collapse whitespace
- lowercase for en / es
- accent fold for es duplicate check
- keep Chinese characters

### 9.2 覆盖范围

用户选择覆盖旧条目时：

覆盖：

- translatedText
- contentType
- provider
- modelName
- alternatives
- classification 中未被用户修改的字段
- rawResponseID
- updatedAt

保留：

- id
- createdAt
- favoritedAt
- lastViewedAt
- userEdited
- 用户修改过的标签，除非用户明确选择用新标签覆盖

第一版 `userEdited` 固定为 false，但保留字段。

### 9.3 标签修改

标签由 LLM 给出初步值，但用户可以删除和修改。

规则：

- 标签最多 8 个。
- 单个标签建议 2 到 12 个字符。
- 标签修改后立即更新 Core Data 和 SearchIndex。
- 用户修改后的标签优先于 LLM 初始标签展示和搜索。
- 覆盖旧条目时，如果旧标签已被用户修改，必须提示是否保留用户标签。
- 第一版不做独立 Tag 管理页；后续可扩展为全局标签管理。

### 9.4 并发冲突

第一版采用 last writer wins。

规则：

- 以 `updatedAt` 和 CloudKit server change 为准。
- 冲突发生后本地重建该条目的搜索索引。
- 删除优先级高于普通更新。若一端删除、一端更新，第一版以删除为准。

这个策略不完美，但第一版够用。别在第一版上 CRDT 或复杂合并，纯属给自己找麻烦。

## 10. CloudKit 同步设计

### 10.1 同步内容

同步：

- TranslationItem
- TranslationAlternative
- ClassificationRecord
- ProviderConfigPublic
- DeletionTombstone

不同步：

- ProviderSecret
- API Token
- SearchIndex
- RawAPIResponse 默认不同步
- 临时请求状态

### 10.2 删除同步

删除流程：

```text
用户删除
  -> TranslationItem.isDeleted = true
  -> deletedAt = now
  -> 写入 DeletionTombstone
  -> 本机隐藏条目
  -> 删除或更新搜索索引
  -> CloudKit 同步
  -> 其他设备收到后隐藏并更新索引
```

### 10.3 同步状态 UI

设置页或收藏页应显示：

- iCloud 是否可用。
- 最近同步时间。
- 当前是否有同步错误。
- 当前设备 Token 是否已配置。

不要承诺“实时同步”。更准确的文案是“通过 iCloud 在设备间同步，具体时间取决于系统状态和网络”。

## 11. 导入导出设计

### 11.1 JSON 格式

第一版只支持全量导入和全量导出，不支持按语言方向、标签、时间范围选择导入导出范围。

```json
{
  "export_schema_version": "2.0",
  "app_version": "1.0.0",
  "exported_at": "2026-05-28T00:00:00Z",
  "source_device": {
    "platform": "macOS",
    "app_build": "100"
  },
  "capabilities": {
    "contains_raw_responses": false,
    "contains_deleted_items": false
  },
  "items": [],
  "checksum": "sha256:..."
}
```

不导出：

- API Token。
- Keychain reference。
- SearchIndex。
- 临时缓存。

### 11.2 导入校验

导入前：

- 校验 JSON 格式。
- 校验 schema version。
- 校验 checksum。
- 统计总条目数、重复条目数、不支持条目数。

导入策略：

- 单条重复：覆盖或跳过。
- 批量重复：可选择全部覆盖或全部跳过。
- 不支持 schema：拒绝导入并提示升级 App。
- 导入完成后重建搜索索引。
- 第一版导入文件视为全量备份文件，但导入行为不是“清空后恢复”，而是把文件中的全部条目导入当前资料库，并按 duplicateKey 处理重复项。

### 11.3 迁移策略

每个导出文件必须带 schema version。App 内部维护 migration：

```text
1.0 -> 2.0
2.0 -> future
```

迁移失败不能写入主库，必须先在内存或临时区完成校验。

## 12. 隐私与安全

### 12.1 Token

- API Token 存 Keychain。
- 默认不跨设备同步 Token。
- 不导出 Token。
- 不写入日志。
- 不写入 RawAPIResponse。

### 12.2 用户内容

用户输入会发送给第三方 LLM Provider。首次使用翻译前必须提示：

```text
翻译请求会发送到你配置的模型服务商。已收藏内容会保存在本机，并通过你的 iCloud 私有空间在设备间同步。
```

### 12.3 导出文件

导出文件包含用户收藏内容，可能有隐私风险。第一版不支持加密导出，导出前必须提示用户妥善保管文件。

### 12.4 匿名崩溃日志

Release build 保留匿名崩溃日志能力，并另写隐私说明。

第一版要求：

- 预留用户选择接口，例如“允许发送匿名崩溃日志”。
- 默认是否开启需要在隐私说明中明确；若不能确定，建议默认关闭。
- 崩溃日志不得包含 API Token、用户原文、译文、RawAPIResponse、导出文件内容。
- 如果未来接入自动上传，需要在 App 内隐私说明中明确收集目的、内容范围、关闭方式。
- 第一版不实现 Face ID / Touch ID 应用锁。

## 13. 非功能需求

### 13.1 性能

- 5000 条收藏内搜索接近即时。
- 翻译请求 UI 不冻结。
- 索引重建在后台执行。
- 导入 5000 条以内不阻塞主线程。

### 13.2 离线

离线可用：

- 查看收藏。
- 搜索收藏。
- 删除收藏。
- 导入导出本地文件。

离线不可用：

- 新翻译。
- API Token 连通性测试。

离线删除需要在联网后同步。

### 13.3 可恢复

- 搜索索引可从 Core Data 重建。
- 导入失败不能污染现有主库。
- CloudKit 不可用时，本地收藏仍可使用。

## 14. 验收标准

### 14.1 翻译

- 未配置 Token 时不能发起翻译，并提示配置入口。
- Token 连通性测试调用 `GET https://api.deepseek.com/user/balance`，以 `is_available` 判断账户是否可用于 API 调用。
- DeepSeek 请求必须使用 `https://api.deepseek.com`、`deepseek-v4-flash`、`thinking.disabled`。
- DeepSeek 设置页不得提供 base URL 自定义入口。
- source 和 target 相同时不能发起有效收藏。
- LLM 非 JSON 响应时最多重试一次。
- 结构化校验失败时不写入收藏。
- `main_translation` 只能包含译文文本，不得包含解释、标签、前缀或 Markdown。
- 候选译文数量不得超过用户设置的 `maxAlternatives`。

### 14.2 收藏

- 收藏成功后可离线查看。
- 重复收藏时提示覆盖或保留旧记录。
- 覆盖后保留原 id、createdAt、favoritedAt。
- 删除后当前设备列表和搜索结果立即消失。

### 14.3 搜索

- 支持原文、译文、标签、分类统一搜索。
- `cancion` 可搜到 `canción`。
- `一个`、`yi ge`、`yige` 可搜到同一个中文条目。
- 使用英文或西班牙语搜索时，也会匹配条目中的中文字段和拼音字段。
- 搜索无结果显示建议。
- 删除项不出现在搜索结果。

### 14.4 同步

- 同一 iCloud 账号下多设备可同步收藏。
- 删除可同步到其他设备。
- Token 不随 iCloud 同步。
- 新设备需要重新配置 Token 后才能翻译，但可查看已同步收藏。

### 14.5 导入导出

- 导出 JSON 不包含 Token。
- 导出 JSON 不加密，并在导出前提示隐私风险。
- 第一版只支持全量导入和全量导出。
- 导入重复项可覆盖或跳过。
- 导入完成后搜索索引可用。
- schema 不支持时不写入主库。

### 14.6 安全

- 第一版不做 Face ID / Touch ID 应用锁。
- RawAPIResponse 只在 Debug build 保存。
- Release build 不保存 RawAPIResponse。
- Release build 预留匿名崩溃日志设置和隐私说明。

### 14.7 视觉兼容

- iOS 26 及以上默认采用系统 Liquid Glass/液态玻璃视觉能力。
- iOS 25 及以下保持系统原生样式，不手写仿玻璃效果。
- 长文本阅读区、搜索结果列表、候选译文说明必须保持足够对比度和可读性。
- 尊重系统辅助功能设置，包括增加对比度、减少透明度、减少动态效果。

## 15. 工程里程碑

### M1: 项目骨架

- SwiftUI multiplatform target。
- Core Data + CloudKit container。
- Keychain credential service。
- 匿名崩溃日志用户选择接口预留。
- 基础设置页。

### M2: DeepSeek 翻译链路

- Provider 抽象。
- OpenAI-compatible Chat Completions 通用适配器。
- DeepSeek provider。
- DeepSeek 固定 `baseURL=https://api.deepseek.com`。
- DeepSeek 固定 `model=deepseek-v4-flash`。
- DeepSeek 固定非思考模式。
- Token 校验：调用 `GET https://api.deepseek.com/user/balance` 并检查 `is_available`。
- 结构化 JSON prompt。
- 响应校验和错误处理。
- 候选译文数量上限设置。

### M3: 收藏与数据模型

- TranslationItem。
- TranslationAlternative。
- ClassificationRecord。
- 重复检测和覆盖策略。

### M4: 本地搜索

- 独立 SQLite FTS store。
- 索引构建与重建。
- 中文拼音全拼和首字母索引。
- 搜索 ranking。
- 搜索过滤。

### M5: iCloud 同步与删除

- 多设备同步验证。
- 软删除同步。
- 同步状态 UI。
- 搜索索引同步后刷新。

### M6: 导入导出

- JSON 全量导出。
- JSON 全量导入。
- schema 校验。
- 重复处理。

### M7: 三端体验完善

- iOS 快速翻译与收藏。
- iPadOS 分栏。
- macOS 菜单、快捷键、工具栏。
- 空状态、无结果、loading、错误状态。
- 标签删除和修改。
- 可访问性检查。

## 16. 已决策项

- DeepSeek 第一版具体模型：`deepseek-v4-flash`。
- DeepSeek 调用模式：非思考模式，显式 `thinking.disabled`。
- DeepSeek base URL：固定 `https://api.deepseek.com`，不允许用户自定义。
- DeepSeek Token 连通性测试：`GET https://api.deepseek.com/user/balance`，用 `is_available` 判断是否可用于 API 调用。
- 第一版不做 Face ID / Touch ID 应用锁。
- 中文拼音搜索进入第一版。
- 拼音转换使用 Apple 原生 `StringTransform.mandarinToLatin` 或 `CFStringTransform`。
- 标签支持用户删除和修改。
- 导出不支持加密。
- RawAPIResponse 只在 Debug build 保存。
- Release build 保留匿名崩溃日志能力，另写隐私说明，预留用户选择接口。
- 第一版只支持全量导入和全量导出。
- iOS 26 及以上默认采用系统 Liquid Glass/液态玻璃视觉能力。
- Provider 增加 OpenAI-compatible Chat Completions 通用适配器。
- 候选译文数量不固定，由模型在上限内按语境决定；默认上限 3，设置范围 0 到 5。

## 17. 仍需决策

- 暂无。

## 18. 官方文档依据

- DeepSeek 快速开始：https://api-docs.deepseek.com/zh-cn/
- DeepSeek 模型与价格：https://api-docs.deepseek.com/zh-cn/quick_start/pricing
- DeepSeek 思考模式：https://api-docs.deepseek.com/zh-cn/guides/thinking_mode
- DeepSeek JSON Output：https://api-docs.deepseek.com/zh-cn/guides/json_mode
- DeepSeek Chat Completions API：https://api-docs.deepseek.com/zh-cn/api/create-chat-completion
- DeepSeek 查询余额：https://api-docs.deepseek.com/zh-cn/api/get-user-balance
- DeepSeek 错误码：https://api-docs.deepseek.com/zh-cn/quick_start/error_codes
- Apple StringTransform：https://developer.apple.com/documentation/foundation/stringtransform
- Apple CFStringTransform：https://developer.apple.com/documentation/CoreFoundation/CFStringTransform%28_%3A_%3A_%3A_%3A%29
- Apple Liquid Glass overview：https://developer.apple.com/documentation/technologyoverviews/liquid-glass
- Apple Applying Liquid Glass to custom views：https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views

## 19. 审视性结论

v2 的关键判断是：第一版不能把复杂度堆到 UI 上，也不能幻想 CloudKit 或 LLM 替你解决搜索和数据一致性。

真正应该优先打牢的是：

- Core Data 作为权威数据层。
- 独立 FTS 作为可重建搜索层。
- Keychain 作为凭据边界。
- DeepSeek 固定官方 base URL，避免中转站带来的 Token 泄露和中间人风险。
- LLM 结构化输出作为可校验输入，而不是可信事实。
- Prompt 必须约束主译文只包含译文文本，解释和风格差异只能进入结构化字段。
- CloudKit 作为最终一致同步，而不是实时数据库。
- JSON 导入导出作为用户数据主权保障。

如果这些边界守住，第一版即使功能不花哨，也会是一个可靠的个人语言记忆库。反过来，如果一开始把搜索、同步、Token、导入导出混在一起，后面做三端体验时会非常难收拾。
