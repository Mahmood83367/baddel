#!/usr/bin/env python3
"""A throwaway GTK window with one text entry holding fixture text.

usage: fixture_entry.py KIND TEXT_FILE OUT_FILE CARET [SEL_START,SEL_END]

KIND is plain, password or readonly. The entry's current text is written to
OUT_FILE whenever it changes, so a check can compare it without reading the
screen. The checks only ever edit this window.
"""
import sys

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk  # noqa: E402

kind, text_file, out_file, caret = sys.argv[1:5]
selection = sys.argv[5] if len(sys.argv) > 5 else None
with open(text_file, encoding="utf-8") as handle:
    text = handle.read()

window = Gtk.Window(title="Baddel Check Host")
window.set_default_size(560, 80)
entry = Gtk.Entry()
if kind == "password":
    entry.set_visibility(False)
    entry.set_input_purpose(Gtk.InputPurpose.PASSWORD)
if kind == "readonly":
    entry.set_editable(False)
entry.set_text(text)
window.add(entry)


def write(*_args):
    with open(out_file + ".tmp", "w", encoding="utf-8") as handle:
        handle.write(entry.get_text())
    import os

    os.replace(out_file + ".tmp", out_file)


def place():
    entry.grab_focus()
    if selection:
        start, end = (int(part) for part in selection.split(","))
        entry.select_region(start, end)
    else:
        entry.select_region(int(caret), int(caret))
    write()
    return False


entry.connect("changed", write)
window.connect("destroy", Gtk.main_quit)
window.show_all()
window.present()
GLib.timeout_add(700, place)
Gtk.main()
