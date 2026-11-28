# Correction rules

These rules are implemented in `BaddelCore` (Swift) and `Baddel.Core` (C#), are
the same on macOS and Windows, and are pinned by [`shared/fixtures/cases.json`](../shared/fixtures/cases.json).

## What gets corrected

| Trigger | Target |
|---|---|
| One press, text is selected | Exactly the selection |
| One press, no selection | The last word before the caret |
| Two presses within the window | The whole focused field |

**Last word.** A word is a run of non-whitespace characters, not a run of
letters, because punctuation keys produce Arabic letters (`;` is `ك`). Starting
at the caret, Baddel skips spaces and tabs backwards, then takes everything back
to the previous whitespace. The skipped spaces stay where they are and the
caret stays after them. A line break is never crossed: at the start of an empty
line there is no word and nothing happens. If the caret is inside a word, only
the part before the caret is used.

All positions are UTF-16 offsets, matching Accessibility text ranges. A range
that would split a surrogate pair (half of an emoji) is rejected.

## Conversion

Conversion is positional: each character is traced back to the key that
produces it on the source layout and replaced by what that key produces on the
target layout.

- Unshifted keys are preferred over shifted keys when a character appears twice.
- Multi-character outputs are matched longest-first. Arabic-PC has keys that
  type two characters (`b` → `لا`, `T` → `لإ`, `G` → `لأ`, `B` → `لآ`).
- If the target layout has nothing on a shifted key, the unshifted output of
  the same key is used: on the macOS Arabic layout `Fhf` becomes `باب`.
- Anything the source layout cannot type — emoji, other scripts, whitespace —
  passes through unchanged.
- Digits follow the layout. The macOS Arabic layouts type Arabic-Indic digits,
  so there `2024` typed on the wrong layout becomes `٢٠٢٤` and back. The
  Windows Arabic layouts type the same digits as the US layout, so digits are
  left alone on Windows.

**Known ambiguity.** On Arabic-PC, `لا` can come from the single key `b` or
from `g` then `h`. Converting Arabic back to English picks `b`, which is the
far more common case in English text. A word such as `light` typed on Arabic-PC
therefore comes back as `libt`.

## Direction

The text decides which layout it was typed on; the active layout is only a
tie-breaker.

1. Count **letters**: Latin letters against Arabic letters and marks. The
   script with more letters is the source.
2. If that is a tie (or there are no letters), count **layout-exclusive
   characters**: characters only one of the two layouts can type, such as `;`
   (US only) or `؟` and `٣` (Arabic only).
3. If that is still a tie, the script of the currently active layout is used.
4. If there is no active-layout information either, the correction is refused.

## Whole-field rule for mixed-script text

A field may contain both scripts — typically a correct Arabic sentence followed
by words typed on the wrong layout, or the reverse.

> The script with more evidence in the field (rule above) is treated as the
> mistyped one. The field is split at whitespace. A word made only of the
> *other* script is left exactly as it is. Every other word is converted.

Concretely, with Latin as the dominant script:

| Word | Result |
|---|---|
| Latin letters (`hgsghl`) | converted |
| No letters, e.g. a lone `,` | converted in the same direction (on Arabic-PC that key is `و`) |
| Arabic only, including its punctuation, e.g. `(مرحبا)` | untouched |
| Both scripts in one word (`ugd;lمر`) | converted; the Arabic letters pass through because the US layout cannot type them |

Examples:

| Field | After double press |
|---|---|
| `مرحبا hgsghl ugd;l` | `مرحبا السلام عليكم` |
| `hgsghl ugd;l (مرحبا)` | `السلام عليكم (مرحبا)` |
| `اثممخ صخقمي ok` | `hello world ok` |
| `اثممخ 01234567890` | `hello 01234567890` |

The same rule is applied to a selection, which is usually a single script.

Limits of this first rule, stated plainly:

- It converts one direction per operation. A field in which *both* scripts were
  mistyped needs two corrections on two selections.
- "More letters" is a heuristic. If most of a field is correct and only a few
  words are wrong, a double press converts the correct majority. Select the
  wrong words and press once instead — Undo restores the field if you get it
  wrong.
- A punctuation-only word next to a word of the other script is still
  converted.

The whole field is replaced in a single write, so one Undo restores it.

## Command lines and Claude Code drafts

The terminal integrations ([guide](TERMINAL.md)) use the rules above with two
differences:

- **Mixed text follows the active layout.** When the text has letters of both
  scripts, the script of the active keyboard layout is the source, whichever
  script has more letters. In `git commit -m "اثممخ"` the correct English
  outweighs the mistyped word, and the layout that is still active (Arabic)
  says which part is wrong. Without a known layout the letter count decides,
  as above.
- **Claude Code markers are kept.** In a draft, `[Image #1]`,
  `[Pasted text #1 +30 lines]` and `[...Truncated text #1 +120 lines...]` come
  back unchanged, and their letters are not evidence for either script.
- **Claude's previous reply is not the draft.** When Claude Code puts its last
  reply at the top of the file, everything up to and including the line
  `# ─── Write your reply below this line ───` is left out of the direction
  decision and comes back unchanged.

## When nothing is changed

Baddel refuses, and leaves the field untouched, when:

- the field is a password or other secure field;
- the focused element is not an editable text field, or its text or selection
  cannot be read;
- focus moved to another element between the first press and the correction;
- the text changed between planning and writing;
- there is no word before the caret, the field is empty, or the result would be
  identical to the input;
- the direction cannot be decided;
- the field is longer than 200,000 UTF-16 units;
- the app does not accept the write, or the text after the write is not exactly
  what was expected (in that case the layout is not switched and no Undo is
  offered).
