# Keyboard layouts

## Built-in layouts

Every built-in table is generated from the operating system's own layout data
and committed in [`shared/layouts`](../shared/layouts):

| Layout | Source | Used on |
|---|---|---|
| `us-english` | macOS "U.S." (identical to "ABC"); compared with Windows `00000409` and recorded as the same | macOS, Windows |
| `uk-english-mac` | macOS "British" | macOS |
| `uk-english-windows` | Windows `00000809` (United Kingdom) | Windows |
| `arabic-mac` | macOS "Arabic" | macOS |
| `arabic-pc` | macOS "Arabic – PC" | macOS |
| `arabic-windows-101` | Windows `00000401` (Arabic 101) | Windows |
| `arabic-windows-102` | Windows `00010401` (Arabic 102) | Windows |

Tools: `tools/dump-macos-layouts.swift` (reads with `UCKeyTranslate`) and
`baddel-wincheck --dump-layouts` (reads the tables inside the layout DLL that
Windows registers for the layout). Neither changes any system setting or loads
a layout into the session. On Linux nothing is committed: the app reads the
XKB layout and variant from the system at start.

Two layouts are never treated as the same because their names are similar. The
macOS British and Windows UK tables differ in four of the 47 keys and are kept
apart; each platform only offers its own.

### Choosing

| | English | Arabic |
|---|---|---|
| macOS | Automatic · US English / ABC · British | Automatic · Arabic · Arabic – PC |
| Windows | US English · UK English | Arabic (101) · Arabic (102) |

*Automatic* on macOS means: the active input source if it is of that script,
else the first enabled one, else the default (US English, Arabic).

### Which layout the system is switched to

The layout used for conversion and the layout the system is switched to are
the same layout. After a correction Baddel selects the installed input source
(macOS), keyboard layout (Windows) or XKB group (Linux) that is exactly the
chosen layout. If it is not installed or enabled, the text is still converted
with the chosen table and the keyboard is left as it was. A different layout
of the same language is never selected instead. On Windows, Settings says so
when a chosen layout is not installed.

### Compatibility

Settings saved by 0.1.0 have no English choice. They keep working: Windows
uses US English and macOS uses Automatic, which is what 0.1.0 did.

### Limits

- 47 keys: the ANSI alphanumeric block, unshifted and shifted. The extra ISO
  key is not described, so `\` and `|` on UK keyboards are left unchanged.
- Option / AltGr levels and dead keys are not mapped.

## Custom layouts

You can supply your own table as a JSON file. It is validated before use, and
a file that fails validation is ignored.

Put the file in:

- macOS: `~/Library/Application Support/Baddel/Layouts/`
- Windows: `%APPDATA%\Baddel\layouts\`

and restart Baddel. A valid layout appears in the matching selector in
Settings, marked as custom. (Linux reads XKB directly and does not use these
files.)

```json
{
  "id": "custom-my-layout",
  "name": "My layout",
  "script": "latin",
  "platformIds": {},
  "keys": [
    { "code": "Backquote", "base": "`", "shift": "~" },
    { "code": "Digit1", "base": "1", "shift": "!" }
  ]
}
```

The `keys` list must contain all 47 key codes; the built-in files show them in
order. `script` is `latin` or `arabic`.

### Validation

A file is rejected if any of these is true:

| Check | Code |
|---|---|
| `id` is not lowercase letters, digits and `-`, 1–64 characters, starting with `custom-`, or it repeats an existing id | `invalidId` |
| A standard key is missing | `missingKey` |
| A key code is not one of the 47 | `unknownKey` |
| A key appears twice | `duplicateKey` |
| A key has no unshifted output | `emptyBase` |
| An output is longer than 4 UTF-16 units | `outputTooLong` |
| An output has whitespace, a control character or half of a surrogate pair | `invalidCharacter` |
| The file is larger than 64 KB, or is not valid JSON in this format | (rejected) |

Two keys producing the same text is allowed and reported as a warning
(`duplicateOutput`): converting back picks the first such key.

At most 32 files are read. Built-in layouts cannot be replaced or shadowed,
because a custom id must start with `custom-`.

### What a custom layout cannot do

It has no system layout behind it, so Baddel converts with it but **does not
switch the keyboard** for that side.

### Status

The validation and loading are implemented and unit-tested on both platforms.
Choosing a custom layout in the Settings windows has not been exercised by
hand; see [TESTING.md](TESTING.md).
