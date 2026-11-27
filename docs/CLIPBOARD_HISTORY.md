# Clipboard history — design (not implemented)

A local, searchable history of what the user copies on macOS: text, images and
files. This document fixes the design so the feature can be built without
changing the rest of the app.

## Principles

- **Local only.** History is stored on this Mac and never leaves it.
- **References by default, copies only on request.** Copying a file records
  *where the file is*, not its contents. A copy is kept only when the user pins
  the entry.
- **Opt-in.** The feature is off until the user turns it on.
- **Respect "do not record".** Entries marked `org.nspasteboard.ConcealedType`
  or `org.nspasteboard.TransientType` (password managers, Baddel's own paste
  fallback) are never stored. The user can exclude apps by bundle identifier.

## Capture

`NSPasteboard` has no change notification, so the history polls
`NSPasteboard.general.changeCount` a few times per second and reads the
pasteboard only when the count changes. This is unrelated to keyboard input.

## Entry model

```
Entry
  id              UUID
  createdAt       timestamp
  sourceBundleID  app that was frontmost at copy time, if known
  kind            text | image | files
  pinned          bool
  searchText      text used for search (see below)
  payload         one of:
    TextPayload     the string (plus RTF/HTML data when present)
    ImagePayload    path of the stored image blob, pixel size, thumbnail path
    FilesPayload    list of FileReference
  contentHash     to collapse repeated copies of the same content

FileReference
  bookmark        security-scoped bookmark data (survives moves and renames)
  lastKnownPath   for display, and as a fallback when the bookmark is stale
  displayName, byteSize, uti
  retainedCopy    nil, or the path of the copy kept because the entry is pinned
```

### References and the pin action

A file entry starts as references only. Consequences, shown honestly in the UI:

- if the source file is moved or renamed, the bookmark still resolves;
- if it is deleted or its volume is unavailable, the entry is shown as
  *missing* and cannot be pasted.

**Pin** is an explicit action that turns an entry into something durable:

- for files, the files are copied into Baddel's storage and `retainedCopy` is
  set; from then on the entry no longer depends on the source. If a source is
  already missing, the pin fails with a clear message instead of pinning a
  dangling reference;
- for text and images, the content is already stored; pinning exempts the entry
  from the retention limits;
- unpinning deletes the retained copy and returns the entry to a reference.

The size of a retained copy is shown before pinning, and total retained size is
shown in settings.

## Storage

- `~/Library/Application Support/Baddel/Clipboard/history.sqlite` — entries and
  an FTS5 index over `searchText`.
- `…/Clipboard/blobs/` — image data and thumbnails.
- `…/Clipboard/pinned/` — retained copies of pinned files.
- Files are created with owner-only permissions.

Retention: unpinned entries are removed after a configurable count or age
(for example 500 entries or 30 days). Pinned entries stay until unpinned.
"Clear history" removes everything unpinned; a second action removes pinned
entries too.

## Search

`searchText` is the text itself for text entries, the file names for file
entries, and empty for images in the first version (on-device text recognition
with Vision is a possible later addition). Search is prefix and substring
matching through FTS5, normalised for Arabic (tatweel and diacritics removed,
alef and yaa forms folded) so that Arabic queries match naturally.

## Interface

A panel opened by its own shortcut: a search field and a list, newest first,
pinned entries in their own section. Return pastes the selected entry into the
previously focused app; a button or shortcut pins and unpins. Like the Undo
panel, it is a non-activating panel so the target app keeps focus.

## Relation to the correction feature

The two features are independent. The clipboard history must ignore Baddel's
own transient paste-fallback entries (they carry the transient marker), and the
correction feature never reads the history.
