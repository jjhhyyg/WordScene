# 单词、短语、句子记忆软件第一版设计方案

## 1. 背景与目标

本软件第一版定位为一个基于 Apple 生态的个人多语种翻译收藏与记忆资料库。它不是单纯的翻译工具，而是以翻译为入口，把用户认为值得长期保存的单词、短语、句子沉淀为可离线查看、可快速检索、可跨设备同步的学习条目。

第一版优先支持中、英、西三个语种之间的翻译与收藏，但由于底层翻译能力依赖大模型 API，数据模型和服务抽象应避免被这三个语种锁死，为后续扩展更多语种保留空间。

第一版核心目标：

- 支持用户自行配置 DeepSeek API Token。
- 预留多模型 Provider 抽象，后续可扩展 Qwen、Kimi、MiniMax、GLM、OpenAI、Gemini、Claude 等。
- 支持中文、英文、西班牙语的源语言选择、目标语言选择、翻译、收藏。
- 收藏内容以“可学习条目”为单位，而不是一次性查询日志。
- 收藏条目支持自动归类、结构化标签、快速全文检索和离线查看。
- 使用 iCloud 私有空间完成多设备同步。
- 支持删除后的多端同步删除。
- 支持导入导出，用于用户主动备份和恢复。
- 三个平台 iOS、iPadOS、macOS 共享核心能力，但界面针对各自交互场景做差异化设计。

第一版明确不做：

- 不允许用户手动编辑翻译结果。
- 不做复习计划、遗忘曲线、每日任务等学习调度功能。
- 不做发音、TTS、音标展示，但数据模型预留字段。
- 不做收藏项合并；重复项只允许用户选择覆盖或保留旧记录。
- 不把 CloudKit 当作主检索引擎。

## 2. 第一版产品边界

### 2.1 核心流程

用户打开 App 后，可以输入一个单词、短语或句子，选择源语言和目标语言，然后调用用户配置的大模型 API 获取翻译结果。用户可以将翻译结果收藏为学习条目。收藏后，系统会保存翻译文本、语言方向、内容类型、自动分类、标签、创建时间、收藏时间、模型信息、开发阶段原始响应等信息。

典型流程：

```text
输入文本
  -> 选择 source 语言：自动检测 / 中文 / 英文 / 西班牙语
  -> 选择 target 语言
  -> 调用 LLM 翻译
  -> 解析结构化结果
  -> 用户确认收藏
  -> 检查重复项
  -> 用户选择覆盖或保留旧记录
  -> 写入本地数据库
  -> 更新本地检索索引
  -> 通过 CloudKit 同步到其他设备
```

### 2.2 语言选择规则

source 语言支持：

- 自动检测
- 中文
- 英文
- 西班牙语

target 语言支持：

- 中文
- 英文
- 西班牙语

约束：

- 当 source 为中文时，target 只能选择英文或西班牙语。
- 当 source 为英文时，target 只能选择中文或西班牙语。
- 当 source 为西班牙语时，target 只能选择中文或英文。
- 当 source 为自动检测时，target 可以选择中文、英文或西班牙语。
- 最终检测出的 source 语言如果与 target 相同，应提示用户重新选择目标语言，不能保存为有效翻译方向。

需要注意的潜在问题：

- 自动检测短文本风险较高，例如 `no`、`me`、`pie` 既可能被识别成英文，也可能被识别成西班牙语。
- 因此第一版应保存用户选择的 `sourceLanguageMode` 与模型检测的 `detectedSourceLanguage`，不要把两者混为一谈。

## 3. 技术路线

### 3.1 推荐架构

```text
SwiftUI App
  -> ViewModel / Use Case
  -> LLM Provider Layer
  -> Local Persistence Layer
  -> Local Search Index
  -> CloudKit Sync Layer
```

推荐技术组合：

- UI：SwiftUI
- 本地结构化数据：Core Data
- iCloud 同步：NSPersistentCloudKitContainer
- API Token 存储：Keychain
- 本地全文检索：SQLite FTS5 或独立搜索索引表
- 大模型调用：URLSession + Provider 抽象
- 导入导出：JSON 文件，后续可扩展 CSV、Markdown、Anki

### 3.2 CloudKit 与 iCloud Documents 的选择

