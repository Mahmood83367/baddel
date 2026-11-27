<img src="docs/media/baddel-logo.png" alt="Baddel logo" width="96">

# Baddel | بدّل

**Fix text typed with the wrong keyboard layout with a shortcut.**

Baddel is an open-source utility for typing in Arabic and English. If you meant to type `عليكم` and got `ugd;l`, press the shortcut to fix the text in place and keep typing.

[Download Baddel](https://mahmoood.com/baddel/) · [Watch the quick-start video](https://mahmoood.com/baddel/#demo) · [GitHub releases](https://github.com/Mahmood83367/baddel/releases) · [العربية](README.ar.md)

## Quick start

1. Try an editable field in TextEdit or Notepad with the other language’s keyboard layout active.
2. **Press the shortcut once** to correct the selected text. With no selection, Baddel corrects the last word before the cursor.
3. **Press twice quickly** to correct the whole field. After a successful correction, Baddel can switch to the matching keyboard layout when that layout is enabled in your operating system and switching is enabled in Baddel.
4. **Click Undo** to restore the previous text and keyboard layout while the same field is active and the corrected text is intact.

| Platform | Default shortcut | Where to find Baddel |
| --- | --- | --- |
| macOS 13 or later, Apple silicon and Intel | `⌥⇧Space` | Menu bar |
| Windows 10 or 11 (x64) | `Ctrl+Alt+Space` | Notification area by the clock |
| Linux (x64), X11 prototype | `Ctrl+Alt+Space` | After starting `baddel` in your desktop session |

Baddel skips password fields and fields it cannot edit safely. [Tested environments](docs/TESTING.md) · [Correction rules](docs/CORRECTION_RULES.md)

## Download and install

Choose the package for your platform from the download page. Each release lists its signing status and SHA-256 checksum. The current public preview is `0.2.0`. The `0.2.1` macOS installer is awaiting Apple signing and notarization for public distribution. [Download page](https://mahmoood.com/baddel/) · [Current release notes](https://github.com/Mahmood83367/baddel/releases/tag/v0.2.0)

### macOS

1. Extract the `0.2.0` archive and move `Baddel.app` to **Applications**. When a release offers a signed, notarized `.pkg`, open it to install Baddel in the same location.
2. Open Baddel from **Applications**. Its icon appears in the menu bar.
3. Enable Baddel in **System Settings → Privacy & Security → Accessibility**. Baddel needs this permission to edit the focused field.

If upgrading from an older preview leaves you with a stale Accessibility entry, select Baddel in the **Accessibility** list, press **−**, then add and allow the copy in **Applications**. In `0.2.1`, the permission window also has a **Remove Old Entry…** button. macOS warns when opening the current preview because it has no Apple notarization. Verify the published checksum and follow Apple's instructions if you choose to open it. [Apple's instructions](https://support.apple.com/en-us/102445)

Version `0.2.1` adds **Open Baddel at login** in Settings. Turn it on or off there or under **System Settings → General → Login Items**. [macOS guide](docs/MACOS.md)

### Windows

Extract the whole ZIP to a permanent folder and run `Baddel.exe`. The package includes the .NET runtime. Right-click the Baddel icon by the clock for Settings. SmartScreen may warn before opening the unsigned preview. [Release notes](https://github.com/Mahmood83367/baddel/releases/tag/v0.2.0)

### Linux

Extract the `x64` prototype and run `./baddel` from its folder in an X11 session. Automated testing used Ubuntu 24.04 and a GTK text field; the prototype has not been run on a real desktop yet. The limited Wayland path needs a desktop-configured shortcut and manual layout switching, and is untested. [Linux dependencies and setup](linux/README.md)

## Clipboard history on macOS

1. Open **Clipboard History** from the menu bar or press `⌥⇧V`. Enable **Keep clipboard history on this Mac**.
2. Copy text, images, or files as usual. To retrieve an entry, open the history and choose **Copy**, then paste it in your app with `⌘V`.
3. To keep a standalone copy of a file even if you delete the original, choose **Keep File Copy**.

History stays on your Mac and holds up to 100 recent items. Use **Clear Recent** to clear those items and **Delete** to remove a saved file copy. [Clipboard history guide](docs/CLIPBOARD_HISTORY.md)

## Layouts, updates, and privacy

- **Layouts.** Settings support common Arabic and English layouts, including Arabic–PC and British on macOS and Arabic (101), Arabic (102), US and United Kingdom on Windows. You can also add a custom JSON layout file, which Baddel checks before using it. [Layout guide](docs/LAYOUTS.md)
- **Updates.** Choose **Check for Updates** from the menu on macOS or Windows, or run `./baddel --check-updates stable` on Linux. macOS and Windows can check once a day if you enable it. Choose **Stable releases and previews** in Settings to include pre-releases. The current version lets you download and install new releases manually. [Updates guide](docs/UPDATES.md)
- **Privacy.** Corrections run on your computer when you press the shortcut. Optional clipboard history stays on your Mac. Update checks contact GitHub for release information.

## Contribute and license

When you fork the repository, start from `main` and open pull requests against it. See the contributing guide for building, running the checks, and keeping the two language guides current. [Contributing](CONTRIBUTING.md) · [Packaging releases](docs/RELEASING.md)

**Copyright © 2026 Mahmood.** Baddel uses the [MIT License](LICENSE). Keep the copyright and license notices when distributing copies or substantial portions of the software.
