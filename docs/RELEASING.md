# Publishing a release

Users download a prebuilt DMG; they never compile the app. Releases are hosted at https://github.com/caua07/Storage-atlas/releases. A future landing page can use:

`https://github.com/caua07/Storage-atlas/releases/latest/download/StorageAtlas-macOS-arm64.dmg`

## Signing keys

Community releases use a persistent self-signed **Storage Atlas Community Releases** identity stored in the maintainer's Keychain. The public certificate is Resources/CommunitySigningCertificate.pem; the private key is never committed. This supplies stable code identity across updates but does not make the download Apple-notarized. Users may need macOS first-launch approval.

Sparkle has a separate Ed25519 update key in Keychain under account `storage-atlas`. Only its public key is embedded in Resources/Info.plist. Both archives and the appcast are signed; no file listings, index data or machine profile is sent to the update server. Never regenerate or rotate either key casually: existing installations depend on them. Keep secure recoverable backups outside Git. Losing keys can require a new manually installed bootstrap.

Local development keeps its own pinned Apple Development identity. The verified development app is not silently replaced by a community build. See SIGNING.md. A fork must use its own feed and update keys before distributing binaries.

## Maintainer workflow

1. Make the change. Increase `CFBundleVersion` and `CFBundleShortVersionString` in Resources/Info.plist. Run `swift test` and the signing-policy tests, inspect native changes, commit and push source.
2. On the maintainer's Mac with the persistent community signing identity and Sparkle update key, run:

```sh
python3 scripts/publish-release.py --publish
```

This builds a complete signed app with nested Sparkle components, creates DMG/ZIP/checksums, creates a draft release, publishes its assets, confirms public download URLs, and only then commits/pushes the signed appcast. A version is offered to installed apps when that feed becomes visible. Ordinary source commits are not app releases. The script refuses dirty tracked source or overwriting an existing release output.

For package-only review, omit `--publish`. That creates a final signed package but does not create a tag/release or change the live feed. Do not modify signed archives or feeds afterward; regenerate and re-sign them instead. Never replace the bytes of a published version. Fix mistakes with a higher build and new release.

Signing stays local: no private keys have been uploaded to GitHub Actions. CI tests/builds PRs using an explicitly labeled CI package, not a downloadable release. Public Apple Developer ID signing/notarization remains an optional later distribution channel; it is not required for this community route.

## Verify before broad distribution

Test a quarantined first download on a second Mac and an actual N→N+1 update. Both apps must satisfy the same certificate requirement, and Sparkle must reject modified feed/archive signatures. Ensure scans defer installation and saved metadata/preferences survive restart. Initial binaries are Apple Silicon only and require macOS 14+; Intel is not advertised.

The update feed is independent of the future landing page:

`https://raw.githubusercontent.com/caua07/Storage-atlas/main/updates/appcast.xml`

The initial app must already contain the updater. Older local 0.4.x builds need one manual replacement; subsequent community releases use the in-app flow.
