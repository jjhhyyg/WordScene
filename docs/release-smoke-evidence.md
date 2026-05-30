## Non-Manual Release Gate

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| DeepSeek live protocol smoke | API | local build host | 1 | PASS | `scripts/run_live_deepseek_translation_smoke.sh` passed at 2026-05-30T08:46:16Z using the ignored local token file. Git commit `4ead34822af4`. It verified JSON Output with the real DeepSeek API and returned `你好世界` without printing the token. |
| Readiness script | macOS + iOS generic | local build host | 1 | PASS | scripts/verify_release_readiness.sh passed script syntax checks, shell regression tests, git diff --check, token leak scan, privacy manifest validation, required-reason API scan, privacy surface validation, CloudKit background-mode validation, XcodeGen version-marker scan, macOS tests, iOS simulator tests, iOS generic build, and unsigned macOS/iOS Release compiles. |
| Candidate gate | macOS + iOS | local build host | 1 | PASS | scripts/run_release_candidate_gate.sh recorded release readiness and signed release candidate evidence for all requested platforms. |

## Release Candidate Build Evidence

Generated: 2026-05-30T09:10:23Z

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Candidate build | macOS | local build host | 1 | PASS | /tmp/WordSceneReleaseCandidates/macOS/Build/Products/Release/Word Scene.app |

| Field | Value |
| --- | --- |
| Bundle ID | com.erikssonhou.leximemory |
| Version | 1.0.0 |
| Build | 1 |
| Git commit | 6123550c23e2 |
| iPad orientations | missing |
| CloudKit containers | iCloud.com.erikssonhou.leximemory |
| iCloud services | CloudKit |
| Privacy manifest | UserDefaults: CA92.1 |

## Release Candidate Build Evidence

Generated: 2026-05-30T09:10:31Z

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Candidate build | iOS | local build host | 1 | PASS | /tmp/WordSceneReleaseCandidates/iOS/Build/Products/Release-iphoneos/Word Scene.app |

| Field | Value |
| --- | --- |
| Bundle ID | com.erikssonhou.leximemory |
| Version | 1.0.0 |
| Build | 1 |
| Git commit | 6123550c23e2 |
| iPad orientations | UIInterfaceOrientationPortrait, UIInterfaceOrientationPortraitUpsideDown, UIInterfaceOrientationLandscapeLeft, UIInterfaceOrientationLandscapeRight |
| CloudKit containers | iCloud.com.erikssonhou.leximemory |
| iCloud services | CloudKit |
| Privacy manifest | UserDefaults: CA92.1 |
