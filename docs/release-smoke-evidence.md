## Release Candidate Build Evidence

Generated: 2026-05-29T17:24:53Z

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

## Non-Manual Release Gate

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Readiness script | macOS + iOS generic | local build host | 1 | PASS | `scripts/verify_release_readiness.sh` passed script syntax checks, shell regression tests, `git diff --check`, token leak scan, XcodeGen version-marker scan, macOS 69-test suite, and iOS generic build. |
| Candidate gate | macOS + iOS | local build host | 1 | BLOCKED | `scripts/run_release_candidate_gate.sh --platform all` records the macOS signing blocker, continues to build iOS, and exits non-zero until all requested platforms produce signed candidates. |
| DeepSeek live protocol smoke | API | local build host | 1 | PASS | `scripts/run_live_deepseek_translation_smoke.sh` used the ignored local token file, verified JSON Output with the real DeepSeek API, and returned a Chinese translation without printing the token. |

## Current Build Blockers

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Candidate build | macOS | local build host | 1 | BLOCKED | Xcode account/profile state is missing a Mac App Development provisioning profile for `com.erikssonhou.leximemory`; rerun `scripts/build_release_candidates.sh --allow-provisioning-updates --platform macos` after restoring the Apple Developer account session. |