第一版建议使用 `Core Data + NSPersistentCloudKitContainer`，不建议使用 iCloud Documents 作为主同步方案。

原因：

- 本软件核心数据是结构化记录，不是单个文档。
- 收藏项、分类、标签、删除状态、模型元数据都需要增量同步。
- iCloud Documents 更容易遇到文件冲突、数据库锁、冲突副本和索引重建问题。
- CloudKit 更适合私有数据库中的结构化数据同步。

关键设计原则：

- CloudKit 负责同步，不负责主搜索。
- 本地数据库负责日常读写。
- 本地搜索索引负责快速查询。
- 本地索引字段可以不直接同步，因为可以由同步后的结构化数据重建。

## 4. 数据模型设计

### 4.1 设计原则

收藏项必须按“可学习条目”建模，而不是按“翻译请求日志”建模。

这意味着：

- 同一个单词、短语或句子，在同一语言方向下应被视作潜在重复项。
- 用户收藏时如果发现重复项，第一版只提供两个选择：覆盖旧条目或保留旧条目。
- 第一版不做自动合并，因为合并涉及释义冲突、标签合并、创建时间保留和用户意图判断，风险过高。

### 4.2 TranslationItem

`TranslationItem` 是第一版最核心的实体，表示一个可学习条目。

字段建议：

```text
id: UUID
sourceText: String
sourceLanguageMode: LanguageMode
detectedSourceLanguage: LanguageCode?
confirmedSourceLanguage: LanguageCode
targetLanguage: LanguageCode
translatedText: String
contentType: ContentType
direction: TranslationDirection
provider: ProviderID
modelName: String
createdAt: Date
updatedAt: Date
favoritedAt: Date
deletedAt: Date?
isDeleted: Bool
duplicateKey: String
note: String?
userEdited: Bool
rawResponseStoragePolicy: RawResponseStoragePolicy
rawResponseRef: String?
pronunciationRef: String?
phoneticText: String?
ttsAudioRef: String?
```

枚举建议：

```text
LanguageMode:
  auto
  zh
  en
  es

LanguageCode:
  zh
  en
  es

ContentType:
  word
  phrase
  sentence
  paragraph
  unknown

TranslationDirection:
  zh_en
  zh_es
  en_zh
  en_es
  es_zh
  es_en

RawResponseStoragePolicy:
  disabled
  developmentOnly
  enabled
```

字段说明：

- `sourceLanguageMode`：用户选择的源语言模式，可以是自动检测。
- `detectedSourceLanguage`：模型或语言识别器判断出的源语言。
- `confirmedSourceLanguage`：最终用于保存和分类的源语言。
- `direction`：由 `confirmedSourceLanguage + targetLanguage` 计算得出。
- `duplicateKey`：用于判断重复收藏，建议由归一化后的原文、确认源语言、目标语言组成。
- `isDeleted` 与 `deletedAt`：用于多端同步删除和可能的误删恢复。
- `pronunciationRef`、`phoneticText`、`ttsAudioRef`：第一版不使用，但为发音能力预留。

### 4.3 TranslationAlternative

用于保存候选译文。第一版界面可以只展示主译文，但结构上应允许保存多个候选。

```text
id: UUID
itemId: UUID
text: String
explanation: String?
partOfSpeech: String?
register: Register?
confidence: Double?
sortOrder: Int
createdAt: Date
```

枚举建议：

```text
Register:
  neutral
  formal
  casual
  academic
  technical
  slang
  unknown
```

### 4.4 Classification

保存大模型自动归类结果。分类结果必须可追踪模型来源，避免未来模型变化导致标准混乱。

```text
id: UUID
itemId: UUID
topic: String?
subtopic: String?
tags: [String]
difficulty: Difficulty?
usageScenario: [String]
grammarFocus: [String]
semanticGroup: String?
confidence: Double?
modelName: String
provider: ProviderID
createdAt: Date
manuallyOverridden: Bool
reasonSummary: String?
```

枚举建议：

```text
Difficulty:
  beginner
  intermediate
  advanced
  unknown
```

说明：

