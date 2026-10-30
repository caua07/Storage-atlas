# Publishing the source

The source is prepared for an MIT open-source release. No Git repository or remote has been created by this preparation, and nothing has been pushed.

## Completed locally

- Root MIT license, short English README, contributor instructions and third-party notices.
- Preserved the vendored Taste MIT notice and pinned provenance.
- Git ignores private scan evidence, databases, credentials, signing material and generated builds.
- Machine-specific history retained locally under ignored evidence; public validation notes contain no personal paths or storage listings.
- A filtered source copy passed all 56 tests, release packaging, signature and plist verification. CI YAML parses; hosted execution is pending.
- CI tests and builds on macOS, with read-only repository permission and a pinned checkout action. It does not publish binaries or run a disk scan.

## First push

Create an empty GitHub repository under your chosen owner/name. From this project directory:

```sh
git init -b main
git add .
git diff --cached --stat
```

Review the staged files before committing. Do not force-add ignored evidence, scan indexes, secrets or local app bundles. Then commit, add your actual repository URL and push:

```sh
git commit -m "Initial MIT source release"
git remote add origin https://github.com/YOUR-USERNAME/YOUR-REPOSITORY.git
git push -u origin main
```

Check the first macOS Actions run after pushing. Do not upload the entire local folder as an archive: Git ignores are applied by Git, not arbitrary file upload tools.

## Source release versus app distribution

Normal local builds require a pinned development certificate; distribution builds require a pinned Developer ID Application identity. Ad-hoc signing is restricted to explicit, separate CI packages. See docs/SIGNING.md. Downloadable Developer ID signed/notarized releases, verified Intel/older-macOS support and in-app updates are not delivered yet. See DISTRIBUTION_UPDATE_PLAN.md before announcing those capabilities. The public source can be shared independently of that future work.
