#!/usr/bin/env python3
"""A throwaway window with one text field holding fixture text, in a chosen toolkit.

usage: fixture_field.py TOOLKIT WIDGET TEXT_FILE OUT_FILE

TOOLKIT/WIDGET: gtk3 entry | gtk3 textview | gtk4 entry | gtk4 textview |
                qt5 lineedit | qt5 plaintextedit | qt5 textedit

The caret is placed at the end. The field's current text is written to OUT_FILE
(UTF-8, exactly as the toolkit reports it) whenever it changes, so a check can
compare bytes without reading the screen. The checks only ever edit this window.
"""
import os
import sys

toolkit, widget, text_file, out_file = sys.argv[1:5]
with open(text_file, encoding="utf-8", newline="") as handle:
    text = handle.read()


def write(current):
    with open(out_file + ".tmp", "w", encoding="utf-8", newline="", errors="surrogatepass") as handle:
        handle.write(current)
    os.replace(out_file + ".tmp", out_file)


if toolkit == "gtk3":
    import gi

    gi.require_version("Gtk", "3.0")
    from gi.repository import GLib, Gtk

    window = Gtk.Window(title="Baddel Check Host")
    window.set_default_size(560, 160)
    if widget in ("entry", "garbling-entry"):
        field = Gtk.Entry()
        field.set_text(text)
        read = field.get_text
        field.connect("changed", lambda *_: write(read()))
        if widget == "garbling-entry":
            # Stands in for an application that receives more than it was sent:
            # whenever Arabic text is inserted, three replacement characters
            # follow it. A correction must notice and put the original back.
            busy = []

            def garble(entry, new_text, _length, _position):
                if busy or not any("\u0600" <= c <= "\u06ff" for c in new_text):
                    return
                busy.append(1)
                GLib.idle_add(lambda: (entry.insert_text("\ufffd\ufffd\ufffd", entry.get_position() + len(new_text)), busy.clear()) and False)

            field.connect("insert-text", garble)

        def place():
            field.grab_focus()
            field.set_position(-1)
            write(read())
            return False
    else:
        field = Gtk.TextView()
        buffer = field.get_buffer()
        buffer.set_text(text)

        def read():
            return buffer.get_text(buffer.get_start_iter(), buffer.get_end_iter(), True)

        buffer.connect("changed", lambda *_: write(read()))

        def place():
            field.grab_focus()
            buffer.place_cursor(buffer.get_end_iter())
            write(read())
            return False

    window.add(field)
    window.connect("destroy", Gtk.main_quit)
    window.show_all()
    window.present()
    GLib.timeout_add(700, place)
    Gtk.main()
elif toolkit == "gtk4":
    import gi

    gi.require_version("Gtk", "4.0")
    from gi.repository import GLib, Gtk

    def activate(app):
        window = Gtk.ApplicationWindow(application=app, title="Baddel Check Host")
        window.set_default_size(560, 160)
        if widget == "entry":
            field = Gtk.Entry()
            field.set_text(text)
            read = field.get_text
            field.connect("changed", lambda *_: write(read()))

            def place():
                field.grab_focus()
                field.set_position(-1)
                write(read())
                return False
        else:
            field = Gtk.TextView()
            buffer = field.get_buffer()
            buffer.set_text(text)

            def read():
                return buffer.get_text(buffer.get_start_iter(), buffer.get_end_iter(), True)

            buffer.connect("changed", lambda *_: write(read()))

            def place():
                field.grab_focus()
                buffer.place_cursor(buffer.get_end_iter())
                write(read())
                return False

        window.set_child(field)
        window.present()
        GLib.timeout_add(700, place)

    application = Gtk.Application(application_id="org.baddel.CheckHost")
    application.connect("activate", activate)
    application.run([])
else:
    from PyQt5 import QtCore, QtGui, QtWidgets

    app = QtWidgets.QApplication(sys.argv[:1])
    window = QtWidgets.QMainWindow()
    window.setWindowTitle("Baddel Check Host")
    window.resize(560, 160)
    if widget == "lineedit":
        field = QtWidgets.QLineEdit()
        field.setText(text)
        read = field.text
        field.textChanged.connect(lambda *_: write(read()))

        def place():
            window.activateWindow()
            field.setFocus()
            field.setCursorPosition(len(read()))
            write(read())
    else:
        field = QtWidgets.QPlainTextEdit() if widget == "plaintextedit" else QtWidgets.QTextEdit()
        field.setPlainText(text)
        read = field.toPlainText
        field.textChanged.connect(lambda *_: write(read()))

        def place():
            window.activateWindow()
            field.setFocus()
            field.moveCursor(QtGui.QTextCursor.End)
            write(read())

    window.setCentralWidget(field)
    window.show()
    QtCore.QTimer.singleShot(700, place)
    app.exec_()