- `tags` 用于人工可见分类，例如“商务”“旅行”“日常表达”“邮件表达”。
- `usageScenario` 用于表达使用场景，例如“餐厅点餐”“学术写作”“工作汇报”。
- `grammarFocus` 用于语法点，例如“虚拟式”“过去时”“被动语态”。
- `semanticGroup` 用于把意思相近的表达归到同一语义组，后续可服务语义检索。

### 4.5 SearchIndex

本地搜索索引实体或辅助表。它可以从 `TranslationItem` 和 `Classification` 重建，因此不一定需要进入 CloudKit 同步。

```text
itemId: UUID
normalizedSourceText: String
normalizedTranslatedText: String
accentFoldedText: String
pinyinText: String?
lowercaseText: String
tokenizedText: String
tagBlob: String
searchBlob: String
updatedAt: Date
```

归一化策略：

- 英文统一 lowercase。
- 西班牙语做大小写归一化和重音折叠，例如 `canción` 可被 `cancion` 搜到。
- 中文保留原文，后续可加入拼音字段。
- 标签、备注、分类、原文、译文都进入 `searchBlob`。

### 4.6 ProviderConfig

Provider 配置保存用户选择的模型服务，但 API Key 明文必须存 Keychain。

```text
id: UUID
provider: ProviderID
displayName: String
baseURL: String
defaultModel: String
apiKeyKeychainRef: String
enabled: Bool
createdAt: Date
updatedAt: Date
```

第一版 UI 只需要 DeepSeek，但代码结构要支持新增 Provider。

### 4.7 RawAPIResponse

开发阶段可保存原始 API 响应，正式版可由用户关闭。

```text
id: UUID
itemId: UUID?
provider: ProviderID
modelName: String
requestPayload: String?
responsePayload: String
createdAt: Date
environment: AppEnvironment
```

注意：

- 原始响应可能包含用户输入内容，属于隐私数据。
- 如果正式版提供保存原始响应选项，必须在隐私说明中明确。
- API Token 不得写入原始请求日志。

## 5. 重复收藏与覆盖策略

第一版判断重复项使用 `duplicateKey`。

建议生成方式：

```text
duplicateKey = hash(
  normalize(sourceText)
  + confirmedSourceLanguage
  + targetLanguage
)
```

重复时弹出选择：

- 覆盖旧条目：旧条目的主译文、分类、标签、模型信息、更新时间被替换；`createdAt` 可保留，`updatedAt` 更新。
- 保留旧记录：不写入新条目，继续保留原收藏。

第一版不提供：

- 合并候选译文
- 合并标签
- 合并学习历史
- 自动判断哪个译文更好

这里必须说得重一点：如果第一版就做“智能合并”，很容易把用户数据搞脏。你现在这个阶段不做合并是对的。

## 6. 搜索体验设计

### 6.1 搜索目标

第一版搜索必须做到：

- 收藏内容可离线搜索。
- 搜索响应应接近即时反馈。
- 支持原文、译文、标签、分类、备注的统一搜索。
- 支持中文、英文、西班牙语基础模糊查询。
- 支持按语言方向过滤。
- 支持按内容类型过滤。
- 支持按收藏时间排序。

### 6.2 搜索分层

建议第一版分三层实现。

第一层：精确与前缀匹配

```text
sourceText
translatedText
normalizedSourceText
normalizedTranslatedText
```

第二层：本地全文检索

```text
searchBlob
tagBlob
tokenizedText
accentFoldedText
```

第三层：语义检索预留

```text
embeddingVectorRef
semanticGroup
usageScenario
```

第一版可以先不做 embedding，但数据模型应避免阻碍后续添加本地或云端向量索引。

### 6.3 搜索输入示例

示例 1：用户搜索 `cancion`

期望：

- 可以命中 `canción`。
- 可以命中包含该词的西语句子。
- 可以按 `西->中` 或 `西->英` 过滤。

示例 2：用户搜索 `商务 邮件`

期望：

- 可以命中标签中包含“商务”“邮件表达”的条目。
- 可以命中分类为 business/email 的条目。

示例 3：用户搜索 `thank`

期望：

- 可以命中 `thank`、`thanks`、`thank you`。
- 后续语义检索可命中“表达感谢”的中英文或西语句子。

### 6.4 不建议第一版做的搜索能力

- 不建议第一版把每次搜索都交给大模型。
- 不建议第一版依赖 CloudKit 远程查询做主搜索。
- 不建议第一版承诺复杂语义搜索。
- 不建议第一版做跨所有语言的高级词形还原。

