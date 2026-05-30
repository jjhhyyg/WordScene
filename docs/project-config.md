# 词境 / Word Scene 项目配置

## 基本信息

```text
App 中文名：词境
App 英文名：Word Scene
Bundle ID：com.erikssonhou.leximemory
Apple Team ID：JU68L3U235
CloudKit 容器：iCloud.com.erikssonhou.leximemory
最低系统版本：iOS 18+、iPadOS 18+、macOS 15+
```

## 本地化

```text
UI 默认语言：跟随系统语言，不在 App 内提供独立语言开关
工程技术：Localizable.xcstrings 管理界面文案，InfoPlist.strings 管理系统显示名
开发语言：简体中文 zh-Hans
支持语言：简体中文 zh-Hans、英文 en、西班牙语 es
iOS / iPadOS 设置路径：Settings -> Apps -> 词境 / Word Scene -> Preferred Language
macOS 设置路径：System Settings -> General -> Language & Region -> Applications
macOS 生效规则：如果 App 已打开，修改单个 App 语言后需要退出并重新打开
```

## 视觉方向

```text
App 图标方向：Apple 原生、语言记忆、低饱和、不要卡通、简约
iOS 26+：默认采用系统 Liquid Glass / 液态玻璃视觉能力
iOS 25 及以下：保持系统原生样式
```

## 隐私与日志

```text
DeepSeek API Token：不保存到仓库，不写入文档，只由用户在 App 设置页输入并存入 Keychain
崩溃诊断上传：第一版不接入，也不在设置页显示开关
调试响应记录：仅 Debug build 可用，Release build 不保存、不显示、不同步、不导出
```

## 导入导出

```text
导出文件名规则：memory-book-export-YYYYMMDD.json
第一版导入导出范围：仅全量导入、全量导出
导出加密：第一版不支持
```

## 工程约定

```text
项目目录：/Users/erikssonhou/Documents/WordScene
Bootstrap 分支：codex/bootstrap-app
```
