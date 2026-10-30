# Storage Atlas implementation plan

## Current direction

[PRODUCT.md](PRODUCT.md), [REFACTOR_PLAN.md](REFACTOR_PLAN.md), [UX_SPEC.md](UX_SPEC.md) and [DESIGN.md](DESIGN.md) define the product: a read-only global storage treemap with floating controls, optional tree/results/details, and explicit measurement limits. Do not restore the rejected permanent sidebar or add cleanup actions.

## Delivered baseline — 0.4.3 / build 7

- Startup System/Data namespace discovery, canonical paths, symlink non-traversal, shared hard-link accounting and atomic SQLite checkpoints.
- Global rectangular treemap, folder entry, tree disclosure, history, scoped search, category composition and details.
- Native app icon, bottom scan activity and enumeration/finalizing/saving feedback.
- Completed traversal distinguished from incomplete coverage; mapped allocation separate from volume-used/free/capacity and unattributed differences.
- Explicit read-access request with a prominent action, dismissible notice, and a user-operated Full Disk Access guide.

## Open-source preparation

The user selected MIT. Preserve the root license and vendored third-party notices. Keep private scan data, screenshots, historical local logs, credentials and build artifacts outside Git. Source publication does not require an updater or signed binary release. The macOS CI workflow tests and builds only; it neither scans a user's disk nor publishes releases.

Acceptance: root license; short English README; contribution and dependency notes; public-file privacy review; clean build/test from a filtered source copy; GitHub CI configured, with hosted execution still pending. No repository is created remotely and nothing is pushed without a publication request.

## Next planned expansion

[DISTRIBUTION_UPDATE_PLAN.md](DISTRIBUTION_UPDATE_PLAN.md) describes signed/notarized distribution and one-click updates via GitHub releases. The license decision is settled; repository/feed identity, Apple signing access and hardware support remain unresolved. Do not implement or publish that system merely because its plan exists.

## Resumption protocol

Read AGENTS.md, PRODUCT.md, this plan, VERIFICATION.md and relevant sources before implementation. For UI changes also read DESIGN.md and .impeccable/surface.md. Inspect current work and active scans before packaging. Preserve measured accounting and private evidence. Run meaningful core tests when filesystem/index/math changes; verify native interface changes in the actual app at normal and compact sizes. Record evidence and limits, then update this plan. Never modify scanned user files as part of analysis.

Preparation acceptance passed locally: filtered-source clean test/build, signature/plists, ignore-rule sentinels, targeted credential/personal-path review and CI YAML parse. PUBLICATION.md records the first-push procedure. There is no local .git directory or remote yet; no publish action was performed. Hosted CI and public binary distribution remain unverified/pending.


## 0.4.4 — verified read-access notices

Fix the incorrect assumption that any coverage note means missing Full Disk Access. Perform a bounded background read-capability check inside the running app on startup/activation and on explicit recheck. Open/close handles for Safari/Mail/Messages directories without reading contents; do not inspect TCC databases or use private permission APIs. Only a fresh access-denied result can offer an automatic request. Available, unknown, missing and checking states do not request permission. The result is a sampled capability observation, not the macOS Full Disk Access switch.

Persist observation/timestamp and dismissal in app UserDefaults; never reuse a cached observation as current authorization. Recheck after returning from Settings; newly observed loss of previously available access can reset dismissal. Keep old scan notes historical, offer refresh and explain remaining restrictions. Preserve floating UI and all scan accounting; no new global scan or permission modification. Acceptance: core decision/persistence tests, release packaging and normal/compact native capture with the real app's current access result.

Delivered 0.4.4/build 8: 60 tests pass; release/signature/plists pass; actual native normal/compact/read-access report and persisted-dismissal relaunch verified. The running build still observes real read denial, not proof of the Full Disk Access switch. System Settings inspection unavailable; no setting changed and no post-grant scan performed. Existing ad-hoc signing can invalidate previous build authorizations. See VERIFICATION.md for the precise distinction.


## 0.4.5 — scan completion independent of index retention

Live diagnosis of a repeated Saving index report: the snapshot was already committed complete. A process sample showed StorageIndex.finish executing its table-wide obsolete-entry deletion, with sustained CPU and WAL writes. That unbounded retention operation held the scan task open. Preserve the completed result and wait for the live old operation to finish before packaging.

