# Debugging protected-folder read failures

A Full Disk Access toggle alone is not proof that the running executable matches the authorized app. Keep diagnostics local: logs and folder paths can disclose personal information.

## Establish which app is running

```sh
ps -axo pid,command | rg '[S]torageAtlas'
codesign --verify --deep --strict "dist/Storage Atlas.app"
codesign -dv --verbose=4 "dist/Storage Atlas.app"
codesign -d -r- "dist/Storage Atlas.app"
```

Check the exact path, bundle identifier, signature validity, signing authority and designated requirement. An ad-hoc signature commonly uses the executable hash as its identity. A replaced build can be validly signed while failing the older authorization requirement.

## Correlate an actual read check with the privacy log

Use **Coverage → Check read access again** in the actual Atlas process. A check from Terminal or a helper tests that process's permissions, which can differ from Atlas.

```sh
/usr/bin/log show --last 10m --style compact --info --debug \
  --predicate 'subsystem == "com.apple.TCC" AND eventMessage CONTAINS[c] "local.storageatlas.mac"'
```

Look for the service `kTCCServiceSystemPolicyAllFiles`, the actual Atlas process, and `Failed to match existing code requirement`. That combination identifies a stale code-identity authorization; ordinary filesystem read permissions do not repair it. Logs can be redacted or unavailable on some systems; absence of the message does not certify permission.

For each failed path, inspect ownership and ACLs with `ls -ldeO` on the directory and its ancestors, without listing file contents. Check that the process's user has read/search access. Some OS protections remain even after valid Full Disk Access, so distinguish those errors from an identity mismatch.

## Repair a confirmed identity mismatch

1. Establish a stable certificate-backed signing identity before granting access again. Use a consistent local development certificate for local rebuilds; use the planned Developer ID release signing for distributed builds. Keep the bundle identifier and signing requirements consistent. The packaging script now requires the appropriate pinned certificate and rejects incompatible replacements; see SIGNING.md.
2. Quit Atlas. In System Settings → Privacy & Security → Full Disk Access, the user should remove the stale Atlas entry and add the exact newly signed app, then enable it. Do not edit TCC databases or reset unrelated apps' permissions.
3. Reopen that same app and run the small access check first. Confirm the read succeeds and the identity-mismatch denial disappears before starting another full scan.
4. Rebuild/update with the same signing identity and verify that the access survives. Passing a signature check alone is insufficient.

Changing authorization is a user-controlled step. Stable signing cannot retroactively make a new identity satisfy an old hash-pinned authorization. Do not promise that repairing access accounts for every unattributed byte; snapshots, excluded volumes and other protections remain separate.

Apple documents [code requirements](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html) and recommends handling [actual filesystem access failures](https://developer.apple.com/forums/thread/114452) instead of treating TCC's private database as an API.
