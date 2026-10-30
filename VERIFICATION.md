# Verification — Storage Atlas

Current local release: **0.4.6 / build 11**, certificate-signed for local development. This document summarizes checks without publishing private scan data. Detailed local screenshots, indexes and reports are excluded from Git.

## Recorded checks

- 56 StorageCore tests passed on an Apple Silicon Mac using Swift 6.2.1. They cover allocation versus logical size, hard links, sparse files, symlink non-traversal, inaccessible paths, canonical scope handling, classification, SQLite checkpoints/restoration, navigation and treemap accounting.
- Release packaging, strict code-signature verification and bundle/privacy plist checks passed. The app is currently ad-hoc signed, not Developer ID signed or notarized.
- Native workflows exercised a synthetic filesystem fixture and a private saved global snapshot. Checks covered tree navigation, history, search, category filters, inspection, allocation conservation, partial/completed status and compact layout.
- Normal native map: 1416×752pt within 1440×868pt usable content. Compact map: 936×484pt within 960×600pt usable content. Optional panels do not resize the map.
- The explicit storage access notice and permission guide were inspected at normal and compact sizes. The notice has a distinct primary action and dismissal. The application never grants itself privacy permissions.
- A saved completed global traversal was restored successfully. Completion does not establish full disk coverage or exclusive recoverable space.

## Reproduce locally

```sh
swift test
./scripts/build-app.sh release
codesign --verify --deep --strict "dist/Storage Atlas.app"
plutil -lint Resources/Info.plist Resources/PrivacyInfo.xcprivacy
```

Quit Atlas before packaging. Do not overwrite a running signed bundle. The build does not start a scan; launching the app normally can start one.

For isolated native checks, create a labeled synthetic fixture with `scripts/create-ux-fixture.py`. The application supports `--fixture`, `--scan-path /absolute/folder`, `--no-auto-scan`, `--reduce-motion`, and `--verify-ux /absolute/output`. Keep output under `.impeccable/review/`, which is Git-ignored. Add `--verify-coverage-only` for the targeted normal/compact/coverage capture pass with an existing snapshot containing coverage notes. Development arguments are not a substitute for manual native task checks.

## Known limits

- The macOS 14 minimum is declared; older macOS releases and Intel execution have not been independently exercised locally.
- No post-Full-Disk-Access global scan is certified. Some system restrictions, excluded APFS snapshots/volumes and filesystem accounting differences remain possible.
- Finder/clipboard task completion, the Settings deep-link on every supported macOS, complete VoiceOver flows, formal contrast testing and authored motion timing are not fully certified.
- Recorded navigation/search timings were individual observations, not p95 guarantees. Large indexes can make some queries noticeably slow.
- The GitHub Actions workflow must pass on GitHub after publication; a local run does not certify hosted CI.
- Signed/notarized distribution, universal binaries and in-app updates remain future work.

## Public-source preparation

The MIT license and third-party notices are present. Private historical verification and implementation logs are retained only under ignored local evidence. Scan databases, screenshots, logs, build outputs and signing material must not be published. The publication audit records the latest local checks below.

Publication audit: a filtered copy of the Git candidate files passed **56 tests, zero failures**, release packaging, strict deep codesign and both plist checks. Ignore sentinels for local evidence, builds, databases, credentials and generated iconsets passed. A targeted credential/home-path scan of candidates found no matches; this is a bounded pattern scan, not a guarantee against every possible secret. CI YAML parses, and checkout v4.2.2's pinned commit was verified against the official repository. Hosted GitHub CI is pending. The local running app, scan index and privacy settings were untouched.


## 0.4.4 — live read-access checks and persistence

`swift test`: **60 tests, zero failures**. Four new tests cover readable/missing directories, live-denial-only notice decisions, unknown/mixed outcomes, deduplication, persisted timestamp/dismissal and newly lost access. Cached observations never authorize a current-session notice. Release packaging, strict deep signature verification and both plist lints pass.

A bounded background check opens/closes handles for three protected current-user directories without reading contents or entries. Available/unknown/checking states suppress the request; only a fresh actual denial can show it. This is a sampled read-capability check, not a Full Disk Access API or proof of the Settings toggle. No TCC database is inspected. Result/timestamp and dismissal persist in app UserDefaults; checking repeats on launch/activation and explicit recheck. Scope notes and saved scan issues no longer control the request.

Native normal/compact/coverage capture at `.impeccable/review/v0.4.4/read-access/ux-verification.json` completed. This particular signed local executable was denied all checked folders; it was not falsely recorded as Full Disk Access disabled. The user's Settings authorization was not changed or independently read: System Settings computer-use inspection failed (no window/timeout). The ad-hoc designated requirement contains the executable hash, so authorization of an earlier build cannot be assumed to cover replacements. Stable signed distribution is still planned.

Native dismissal removed the notice. Relaunch using the same bundle retained dismissal, confirmed by native accessibility and the persisted preference. `.impeccable/review/v0.4.4/persisted-access/ux-verification.json` records the follow-up capture. Normal/compact text and first-viewport coverage state are readable. Available/unknown behavior and restart persistence are covered by core tests; a real post-grant global scan and live Settings toggling remain unverified. No new global scan, user-file change, privilege escalation or privacy-setting modification occurred. Private captures remain ignored.