Separate finish's atomic summary/issues commit from optional retention. Prune obsolete Atlas metadata in indexed batches of at most 512 entry rows, releasing the writer lock between transactions. Keep newest three snapshots, latest completed global baseline and active scans. Run batches at background priority after endScan, yield between batches, and cancel future maintenance when a new scan begins. Failed maintenance must not undo completion; failed batches roll back. No VACUUM or user-file cleanup. Acceptance: bounded/resumable retention and rollback tests, 62 core tests, package/signature checks, saved real completed-map restoration. Do not start another global scan for verification.

Delivered: 62 tests pass; release 0.4.5/build 9/signature/plists pass; newly saved real completed result restores with idle Scan finished at normal/compact widths. Existing long cleanup completed naturally before packaging. No new real scan was started. Large-scale throughput of the new batching path is unmeasured; bounded behavior, retention safety and rollback are tested.


## Confirmed access failure — stable signing required

Unified TCC logs and offline requirement validation confirm that the running app fails an older hash-pinned Full Disk Access code requirement. This is no longer just a suspicion. Local directory permissions permit reads; the current ad-hoc signature is valid but has a different identity. Private evidence is ignored, and docs/ACCESS_DEBUGGING.md records the process.

Repair order: configure explicit stable certificate-backed signing (a local development identity is available; public Developer ID distribution remains separate), build once, have the user remove/re-add the exact signed app to Full Disk Access, validate actual small reads from the same app, then run a global scan. Prove access survives a second consistently signed build. Do not repeatedly ship/re-authorize ad-hoc rebuilds or use a loose identifier-only requirement to sidestep identity checks. No permission, key or signature was changed during this diagnostic pass.


## 0.4.6 — durable signing repair

Replace implicit ad-hoc signing with pinned certificate-backed development/distribution channels. Save first designated requirement and team in ignored local signing configuration, preserve them across certificate reconfiguration, verify candidates against the pin and installed bundle, stage complete packages and refuse incompatible replacements. Permit explicit first ad-hoc→development migration only; do not use identifier-only rules. CI-only ad-hoc builds have separate output/metadata and cannot replace installed apps. Distribution requires Developer ID, Hardened Runtime and timestamp; actual public notarized distribution remains pending the certificate/release setup.

Use the existing development certificate for this machine, create two distinct signed builds, prove mutual requirement compatibility and reject an ad-hoc same-identifier replacement. With the user's action-time approval, replace only Atlas's stale FDA entry with the exact first signed app. Verify reads succeed, replace via ordinary build with the second signed app without changing Settings, and verify reads still succeed. Preserve scan index and preferences; no full scan required for continuity proof.

Local repair delivered and runtime-proven: stable signed build 10 received one approved FDA authorization; normal build replaced it with differently hashed build 11; three actual protected-directory reads remained available, zero denied, with no Settings changes between versions. Both mutual requirement checks and ad-hoc spoof rejection pass; 62 core and six signing-policy tests pass. Native saved-map normal/compact checks pass. Public packaging fails closed without Developer ID and is not claimed as a completed public release. Clarification requested by user: publisher signing is independent of open-source licensing and involves no Atlas login/account/backend. No public signing account/certificate setup has been authorized or completed.

## GitHub publication and updater — active

User authorized publishing the complete MIT source to https://github.com/caua07/Storage-atlas and implementing downloadable non-paid-membership releases plus in-app updates. Landing page comes later. This supersedes the earlier Developer-ID-only distribution assumption; preserve the verified development certificate for local builds and add a separate persistent community signing identity for downloadable builds (no ad-hoc per-release identity). Expect first-launch Gatekeeper approval, with no global security disabling.

Deliver: clean first Git commit/push; pinned Sparkle 2.10.1 with Ed25519 signed update archives/feed; GitHub release DMG/ZIP; stable feed and latest-download URLs; native one-click popup/manual menu/opt-out; scan-safe deferral and index shutdown; single-writer lock; atomic signed publishing. Preserve private keys locally and never publish private evidence, indexes, signing profiles or certificates containing personal development identity. Community release signing key is separate from development and update signing keys. No login, telemetry or landing page work. Initial hardware support Apple Silicon only; do not claim Intel runtime validation.

Acceptance: core/coordinator/single-writer tests; signature-tamper rejection; packaged nested Sparkle signing; normal/compact native popup verification; actual isolated N→N+1 Sparkle download/install/relaunch preserving metadata and signing identity; remote source/CI/release/feed verification. Publish artifacts before feed; no forced scan termination. Local 0.4.6 development app must remain usable; isolated test app/index for updater verification. Record actual limits. Repository identity and release/update channel are public, so no extra approval is required to push/publish. OS privacy changes remain separately controlled.
