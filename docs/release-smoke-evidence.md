## Non-Manual Release Gate

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Readiness script | macOS + iOS generic | local build host | 1 | PASS | `scripts/verify_release_readiness.sh` passed script syntax checks, shell regression tests, `git diff --check`, token leak scan, XcodeGen version-marker scan, macOS 72-test suite, and iOS generic build. |
| Candidate gate | macOS + iOS | local build host | 1 | BLOCKED | `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all` records the macOS signing blocker, continues to build iOS, refreshes current candidate evidence, and exits non-zero until all requested platforms produce signed candidates. |
| DeepSeek live protocol smoke | API | local build host | 1 | PASS | `scripts/run_live_deepseek_translation_smoke.sh` passed at 2026-05-29T18:13:40Z using the ignored local token file, verified JSON Output with the real DeepSeek API, and returned `你好世界` without printing the token. |

## Release Candidate Build Blocker

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Candidate build | macOS | local build host | 1 | BLOCKED | Signing diagnosis / macOS / BLOCKED / Xcode has no active Apple Developer account session; Mac App Development provisioning profile is missing for com.erikssonhou.leximemory / Next: Open Xcode Settings > Accounts and add or re-authenticate the Apple ID for team JU68L3U235; After account authentication, rerun scripts/build_release_candidates.sh --allow-provisioning-updates --platform macos /  See /tmp/WordSceneReleaseCandidates/logs/macos-release-candidate.log |

## Release Candidate Build Evidence

Generated: 2026-05-29T18:19:25Z

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Candidate build | iOS | local build host | 1 | PASS | /tmp/WordSceneReleaseCandidates/iOS/Build/Products/Release-iphoneos/Word Scene.app |

| Field | Value |
| --- | --- |
| Bundle ID | com.erikssonhou.leximemory |
| Version | 1.0.0 |
| Build | 1 |
| iPad orientations | UIInterfaceOrientationPortrait, UIInterfaceOrientationPortraitUpsideDown, UIInterfaceOrientationLandscapeLeft, UIInterfaceOrientationLandscapeRight |
| CloudKit containers | iCloud.com.erikssonhou.leximemory |
| iCloud services | CloudKit |