## 0.4.5 — index maintenance no longer holds scan completion

Readonly live diagnosis found the current global snapshot already committed complete while the UI still showed Saving index. A two-second process sample placed the active worker in StorageIndex.finish's obsolete-entry deletion. CPU activity and growing WAL confirmed database work; later observation showed idle CPU and a small WAL after it ended. This establishes a retention delay, rather than a paused enumerator. Private evidence is under `.impeccable/review/saving-index-sample.txt`; machine-specific data is not published.

`swift test`: **62 tests, zero failures**. New tests establish that finish publishes completion without retention, each maintenance batch deletes at most its entry limit, work resumes after interleaved scans, active scans/latest completed global/newest snapshots are protected, and a triggered maintenance failure atomically rolls back entries/notes without undoing the latest completion.

Retention is now optional indexed metadata maintenance after endScan, in 512-entry transactions with 50ms yields and background priority. Starting another scan cancels future batches. A maintenance failure is reported separately from scan success. Database pages are reusable; no VACUUM or claim of disk-space recovery is made. Existing allocated/logical accounting, coverage, checkpoints and user files are unchanged.

Release 0.4.5/build 9 packaging, strict deep signature and plist checks pass. The old live cleanup was allowed to finish before quitting; no scan was interrupted. Native saved-result verification completed at 20:04:03Z in `.impeccable/review/v0.4.5/saved-result/ux-verification.json`, with normal/compact/coverage captures. Compact visual inspection confirms the user's newly completed map restores with Scan finished and no active scan bar. No additional real global scan was run. New multi-million-row maintenance throughput and full UI lifecycle during those background batches were not measured; tests validate bounded transaction/retention behavior, and source wiring schedules it only after endScan. The existing permission limitation remains independent of this diagnosed saving delay.


## Confirmed privacy-denial root cause

Readonly unified privacy logs for the running 0.4.5 app explicitly report Failed to match existing code requirement for local.storageatlas.mac and kTCCServiceSystemPolicyAllFiles, followed by a service-policy denial. The requirement in the log is an older hash-pinned ad-hoc build; the current binary has a different hash. Current bundle signature verification passes, while evaluating the logged older requirement against it fails with code failed to satisfy specified code requirement(s). This upgrades the earlier signing hypothesis to a confirmed authorization-identity mismatch for these requests. Directory owners/modes/ACLs grant the current user read/search access for the checked user Library locations; deny-delete ACLs do not explain read failures.

Private evidence: `.impeccable/review/tcc-debug.log` and `tcc-diagnosis.json`. The exact path and running-process attribution were checked; no private TCC database was read or altered. A valid local Apple Development signing identity is available, but no key was used and neither signing nor privacy settings were changed in this diagnostic pass. Current packaging remains ad-hoc; stable certificate-backed packaging and a user-operated authorization of the exact new identity are required for a durable repair. See docs/ACCESS_DEBUGGING.md for reproduction and repair order. No new scan or source-runtime change; no additional core tests needed for documentation-only changes. This diagnosis does not attribute the whole volume-to-map gap.


## 0.4.6 — certificate-backed identity and verified permission continuity

The existing Apple Development identity was explicitly pinned in ignored local `.signing/` configuration. No private key was exported or Keychain access control changed. The build script now stages complete bundles, requires certificate-backed signing by default, pins the initial designated requirement/team, validates candidates against both pin and installed app, and refuses fallback or incompatible replacements. A first ad-hoc→development migration requires explicit opt-in; identifier-only requirements are not used. Reconfiguring a certificate retains the original requirement. Previous apps are archived in ignored `.build/app-backups/` rather than left as discoverable app copies.

Actual signed build 10 and build 11 have different code hashes and mutually satisfy their certificate-backed requirements. An ad-hoc same-identifier replacement is rejected. Missing Developer ID distribution configuration fails closed. Explicit CI-only ad-hoc packaging has its own name/channel marker and cannot replace an existing app. Normal staged replacement, compatibility validation and archive cleanup passed. Six signing-policy tests and all 62 StorageCore tests pass; scripts parse/compile and CI YAML parses.

With explicit action-time user approval, only Atlas's stale Full Disk Access entry was removed and replaced with the exact signed build 10. macOS Settings showed the Atlas toggle on. After Quit & Reopen, the actual app reported three protected user folders readable and zero denied. It was then rebuilt/replaced by the ordinary build script as build 11, without changing privacy settings again. The new running process still reports three readable, zero denied. This is observed permission survival across a real differently hashed signed update, not merely signature theory.

Private evidence: `.impeccable/review/v0.4.6/signing-verification.json`, build/signing-policy logs and `.impeccable/review/v0.4.6/after-update/ux-verification.json`. The native normal/compact/coverage check completed at 20:22:54Z with readAccessState=available and readAccessNoticeVisible=false. Saved map restoration passed; no full global rescan was run. Old denied notes/map remain historical until refresh. This does not certify every protected path or attribute all missing volume use.

Public distribution now requires the correct Developer ID Application certificate type, Hardened Runtime and timestamping; no Developer ID identity is currently available/configured here. Public certificate signing, notarization and an actual public-user update test remain unperformed. This is macOS publisher verification, not app login or a runtime auth service. No network/auth feature was added to Atlas.
