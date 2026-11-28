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

`tools/check-version.sh` enforces this in two modes:

| Mode | When | Rule |
|---|---|---|
| Ordinary (`tools/check-version.sh`) | every pull request and push — the `version` CI job | `VERSION` is a semantic version and is **not lower** than any published version. A version that is already published still passes, so documentation and other changes that publish nothing are not blocked; the output notes that it must be raised before the next release. |
| Strict (`tools/check-version.sh --release`) | when releasing — run by hand before tagging, and by the `release-version` CI job on every `v*` tag | The tag `v<VERSION>` either does not exist yet and `VERSION` is **higher** than every published version, or it points at exactly this commit. New content under an existing version is refused. |

Versions are ordered as semantic versions, including the pre-release part
(`0.2.0-preview.2` < `0.2.0-preview.10` < `0.2.0` < `0.2.1` < `0.10.0`), so a
preview cannot be followed by a lower-numbered one. The guard has its own tests
in `tools/test-check-version.sh`, which CI runs.

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

## The macOS installer package

`macos/scripts/package-pkg.sh` builds an installer for `/Applications/Baddel.app`.
Its file name says what it is:

| File | Meaning |
|---|---|
| `Baddel-<version>-macos-universal.pkg` | Signed with a Developer ID Installer identity **and** notarized. The only form that may be published. |
| `Baddel-<version>-macos-universal-TEST-ONLY-unsigned.pkg` | No signature. Validation only. |
| `Baddel-<version>-macos-universal-TEST-ONLY-not-notarized.pkg` | Signed but not notarized. Validation only. |

**An installer that is not signed and notarized is never attached to a
release.** macOS refuses to open such a package normally, and telling users to
get around that is not acceptable. Until a signed one exists, the ZIP remains
the macOS download.

What a signed installer needs, all already present in the keychain of the
machine that builds the release (the script uses them in place and reads no
credential):

| Variable | What it names | Status on the release machine |
|---|---|---|
| `BADDEL_SIGN_IDENTITY` | Developer ID **Application** identity, signs the app | Present (Health360 team) |
| `BADDEL_INSTALLER_IDENTITY` | Developer ID **Installer** identity, signs the package | Present (same team), since 0.2.2 |
| `BADDEL_NOTARY_PROFILE` | `notarytool` keychain profile for the same team | Present (`baddel-notary`), since 0.2.2 |

A signing identity is not a notarization credential; the profile is separate
and is created once with `xcrun notarytool store-credentials`.

CI has none of these, so its macOS package is the ad-hoc ZIP and its installer
is the `TEST-ONLY-unsigned` build, used to test installing on the runner.
A signed macOS release is therefore built on the release machine, from the
release commit:

```bash
cd macos
BADDEL_SIGN_IDENTITY="Developer ID Application: …" ./scripts/package-release.sh
BADDEL_INSTALLER_IDENTITY="Developer ID Installer: …" BADDEL_NOTARY_PROFILE="…" ./scripts/package-pkg.sh
```

If the notarytool profile is set up after the package was built and checked,
notarize that same file instead of rebuilding it:

```bash
BADDEL_NOTARY_PROFILE="…" macos/scripts/notarize-pkg.sh dist/Baddel-<version>-macos-universal-TEST-ONLY-not-notarized.pkg
```

It submits the package, waits for Apple's answer, staples and validates the
ticket, runs Gatekeeper's installer assessment, and only then writes
`Baddel-<version>-macos-universal.pkg` and its `.sha256`.

When a release is signed with the Health360 team's identity, say so in the
release notes, and say that a later change of signing team would require
users to approve Accessibility once more.

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

1. `tools/check-version.sh --release` passes on that commit. If it says the
   version is already published, raise `VERSION` in a pull request first.
2. Download the package artifacts of the CI run **for that exact commit**, and
   verify each ZIP against its `.sha256` and its inner `SHA256SUMS.txt`.
3. Create the release with tag `v<VERSION>` targeting that commit and attach
   the packages and their `.sha256` files. `gh release create` refuses a tag
   that already exists; never work around that.
4. Mark it as a pre-release for a preview, so that it reaches the preview
   update channel only.
5. State the signing status from the table above in the release notes.

Creating the release creates the tag, which starts a CI run on that commit
with the strict `release-version` job. Check that it passed.
