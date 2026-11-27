# Updates

## What exists today

**A manual check, and an opt-in daily check. No installation.**

- *Check for Updates…* requests this project's public release list from
  GitHub (`api.github.com/repos/Mahmood83367/baddel/releases`), picks the
  newest release on your channel, and tells you. If there is a newer one it
  offers to open the release page in your browser.
- The daily check is off by default. When on, it makes the same request at most
  once every 24 hours and only changes the menu item's text.
- The request is anonymous: no cookies, no identifier, a `User-Agent` of
  `Baddel/<version>`. Nothing about you or your text is sent.
- Only releases hosted at `github.com/Mahmood83367/baddel/releases/` are
  considered; drafts and tags that are not versions are ignored.
- Baddel never downloads or installs anything by itself. You download the
  package and verify its SHA-256.

## Channels

| Channel | Sees |
|---|---|
| Stable (default) | Releases that are not marked pre-release on GitHub and whose version has no pre-release part |
| Preview | Those, and previews |

Version 0.1.0 is published as a pre-release, so the stable channel reports
"no stable release yet" until one exists.

## Versions

`VERSION` at the repository root is the single source of the version for every
package. Rules, enforced by `tools/check-version.sh` in CI:

- every published update has a higher version than every earlier one;
- a published version is never rebuilt or replaced: once `v<VERSION>` exists,
  only the commit it was published from may carry that version;
- tags and package names always match `VERSION`.

Versions are compared as semantic versions (`0.2.0-preview.1` < `0.2.0` <
`0.2.1` < `0.10.0`).

## Signed updates: what is built, and what is deliberately not

The checks an installer must make are implemented and tested in both the Swift
and the C# core, so that they exist before any installer does:

1. **Signature first.** An update manifest is a small JSON file with a detached
   ECDSA P-256 / SHA-256 signature. The signature is verified over the exact
   bytes, against public keys compiled into the app, *before* the JSON is
   parsed. Unsigned or wrongly signed data is never interpreted.
2. **Channel and version.** The manifest's channel must be the one asked for,
   and its version must be higher than the running one. A valid signature on an
   older manifest is refused, which blocks downgrades.
3. **Official location only.** Every package URL must be under
   `github.com/Mahmood83367/baddel/releases/download/`.
4. **Compatibility.** A package is chosen by platform, architecture and minimum
   OS version; if none fits, there is no update.
5. **Hash.** A downloaded file must match the manifest's size and SHA-256.

```json
{
  "schema": 1,
  "channel": "preview",
  "version": "0.3.0-preview.1",
  "packages": [
    { "platform": "macos", "arch": "universal", "minOS": "13.0",
      "url": "https://github.com/Mahmood83367/baddel/releases/download/v0.3.0-preview.1/Baddel-0.3.0-preview.1-macos-universal.zip",
      "sha256": "…", "size": 349687 }
  ]
}
```

Both implementations run the same fixture
([`shared/fixtures/updates.json`](../shared/fixtures/updates.json)), including
a manifest signed with a throwaway key generated only for that fixture, and
refuse it when a byte changes, the signature is damaged, the key is a different
one, the channel differs, or the version is not newer.

**What is not built:** downloading, unpacking, replacing the app, and rollback.

**Why nothing can be installed:** the list of trusted update keys in the apps
is empty. With no trusted key, verification fails with `noTrustedKey` for every
manifest, and a test asserts that the list is empty. This is intentional.

## Before automatic installation can be enabled

All of these, and not before:

1. An update signing key, created and kept offline by the maintainer; only its
   public half is added to the apps.
2. Platform code signing for the packages: Developer ID with notarization on
   macOS, Authenticode on Windows. An updater must not make the system's own
   checks weaker than a manual download.
3. A release step that produces and signs the manifest for each channel and
   attaches it to the release.
4. An installer per platform that stages the new version, verifies it again
   after unpacking, swaps it in, and keeps the previous version until the new
   one has started successfully.
5. Real update **and rollback** tests on each platform, recorded in
   [TESTING.md](TESTING.md): a good update, a tampered package, an interrupted
   update, and a new version that fails to start.

Automatic installation will stay opt-in, and code that is not signed by the
update key will never be executed.
