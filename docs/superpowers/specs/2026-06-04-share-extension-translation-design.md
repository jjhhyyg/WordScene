# Share Extension 快捷翻译设计

## 1. 目标

为 WordScene 增加 iOS Share Extension，让用户在 Safari、备忘录、邮件、PDF 阅读器和其他支持系统 Share Sheet 的 App 中选中文本后，可以通过 `翻译到译笺` 快速发送到 WordScene，直接翻译、复制译文、收藏，并可进入主 App 的翻译页查看已有原文和译文。

第一版重点是把外部文本进入 WordScene 的高频路径做稳，不把剪贴板监听、OCR、Live Activity 或复杂复习能力塞进同一个交付。

## 2. 范围

### 2.1 第一版包含

- 新增 iOS Share Extension 入口，Share Sheet 显示名为 `翻译到译笺`。
- 支持从 Share Sheet 接收纯文本。
- 支持从富文本中提取纯文本。
- 支持接收 URL，并把 URL 作为来源信息保留；第一版不抓取网页正文。
- Share Extension 内展示轻量翻译面板。
- Share Extension 内调用现有 DeepSeek 翻译链路。
- 翻译完成后展示译文。
- 提供 `复制译文` 按钮。
- 提供 `收藏` 按钮，写入收藏库。
- 提供 `打开译笺` 按钮，进入主 App 翻译页，并带入原文和译文。
- 翻译成功后写入翻译历史。
- 所有新增用户可见文案进入 `WordScene/Resources/Localizable.xcstrings`，不写死中文。
- 本地化测试覆盖新增 key。

### 2.2 第一版不包含

- 不做后台剪贴板监听。
- 不做 OCR 或图片文字识别。
- 不抓取网页全文。
- 不做自动收藏；收藏必须由用户点击 `收藏`。
- 不在 Share Extension 中提供完整收藏编辑页。
- 不做系统本地通知。
- 不做 Live Activity / Dynamic Island。
- 不做 Dynamic Island 上的复制按钮。
- 不自建服务端，不做远程推送。

## 3. 用户流程

### 3.1 Share Sheet 快捷翻译

1. 用户在外部 App 中选中文本。
2. 用户打开系统 Share Sheet。
3. 用户点击 `翻译到译笺`。
4. WordScene Share Extension 打开轻量面板。
5. 面板显示原文、目标语言、翻译状态和译文区域。
6. Extension 读取本机 DeepSeek Token。
7. Extension 调用 DeepSeek 翻译。
8. 翻译成功后，面板显示译文并启用 `复制译文`、`收藏`、`打开译笺`。
9. Extension 写入翻译历史。

### 3.2 收藏

用户点击 `收藏` 后，Extension 把当前原文、译文、语言方向和来源信息写入收藏库。按钮状态变为 `已收藏`，避免重复点击造成重复条目。

如果收藏写入失败，面板展示错误提示，用户仍可复制译文或打开主 App。

### 3.3 打开主 App

用户点击 `打开译笺` 后，主 App 打开翻译页。翻译页需要处于已有结果状态：

- 输入框包含原文。
- 结果区包含译文。
- 语言方向与 Extension 翻译一致。
- 如果用户已经在 Extension 中收藏，主 App 应能反映已收藏状态或至少不重复保存。

## 4. UI 设计

Share Extension 面板使用轻量卡片式布局，避免复制主 App 完整翻译页。

建议结构：

```text
翻译到译笺

原文
[选中文本，最多展示若干行，可滚动]

目标语言
[简体中文 v]

译文
[翻译中... / 译文 / 错误提示]

[复制译文] [收藏] [打开译笺]
```

交互要求：

- 无可用文本时显示 `无法读取分享内容`。
- 未配置 Token 时显示 `请先在设置中保存 DeepSeek API Token`，并提供 `打开译笺`。
- 翻译中禁用 `复制译文` 和 `收藏`。
- 翻译失败后保留原文，允许用户打开主 App。
- 译文过长时滚动展示，不挤压按钮区。
- Share Extension 首屏要以任务完成为目标，不展示设置、同步诊断或发布信息。

## 5. 架构设计

### 5.1 新增 target

在 `project.yml` 中新增 iOS Share Extension target：

- target 名：`WordSceneShareExtension`
- bundle id：`com.erikssonhou.leximemory.share`
- display name：`翻译到译笺`
- extension point：`com.apple.share-services`
- deployment target：iOS 18.0
- activation rule：明确支持 plain text、rich text、web URL，不使用 `TRUEPREDICATE`

主 App target 需要依赖并嵌入 Share Extension。

### 5.2 App Group

主 App 和 Share Extension 需要加入同一个 App Group，例如：

```text
group.com.erikssonhou.leximemory
```

用途：

- 存放 Extension 写入的 pending translation record。
- 支持 Extension 与主 App 交换一次性打开上下文。
- 为未来共享 Core Data store 或共享轻量队列预留空间。

注意：App Group 是签名和 Developer Portal 层面的能力，工程配置后仍需要在 Apple Developer 账号中启用。

### 5.3 共享服务边界

Extension 不应直接依赖主 App UI runtime。需要抽出 extension-safe 服务：

- `SharedContentExtractor`：从 `NSItemProvider` 提取文本、富文本纯文本和 URL。
- `ShareTranslationWorkflow`：协调 Token 读取、翻译调用、历史写入和收藏写入。
- `SharedTranslationHandoffStore`：把原文、译文、语言方向、收藏状态写入 App Group，供主 App 打开时读取。

