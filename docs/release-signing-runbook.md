# WordScene Release Signing Runbook

This runbook covers the current release blocker before manual smoke testing can
start. The project configuration is already set to automatic signing:

| Field | Value |
| --- | --- |
| Team ID | `JU68L3U235` |
| Bundle ID | `com.erikssonhou.leximemory` |
| CloudKit container | `iCloud.com.erikssonhou.leximemory` |
| iOS scheme | `WordScene` |
| macOS scheme | `WordSceneMac` |

Do not change `project.yml` to work around this blocker unless the Apple
Developer account itself has changed. The current failure is local Xcode account
and provisioning state, not a product-code failure.

## Current Blocker

`scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`
currently produces the iOS signed Release candidate, then fails the macOS
candidate with:

```text
No Accounts: Add a new account in Accounts settings.
No profiles for 'com.erikssonhou.leximemory' were found: Xcode couldn't find any Mac App Development provisioning profiles matching 'com.erikssonhou.leximemory'.
```

This means Xcode cannot access an Apple Developer account session that can create
or download a Mac App Development provisioning profile for the configured bundle
identifier and team.

## Restore Signing

1. Open Xcode.
2. Open Xcode Settings.
3. Open Accounts.
4. Add or re-authenticate the Apple ID that belongs to team `JU68L3U235`.
5. Select the team and download manual profiles if Xcode offers that action.
6. Open `WordScene.xcodeproj`.
7. Select the `WordSceneMac` target.
8. Confirm Signing & Capabilities uses team `JU68L3U235`.
9. Confirm iCloud / CloudKit capability still references
   `iCloud.com.erikssonhou.leximemory`.
10. Build the macOS Release candidate from Terminal:

```bash
scripts/internal/build_release_candidates.sh --allow-provisioning-updates --platform macos
```

If that command still fails, do not edit source code first. Read the last
signing error and confirm whether Xcode is missing the account, the certificate,
the provisioning profile, or access to the CloudKit container.

You can classify the latest release-candidate signing log without rerunning the
build. By default the script reads
`/tmp/WordSceneReleaseCandidates/logs/<platform>-release-candidate.log`; pass
`--log` only when diagnosing a different log file:

```bash
scripts/internal/diagnose_release_signing.sh \
  --platform macos
```

The release candidate gate runs the same diagnosis automatically when a platform
build fails and records the result in `docs/release-smoke-evidence.md`.

## Regenerate Candidate Evidence

After macOS signing succeeds, run the full non-manual gate:

```bash
scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all
scripts/test_verify_release_readiness.sh
```

Expected result:

- macOS Release candidate build: `PASS`
- iOS Release candidate build: `PASS`
- `docs/release-smoke-evidence.md` contains current candidate evidence for both
  platforms and no stale signing blocker for the same build.
- `scripts/test_verify_release_readiness.sh` passes script checks, token leak scan,
  macOS tests, and iOS generic build.

## Then Run Manual Smoke

Only after both signed candidates exist:

1. Follow `docs/release-smoke-test.md`.
2. Record translation loop, import/export, recovery, local-only fallback, and
   CloudKit sync results in `docs/release-smoke-evidence.md`.
3. Keep the DeepSeek token local to each device. It must not enter CloudKit,
   exports, logs, screenshots, or commits.
