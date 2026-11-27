# Baddel on macOS

Requires macOS 13 or later, on Apple silicon or Intel.

## Installing

There is one place for Baddel: `/Applications/Baddel.app`. Keep a single copy
there.

**Installer (`.pkg`).** Offered only for releases where the package is signed
with an Apple Developer ID and notarized by Apple. Open it and follow the
steps. It:

- copies `Baddel.app` to the Applications folder of the startup disk, and
  nowhere else, even if another copy of Baddel exists on the disk;
- asks you to quit Baddel if it is open, so it can be replaced. Quit it
  yourself first, including a copy from an earlier preview;
- runs no scripts: nothing in the package executes with administrator rights;
- installs no background service, launch agent or daemon;
- does not turn on opening at login and changes no permission.

**ZIP.** Unzip it and move `Baddel.app` to Applications yourself. The result is
the same.

A package that is not signed and notarized is never published as the
installer. If a file named `…-TEST-ONLY-…​.pkg` reaches you, it is a
validation build; macOS will refuse to open it normally, and it should not be
installed.

## First open

1. Open Baddel from Applications. It is a menu bar app: a keyboard icon near
   the clock, and no Dock icon.
2. Baddel shows a window explaining why it needs **Accessibility** access and
   opens **System Settings → Privacy & Security → Accessibility**. Turn Baddel
   on there. Baddel never changes that setting itself.
3. Press `⌥⇧Space` in a text field to try it.

## Upgrading from an earlier preview

Versions before the signed installer were signed "ad hoc", without a developer
identity. macOS identifies such an app by the exact build, so every preview
counts as a different app as far as Accessibility is concerned. After
upgrading you may see Baddel listed and switched on under Accessibility while
Baddel itself says access is not granted. That entry belongs to the old build.

To fix it in Baddel 0.2.1 or later, click **Remove Old Entry…** in Baddel's
access window and confirm, then turn Baddel on in the list again. This removes
only Baddel's own entry. In 0.2.0 and 0.1.0 that button does not exist: select
Baddel in the Accessibility list, press **–**, and add it again. From Terminal
the equivalent, for any version, is:

```bash
tccutil reset Accessibility app.baddel.Baddel
```

Also delete old copies of Baddel that you kept outside Applications
(Downloads, the Desktop), so that only one remains.

From the first release signed with a Developer ID onwards, macOS recognises
Baddel by that identity and keeps the approval across updates. If the signing
team ever changes, one more approval will be needed.

## Open at login

Available from 0.2.1. Off by default. To turn it on: menu bar icon → **Settings…** → **Open Baddel
at login**.

- It uses the standard macOS login-item mechanism for an app
  (`SMAppService`), the one shown in **System Settings → General → Login
  Items**. No helper, launch agent or administrator right is involved.
- It is offered only when Baddel runs from `/Applications/Baddel.app`.
- macOS may ask you to allow it; Settings then says it is waiting for your
  approval and opens Login Items for you.

To stop Baddel opening at login, untick the same checkbox, or remove Baddel
under **System Settings → General → Login Items**. Either way takes effect at
the next login and nothing is left behind.

## Uninstalling

1. Untick **Open Baddel at login** if you had turned it on.
2. Quit Baddel from its menu bar icon.
3. Move `Baddel.app` from Applications to the Trash.

Optional, to remove what Baddel stored:

```bash
rm -rf ~/Library/Application\ Support/Baddel      # clipboard history and custom layouts
```

```bash
defaults delete app.baddel.Baddel                   # settings
```

```bash
tccutil reset Accessibility app.baddel.Baddel       # its Accessibility entry
```

If you used the installer, this forgets its receipt (it removes no files):

```bash
sudo pkgutil --forget app.baddel.Baddel.pkg
```

## What was tested

See [TESTING.md](TESTING.md). In short: installing, upgrading over the 0.1.0
and 0.2.0 previews, the Open at Login switch and uninstalling are run on a
throwaway macOS machine in CI with an unsigned test package. A real logout and
login has not been performed, and the signed, notarized installer has not been
built yet.