已有 `DeepSeekTranslationClient` 可复用，但必须确认它没有使用 app-extension-unavailable API。

### 5.4 Token 读取

现有 DeepSeek Token 存在 Keychain。Extension 要读取同一个 Token，需要确认 Keychain access group 是否覆盖主 App 和 Extension。

如果当前 Keychain 配置无法跨 target 读取，需要新增共享 Keychain access group。Token 仍不能进入 CloudKit、导出文件、App Group 明文文件或调试响应记录。

### 5.5 数据写入

第一版优先采用保守写入策略：

- 翻译历史：Extension 翻译成功后写入。
- 收藏：用户点击 `收藏` 后写入。
- 主 App 打开时读取 handoff record，恢复翻译页状态。

Core Data + CloudKit store 当前是主数据真源。Extension 直接写 Core Data 需要处理 App Group store、CloudKit entitlement、并发写入和 migration 风险。第一版实现时可以选择两种路径之一：

1. Extension 直接写共享 Core Data store：体验完整，但签名、App Group 和并发协调风险较高。
2. Extension 写 App Group pending operation，主 App 下次启动或收到打开事件后落库：更稳，但打开主 App 前收藏/历史可能只是 pending。

推荐第一版使用第 2 种路径，除非实现阶段验证 Extension 直接写 Core Data 的签名和并发风险可控。

## 6. Deep Link / 打开主 App

主 App 需要支持一个内部打开入口，例如：

```text
wordscene://share-translation?id=<handoff-id>
```

打开后：

- 读取 App Group 中的 handoff record。
- 切换到翻译页。
- 设置原文、译文、语言方向和翻译状态。
- 如有 pending history 或 pending favorite，完成落库并清理 pending 状态。

如果系统不允许 Share Extension 直接打开 containing app，则 `打开译笺` 需要采用可审核的系统路径，例如通过 `NSExtensionContext` 能力或文档化允许的 URL 打开方式。实现阶段必须验证，不使用依赖私有 API 或明显规避审核的技巧。

## 7. Live Activity / Dynamic Island 后续阶段

Live Activity 和 Dynamic Island 不进入 V1。

后续 V2 需要单独设计：

- 新增 Widget Extension。
- 定义 ActivityKit attributes 和 content state。
- 验证从 Share Extension 场景启动或更新 Live Activity 是否稳定。
- 验证锁屏、Dynamic Island compact/minimal/expanded 展示。

后续 V3 再验证 Dynamic Island 上的 `复制译文` 按钮：

- 是否能通过 App Intent 稳定复制译文。
- 是否会要求启动主 App 或产生明显延迟。
- 是否符合系统隐私和审核预期。

## 8. 本地化

新增 key 必须进入 `Localizable.xcstrings`，至少包括：

- `翻译到译笺`
- `原文`
- `目标语言`
- `译文`
- `翻译中...`
- `复制译文`
- `已复制`
- `收藏`
- `已收藏`
- `打开译笺`
- `无法读取分享内容`
- `请先在设置中保存 DeepSeek API Token`
- `翻译失败`
- `收藏失败`
- `已保存到收藏`

本地化测试要求：

- `AppLocalizationTests` 覆盖新增 key。
- Share Extension display name 覆盖至少 `zh-Hans`、`en`、`es` 的基础展示。
- 不在 SwiftUI 视图或错误提示里裸写仅中文文案。

## 9. 错误处理

- 无文本：显示 `无法读取分享内容`。
- Token 缺失：显示 `请先在设置中保存 DeepSeek API Token`，提供 `打开译笺`。
- 网络失败：显示翻译失败原因摘要，保留原文。
- DeepSeek 返回空结果：显示翻译失败，不写入历史或收藏。
- 收藏写入失败：保留译文，允许复制和打开主 App。
- App Group 不可用：Extension 显示无法打开主 App 的提示，但仍可展示译文。

## 10. 测试计划

单元测试：

- 文本提取：plain text、rich text、URL、空输入。
- Share workflow：Token 缺失、翻译成功、翻译失败、收藏成功、收藏失败。
- Handoff store：写入、读取、清理、缺失 id。
- 本地化 key 覆盖。

工程测试：

- `xcodegen generate` 后确认 Share Extension target 出现在 `.xcodeproj`。
- iOS build 能嵌入 extension。
- activation rule 不包含 `TRUEPREDICATE`。
- entitlements 包含 App Group，且主 App 与 Extension 一致。

手动 smoke：

- Safari 选中文本后 Share Sheet 出现 `翻译到译笺`。
- 备忘录选中文本后可翻译。
- 邮件选中文本后可翻译。
- PDF 场景能处理可分享文本；不能分享文本时不承诺可用。
- 翻译完成后可复制。
- 翻译完成后可收藏。
- 点 `打开译笺` 进入主 App，并显示已有原文和译文。

## 11. 审视性结论

这个功能最重要的不是炫技，而是把外部阅读场景里的文本低摩擦送进 WordScene。第一版必须优先保证 Share Sheet 入口稳定、翻译面板可靠、收藏按钮明确、本地化完整。Live Activity 和 Dynamic Island 是体验增强，不应该成为 V1 的交付阻塞点。
