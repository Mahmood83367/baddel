# Releasing

The version is the single line in [`VERSION`](../VERSION). Every platform reads
it at build time, and package names and the release tag are derived from it.

## Version rules

- **Every published update gets a new, higher version.** A feature release
  raises the minor version (0.1.0 → 0.2.0); a fix that ships on its own raises
  the patch version (0.2.0 → 0.2.1).
- **A published version is never rebuilt, re-uploaded or replaced.** If a
  package has to change after publication, publish a new version.
- The tag is `v<VERSION>` on the commit the packages were built from.

`tools/check-version.sh` enforces this and runs as the `version` job in CI. It
fails when the tag `v<VERSION>` already exists on a different commit, or when
`VERSION` is not higher than every published version. The first change after a
release therefore has to raise `VERSION`.

## Signing status

| | Packages so far | How to change it |
|---|---|---|
| macOS | Ad-hoc signed, **not notarized** | Set `BADDEL_SIGN_IDENTITY` to a Developer ID Application identity and `BADDEL_NOTARY_PROFILE` to a `notarytool` keychain profile. Notarization needs a profile created once with `xcrun notarytool store-credentials`; CI has no signing secrets, so signed builds are made locally |
| Windows | **Not code-signed** | Set `BADDEL_SIGN_THUMBPRINT` to a code-signing certificate thumbprint |

Signing is opt-in so that a release build never depends on, or exposes, a
private identity by accident. The packaging scripts write the actual status
into the `README.txt` inside each ZIP. Developer ID signing without
notarization was tried locally and works (hardened runtime, app runs), but
Gatekeeper still treats an unnotarized app as unidentified, so it is not the
default.

The scripts never weaken an operating-system protection: they do not remove
quarantine attributes, add Gatekeeper or SmartScreen exceptions, or change
security settings.

## Build the packages

From a clean checkout of `main` at the commit being released.

macOS (Xcode 15 or later):

```bash
cd macos && swift test && ./scripts/package-release.sh
```

Produces:

```
dist/Baddel-<version>-macos-universal.zip
dist/Baddel-<version>-macos-universal.zip.sha256
```

Windows (.NET 8 SDK, PowerShell):

```powershell
dotnet test windows/tests/Baddel.Core.Tests/Baddel.Core.Tests.csproj
dotnet test windows/tests/Baddel.Windows.Tests/Baddel.Windows.Tests.csproj
./windows/scripts/package-release.ps1
```

Produces:

```
dist\Baddel-<version>-windows-x64.zip
dist\Baddel-<version>-windows-x64.zip.sha256
```

Each ZIP contains one folder with the app, the license, `README.txt` and
`SHA256SUMS.txt`.

The same two scripts run in CI (`macos` and `windows-app` jobs) on every pull
request and on every push to `main`, and upload the results as the
`baddel-macos` and `baddel-windows` artifacts. Building from the release commit
on `main`, either locally or by downloading those artifacts from the `main`
run, gives the files to attach to a release.

The builds are repeatable but not bit-for-bit reproducible: signatures and
archive timestamps differ between runs, so the hashes belong to one specific
build. Publish the `.sha256` files produced by the same run as the ZIPs.

## Check the packages before publishing

```bash
cd dist && shasum -a 256 -c Baddel-*-macos-universal.zip.sha256 Baddel-*-windows-x64.zip.sha256
```

Then, on a real desktop for each platform:

- macOS: `macos/scripts/hotkey-e2e-check.sh` (needs a terminal with
  Accessibility access; uses throwaway TextEdit documents).
- Windows: `baddel-wincheck --engine --e2e <extracted Baddel.exe> --notepad --out results.txt`
  in a logged-in desktop session with English and Arabic layouts installed.

Record the outcome in [TESTING.md](TESTING.md).

## Publish

Publishing is a manual step, from the release commit on `main` only:

1. `tools/check-version.sh` passes on that commit.
2. Download the package artifacts of the CI run **for that exact commit**, and
   verify each ZIP against its `.sha256` and its inner `SHA256SUMS.txt`.
3. Create the release with tag `v<VERSION>` targeting that commit and attach
   the packages and their `.sha256` files. `gh release create` refuses a tag
   that already exists; never work around that.
4. Mark it as a pre-release for a preview, so that it reaches the preview
   update channel only.
5. State the signing status from the table above in the release notes.