原因很简单：搜索是高频功能，必须稳定、快速、低成本。LLM 可以增强搜索，但不能成为搜索的地基。

## 7. LLM 结构化输出设计

### 7.1 Provider 抽象

第一版虽然只暴露 DeepSeek，但代码应设计为可扩展 Provider。

```swift
protocol LLMProvider {
    var providerID: String { get }
    func translate(_ request: TranslationRequest) async throws -> TranslationLLMResult
}
```

请求字段建议：

```text
inputText
sourceLanguageMode
targetLanguage
expectedOutputSchemaVersion
```

响应必须是结构化 JSON，而不是自然语言段落。

### 7.2 结构化输出 Schema

建议第一版要求模型输出：

```json
{
  "schema_version": "1.0",
  "detected_source_language": "es",
  "confirmed_source_language": "es",
  "target_language": "zh",
  "content_type": "phrase",
  "direction": "es_zh",
  "main_translation": "不用客气",
  "alternatives": [
    {
      "text": "没关系",
      "explanation": "较口语化的表达",
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
  "warnings": []
}
```

### 7.3 结构化输出校验

App 不能盲信模型输出。必须做本地校验：

- `target_language` 必须等于用户选择的目标语言。
- `confirmed_source_language` 不能等于 `target_language`。
- `direction` 必须能由 `confirmed_source_language + target_language` 计算出来。
- `main_translation` 不能为空。
- `content_type` 不在枚举内时降级为 `unknown`。
- `tags` 数量应有限制，例如最多 8 个。
- `confidence` 必须归一到 0 到 1。

如果模型输出不合法：

- 可自动重试一次。
- 仍失败则提示用户翻译失败。
- 开发阶段保存失败响应，便于调试。

### 7.4 Prompt 设计要点

Prompt 应明确要求：

- 只输出 JSON。
- 不要输出 Markdown。
- 目标语言必须与用户选择一致。
- 不要编造不确定的词性或语法点。
- 对短文本要返回语言识别置信度或 warning。
- 分类标签必须短、稳定、可复用。

潜在风险：

- 不同 Provider 对 JSON 输出约束能力不同。
- 即使模型声称支持 JSON，也可能在异常场景输出解释文字。
- 因此结构化解析层必须容错。

## 8. iCloud 同步与删除设计

### 8.1 同步对象

建议同步：

- TranslationItem
- TranslationAlternative
- Classification
- ProviderConfig 中的非敏感配置

不建议同步：

- API Token 明文
- 本地 SearchIndex
- 临时请求状态
- 可重建缓存

RawAPIResponse 是否同步需要谨慎。建议第一版开发阶段只本地保存，不同步到 iCloud；正式版默认不保存。

### 8.2 删除策略

第一版需要支持删除后的多端同步删除。建议使用软删除与最终清理结合：

```text
用户删除
  -> isDeleted = true
  -> deletedAt = now
  -> 本地列表隐藏
  -> CloudKit 同步删除状态
  -> 其他设备收到后隐藏
  -> 未来可做回收站或定期物理删除
```

原因：

- 多设备同步存在延迟。
- 直接物理删除不利于冲突处理。
- 软删除方便未来做误删恢复。

第一版 UI 可以不做回收站，但数据层建议保留 `deletedAt`。

## 9. 导入导出与备份恢复

### 9.1 格式选择

第一版建议使用 JSON 作为主导入导出格式。

原因：

- 能完整表达嵌套结构，如候选译文、分类、标签、模型信息。
- 比 CSV 更适合恢复。
- 比 Markdown 更适合机器解析。
- 后续可再额外导出 CSV 或 Anki 包。

导出文件建议结构：

```json
{
  "schema_version": "1.0",
  "exported_at": "2026-05-28T00:00:00Z",
  "app_version": "1.0.0",
  "items": []
}
```

导出内容应包含：

- TranslationItem
- TranslationAlternative
- Classification
- 必要的非敏感元数据

导出内容不应包含：

- API Token
- Keychain 引用
- 临时缓存
- 本地搜索索引

### 9.2 导入策略

导入时需要处理重复项：

