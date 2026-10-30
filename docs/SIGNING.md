# Stable app identity

Code signing is a build-time signature on the app, not a login system. Downloading users do not need an Atlas account or an Apple developer account. The MIT license and source availability are unchanged.

Atlas must retain a certificate-backed identity across rebuilds and updates so macOS can recognize its existing privacy authorization. A matching display name or bundle identifier alone is insufficient.

## Local development

A signing certificate and its private key must already exist in your Keychain. Obtain/manage an Apple Development certificate through Xcode; Atlas never creates keys or changes Keychain access rules.

List valid identities and explicitly pin the selected certificate's SHA-1 fingerprint:

```sh
security find-identity -v -p codesigning
python3 scripts/app-signing.py configure development YOUR_CERTIFICATE_SHA1
./scripts/build-app.sh release
```

The `release` argument selects Swift optimization, while the default **development signing channel** uses your pinned development certificate. Configurations and the first signed build's designated requirement live under Git-ignored `.signing/`. Private keys stay in Keychain. Missing, expired or mismatched identities fail the build; there is no automatic fallback to another certificate or ad-hoc signing.

Every later signed candidate must satisfy the saved requirement and retain its signing team. Before replacing an installed bundle, packaging also tests the candidate against the installed app's requirement. Configuring a replacement certificate preserves the original requirement instead of resetting continuity.

Quit Atlas before packaging. The build stages and verifies a complete app before replacing it. Previous app data is archived under ignored `.build/app-backups/`, rather than leaving another visible app copy. The metadata index and app preferences are preserved.

## One-time migration from an old ad-hoc build

An existing hash-pinned authorization cannot recognize the new certificate-backed identity. After pinning the certificate, explicitly allow this initial development migration:

```sh
ATLAS_ALLOW_SIGNING_MIGRATION=1 ./scripts/build-app.sh release
```

This exception only permits a development migration from an ad-hoc requirement. It cannot override a mismatched certificate-backed installed identity or a distribution identity. Then remove the stale Atlas entry and add the exact new app in **System Settings → Privacy & Security → Full Disk Access**, enable it, and reopen Atlas. The user controls this authorization.

After that initial migration, ordinary `./scripts/build-app.sh release` rebuilds should retain access. Verify with **Coverage → Check read access again** in the actual app before rescanning. Never weaken the requirement to an identifier-only rule or alter TCC databases.

## Community downloads

Current GitHub releases use a persistent self-signed community identity, separate from local development. No paid Apple membership is required. The public certificate is committed; private keys stay in Keychain. First launch may require macOS approval. Sparkle independently verifies signed feeds and update archives. See [RELEASING.md](RELEASING.md).

## Optional Apple-notarized distribution

For Apple-notarized distribution, use a consistently configured **Developer ID Application** identity:

```sh
python3 scripts/app-signing.py configure distribution YOUR_DEVELOPER_ID_SHA1
ATLAS_SIGNING_MODE=distribution ./scripts/build-app.sh release
```

This channel requires a valid Developer ID certificate, enables Hardened Runtime and secure timestamping, pins the resulting designated requirement/team, and rejects incompatible replacements. It cannot silently ship a development or ad-hoc signature. Preserve this configuration securely on the release signing machine across releases; protect the private key and use consistent signing policy in CI. Certificate renewal must still satisfy the previously pinned requirement.

This optional channel additionally needs notarization and stapling. Do not distribute development or CI packages as production releases. The current local machine has a development identity; a Developer ID distribution identity has not been configured here.

## CI builds

Only explicit `CI=true ATLAS_SIGNING_MODE=ci` builds may use ad-hoc signing. They have a separate `Storage Atlas CI.app` output and an `AtlasBuildChannel=ci` marker. CI builds cannot replace an existing app through the packaging script. The current GitHub workflow tests/builds only; it does not upload or publish an app.

## Continuity verification

```sh
python3 -m unittest discover -s Tests/SigningTests -v
python3 scripts/verify-signing-continuity.py /path/to/first.app /path/to/second.app
```

Use different build numbers/code hashes. The check verifies both signatures, matching bundle/team identity, certificate constraints and mutual designated-requirement compatibility. Also grant the first build access, replace it with the second **without changing Settings**, and verify actual protected-folder reads. Signature continuity alone is not proof of every macOS authorization or access to every file. Revocation, user changes and OS policy can still affect access.