- 如果导入条目的 `duplicateKey` 已存在，提示用户覆盖或跳过。
- 第一版不做批量智能合并。
- 导入后重建本地 SearchIndex。

这里要明确一点：导入导出是“用户主动备份和恢复”，不是自动备份系统。自动备份已经由 iCloud 同步在一定程度上承担，但它不等于历史版本备份。后续如需真正备份，应设计版本化导出或自动周期导出。

## 10. 三端体验差异

### 10.1 iOS

重点：

- 快速输入
- 快速翻译
- 快速收藏
- 快速搜索

建议：

- 首页突出输入框与语言方向选择。
- 收藏成功反馈要轻。
- 搜索入口常驻底部 Tab 或导航栏。

### 10.2 iPadOS

重点：

- 输入、结果、收藏列表并排。
- 更适合阅读长句和对比译文。

建议：

- 使用 split view。
- 左侧收藏/分类列表，中间搜索结果，右侧详情。
- 支持键盘快捷键。

### 10.3 macOS

重点：

- 高效检索
- 批量管理
- 导入导出
- 快捷键

建议：

- 使用侧边栏 + 列表 + 详情面板。
- 支持全局或应用内快捷查词入口。
- 菜单栏提供导入、导出、设置。

## 11. 隐私与安全

关键原则：

- API Token 必须存 Keychain。
- 默认不把 API Token 同步到 iCloud。
- 用户输入内容会发送给第三方模型服务，必须在设置或首次使用时明确提示。
- 原始 API 响应在正式版默认关闭保存。
- 导出文件可能包含用户隐私内容，导出时应提醒用户妥善保管。

如果未来上架 App Store，需要准备：

- 隐私政策
- 第三方 API 使用说明
- 用户数据处理说明
- 是否收集诊断信息的声明
- iCloud 数据使用说明

## 12. 第一版最小可交付范围

第一版建议拆成以下功能模块：

1. Provider 设置
   - DeepSeek API Token 配置
   - Keychain 存储
   - API 连通性测试

2. 翻译
   - 输入文本
   - source 语言选择
   - target 语言选择
   - 调用 DeepSeek
   - 解析结构化 JSON

3. 收藏
   - 保存为 TranslationItem
   - 自动分类
   - 重复检测
   - 覆盖或保留旧记录

4. 搜索
   - 本地离线搜索
   - 原文、译文、标签、分类统一搜索
   - 语言方向过滤
   - 内容类型过滤

5. 同步
   - Core Data + CloudKit
   - 多端收藏同步
   - 多端删除同步

6. 导入导出
   - JSON 导出
   - JSON 导入
   - 重复项覆盖或跳过

7. 平台体验
   - iOS 快速输入和收藏
   - iPadOS 分栏浏览
   - macOS 高效检索与导入导出

## 13. 仍需决策的问题

以下问题还需要后续明确：

- DeepSeek 第一版使用哪个具体模型。
- 是否允许用户自定义 DeepSeek baseURL。
- 翻译失败后是否自动重试，以及重试次数。
- 是否需要请求超时设置，例如 20 秒或 30 秒。
- 收藏时是否必须展示 LLM 自动分类结果。
- 标签是否允许用户删除或修改。
- 导入时是否允许一次性覆盖全部重复项。
- 是否需要导出时选择范围，例如全部、某语言方向、某标签。
- 是否需要设置“开发模式”来控制原始 API 响应保存。
- 是否需要本地应用锁或 Face ID 保护。

## 14. 审视性结论

目前方案最容易踩坑的地方不是翻译，而是数据模型和搜索。

如果第一版只做成“输入、翻译、收藏、同步”，它很快会退化成一个会用大模型的收藏夹。真正决定长期价值的是：收藏项是否结构化、搜索是否足够快、分类是否稳定、导入导出是否保护用户资产。

因此第一版应该把工程重心放在：

- 可学习条目的稳定数据模型；
- 本地优先的快速检索；
- 可校验的 LLM 结构化输出；
- 安全的 Keychain Token 管理；
- CloudKit 同步但不依赖 CloudKit 检索；
- JSON 导入导出保障用户数据可迁移。

这套边界比“先做一个翻译 App”更慢一点，但方向更对。否则后面数据一多，再想补结构化、补搜索、补同步冲突处理，会非常痛苦。
