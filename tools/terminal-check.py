#!/usr/bin/env python3
"""End-to-end checks of Baddel in a terminal.

Each check starts its own interactive program in a new pseudo-terminal, types
synthetic text, presses the shortcut, and reads the edit buffer back through
the program's own supported hooks. It never presses Enter on a command or a
draft, and it runs with a throwaway home, start-up file and configuration, so
no personal shell configuration, history or running session is touched.

    tools/terminal-check.py zsh    --bin PATH --script shared/shell/baddel.zsh
    tools/terminal-check.py bash   --bin PATH --script shared/shell/baddel.bash
    tools/terminal-check.py pwsh   --bin PATH --script shared/shell/baddel.ps1 [--ssh HOST]
    tools/terminal-check.py claude --bin PATH [--ssh HOST --remote-dir DIR]

`--bin` is the packaged Baddel executable (macOS: Baddel.app/Contents/MacOS/Baddel,
Linux: baddel, Windows: Baddel.exe). With `--ssh HOST` the program runs on that
host in an SSH terminal and the paths are paths on that host.

The Claude Code check needs the `claude` command. It starts Claude Code with an
empty configuration directory and a placeholder API key; nothing is ever sent,
because no draft is submitted.

Prints one line per case and `RESULT pass` or `RESULT fail`. Output contains
only the synthetic test text.
"""
import argparse
import json
import os
import pty
import select
import shlex
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import fcntl
import termios

CTRL_T, CTRL_G, CTRL_U, CTRL_UNDERSCORE, CTRL_Z, CTRL_A, CTRL_E, CTRL_AT = "\x14", "\x07", "\x15", "\x1f", "\x1a", "\x01", "\x05", "\x00"
# What the shortcut under test sends in a terminal. Each check sets it: Baddel's
# own shortcut as that platform's terminals deliver it, or Ctrl+T as the fallback.
KEY = CTRL_T
OPTION_SPACE = "\u00a0"       # macOS Terminal, default settings: Option-(Shift-)Space types a no-break space
ESC_SPACE = "\x1b "           # the same key with "Use Option as Meta key"
CTRL_ALT_SPACE = "\x1b\x00"   # Ctrl+Alt+Space on Linux terminals
DUMP_KEY = "\x18\x04"  # Ctrl+X Ctrl+D, bound by the checks to "write the buffer to a file"
PLACEHOLDER_KEY = "sk-ant-api03-" + "baddel-terminal-check-placeholder-0000000000000000"


class Terminal:
    """A program running in its own pseudo-terminal."""

    def __init__(self, argv, env=None, cwd=None):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            if cwd:
                os.chdir(cwd)
            os.execvpe(argv[0], argv, env or os.environ)
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
        self.output = b""

    def pump(self, seconds):
        end = time.time() + seconds
        while time.time() < end:
            ready, _, _ = select.select([self.fd], [], [], 0.05)
            if not ready:
                continue
            try:
                data = os.read(self.fd, 65536)
            except OSError:
                return
            if not data:
                return
            self.output += data
            if b"\x1b[6n" in data:  # cursor position request
                os.write(self.fd, b"\x1b[1;1R")
            if b"\x1b[c" in data:  # device attributes request
                os.write(self.fd, b"\x1b[?1;0c")

    def send(self, text, settle=0.25):
        os.write(self.fd, text.encode("utf-8"))
        self.pump(settle)

    def wait_for(self, marker, timeout=30):
        end = time.time() + timeout
        while time.time() < end:
            if marker.encode() in self.output:
                return True
            self.pump(0.2)
        return False

    def close(self):
        try:
            os.kill(self.pid, 15)
            self.pump(0.3)
            os.kill(self.pid, 9)
        except OSError:
            pass
        try:
            os.waitpid(self.pid, 0)
        except OSError:
            pass
        os.close(self.fd)


def _short(value):
    text = repr(value)
    return text if len(text) <= 240 else text[:120] + " … " + text[-110:]


class Report:
    def __init__(self, title):
        self.failed = 0
        print(f"== {title}")

    def check(self, name, actual, expected):
        ok = actual == expected
        self.failed += 0 if ok else 1
        print(f"{'PASS' if ok else 'FAIL'}  {name}" + ("" if ok else f"\n      expected {_short(expected)}\n      actual   {_short(actual)}"))

    def finish(self):
        print("RESULT " + ("pass" if self.failed == 0 else f"fail ({self.failed})"))
        return 1 if self.failed else 0


def encoded(script):
    """A PowerShell script as an -EncodedCommand argument, so no quoting is lost on the way."""
    import base64
    return base64.b64encode(script.encode("utf-16-le")).decode("ascii")


def remote_powershell(host, script):
    return subprocess.run(["ssh", "-o", "BatchMode=yes", host, "powershell", "-NoProfile", "-EncodedCommand", encoded(script)],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)


class Files:
    """Reads and removes small files, locally or on the SSH host."""

    def __init__(self, ssh=None):
        self.ssh = ssh

    def read(self, path, timeout=8):
        end = time.time() + timeout
        while time.time() < end:
            if self.ssh:
                # `path` is one of this script's own fixed file names.
                done = remote_powershell(
                    self.ssh, f"if (Test-Path -LiteralPath '{path}') {{ [Convert]::ToBase64String([IO.File]::ReadAllBytes('{path}')) }}")
                if done.stdout.strip():
                    import base64
                    return base64.b64decode(done.stdout.strip()).decode("utf-8")
            elif os.path.exists(path):
                with open(path, encoding="utf-8") as handle:
                    return handle.read()
            time.sleep(0.1)
        return None

    def remove(self, path):
        if self.ssh:
            remote_powershell(self.ssh, f"Remove-Item -LiteralPath '{path}' -ErrorAction SilentlyContinue")
        elif os.path.exists(path):
            os.remove(path)


# The cases every shell runs. `keys` are typed into an empty prompt; the buffer
# is read back afterwards. Arabic text is typed as characters, the way a
# terminal delivers it.
def shell_cases(undo, selection):
    cases = [
        ("one press corrects the last word", "echo ugd;l" + KEY, "echo عليكم"),
        ("one press, then the shell's undo", "echo ugd;l" + KEY + "|" + undo, "echo ugd;l"),
        ("two quick presses correct the whole line", "hgsghl ugd;l" + KEY + KEY, "السلام عليكم"),
        ("Arabic typed for English, last word", "git سفشفعس" + KEY, "git status"),
        ("mixed line: only the last word changes on one press", 'echo "ugd;l" ugd;l' + KEY, 'echo "ugd;l" عليكم'),
        ("a slow second press is a new single press", "echo ugd;l" + KEY + "|WAIT|" + KEY, "echo ugd;l"),
        ("nothing to correct leaves the line alone", "   " + KEY, "   "),
        ("cursor in the middle: the word before it", "ugd;l hgsghl" + CTRL_A + "\x1b[C" * 5 + KEY, "عليكم hgsghl"),
    ]
    if selection:
        cases.append(("a selection of two words is corrected, not just the last word", selection, "echo عليكم السلام"))
    return cases


def run_shell_cases(terminal, files, dump, report, cases, undo_after_double, clear=CTRL_E + CTRL_U):
    for name, keys, expected in cases:
        terminal.send(clear, 0.3)
        for part in keys.split("|"):
            if part == "WAIT":
                terminal.pump(1.0)
            else:
                terminal.send(part, 0.9)
        files.remove(dump)
        terminal.send(DUMP_KEY, 0.4)
        report.check(name, files.read(dump), expected)
    # Undo after a double press must come back to exactly what was typed.
    terminal.send(clear, 0.3)
    terminal.send("hgsghl ugd;l" + KEY + KEY, 1.2)
    for _ in range(undo_after_double):
        terminal.send(cases[1][1].split("|")[1], 0.4)
    files.remove(dump)
    terminal.send(DUMP_KEY, 0.4)
    report.check(f"undo after a double press ({undo_after_double} step{'s' if undo_after_double > 1 else ''})", files.read(dump), "hgsghl ugd;l")
    terminal.send(clear, 0.3)


def check_zsh(args):
    report = Report("zsh command line")
    home = tempfile.mkdtemp(prefix="baddel-zsh-check-")
    dump, prompts = os.path.join(home, "buffer"), os.path.join(home, "prompts")
    with open(os.path.join(home, ".zshrc"), "w") as rc:
        rc.write(f"""PS1='ready> '
unsetopt zle_bracketed_paste 2>/dev/null
unset HISTFILE
BADDEL_BIN={shlex.quote(os.path.abspath(args.bin))}
BADDEL_HINT=none
{"BADDEL_KEY='^T'" if args.key == "ctrl-t" else ""}
source {shlex.quote(os.path.abspath(args.script))}
precmd() {{ print p >> {shlex.quote(prompts)} }}
_check_dump() {{ print -rn -- "$BUFFER" > {shlex.quote(dump)}.tmp; mv {shlex.quote(dump)}.tmp {shlex.quote(dump)} }}
zle -N _check_dump
bindkey '^X^D' _check_dump
""")
    # A preferences domain of the check's own, so the real settings are never read
    # or changed. "command" stores a shortcut no terminal can deliver (⇧⌘B).
    suite = f"app.baddel.check{os.getpid()}"
    if args.key == "command":
        subprocess.run(["defaults", "write", suite, "shortcutKeyCode", "-int", "11"], check=True)
        subprocess.run(["defaults", "write", suite, "shortcutModifiers", "-int", "768"], check=True)
    env = {"PATH": os.environ["PATH"], "HOME": home, "ZDOTDIR": home, "TERM": "xterm-256color",
           "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8", "BADDEL_SETTINGS_SUITE": suite}
    global KEY
    KEY = {"shared": OPTION_SPACE, "shared-meta": ESC_SPACE}.get(args.key, CTRL_T)
    print("    key under test:", {"shared": "Baddel's shortcut as Terminal sends it by default (no-break space)",
                                   "shared-meta": "Baddel's shortcut with Option as Meta (Escape, Space)",
                                   "command": "Ctrl+T, because the stored shortcut uses Command",
                                   "ctrl-t": "Ctrl+T set with BADDEL_KEY"}[args.key])
    terminal = Terminal(["zsh", "-i"], env, home)
    try:
        if not terminal.wait_for("ready> "):
            report.check("zsh starts", "no prompt", "prompt")
            return report.finish()
        # Ctrl+Space sets the mark at the end; twelve Left keys extend the region
        # back over the last two words.
        selection = "echo ugd;l hgsghl" + CTRL_AT + "\x1b[D" * 12 + KEY
        run_shell_cases(terminal, Files(), dump, report, shell_cases(CTRL_UNDERSCORE, selection), undo_after_double=1)
        with open(prompts) as handle:
            report.check("no command line was run", handle.read().count("p"), 1)
        status = subprocess.run([os.path.abspath(args.bin), "--terminal-key", "status"], env=dict(os.environ, BADDEL_SETTINGS_SUITE=suite),
                                stdout=subprocess.PIPE, universal_newlines=True).stdout
        if args.key in ("shared", "shared-meta"):
            report.check("loading the script turned automatic pass-through on", "on (automatic" in status, True)
        elif args.key == "command":
            report.check("status says the shortcut cannot reach a terminal", "not available" in status, True)
    finally:
        terminal.close()
        shutil.rmtree(home, ignore_errors=True)
        subprocess.run(["defaults", "delete", suite], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return report.finish()


def check_bash(args):
    report = Report("Bash command line")
    home = tempfile.mkdtemp(prefix="baddel-bash-check-")
    dump, prompts = os.path.join(home, "buffer"), os.path.join(home, "prompts")
    with open(os.path.join(home, "rc"), "w") as rc:
        rc.write(f"""PS1='ready> '
unset HISTFILE
bind 'set enable-bracketed-paste off' 2>/dev/null
BADDEL_BIN={shlex.quote(os.path.abspath(args.bin))}
BADDEL_HINT=none
{"BADDEL_KEY='\\C-t'" if args.key == "ctrl-t" else ""}
source {shlex.quote(os.path.abspath(args.script))}
PROMPT_COMMAND='echo p >> {shlex.quote(prompts)}'
_check_dump() {{ printf '%s' "$READLINE_LINE" > {shlex.quote(dump)}.tmp; mv {shlex.quote(dump)}.tmp {shlex.quote(dump)}; }}
bind -x '"\\C-x\\C-d": _check_dump'
echo "bash $BASH_VERSION unit=$_baddel_unit"
""")
    settings = os.path.join(home, "settings")
    os.makedirs(settings)
    if args.key == "command":
        with open(os.path.join(settings, "settings.json"), "w") as handle:
            json.dump({"Shortcut": "Super+space"}, handle)
    env = {"PATH": os.environ["PATH"], "HOME": home, "TERM": "xterm-256color", "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8",
           "BADDEL_SETTINGS_DIR": settings}
    global KEY
    KEY = CTRL_ALT_SPACE if args.key in ("shared", "shared-meta") else CTRL_T
    print("    key under test:", "Baddel's shortcut, Ctrl+Alt+Space (Escape, NUL)" if KEY == CTRL_ALT_SPACE else "Ctrl+T")
    terminal = Terminal([args.shell or "bash", "--noprofile", "--rcfile", os.path.join(home, "rc"), "-i"], env, home)
    try:
        if not terminal.wait_for("ready> "):
            report.check("bash starts", "no prompt", "prompt")
            return report.finish()
        version = [line for line in terminal.output.decode("utf-8", "replace").splitlines() if line.startswith("bash ")]
        print("   ", version[0].strip() if version else "bash version unknown")
        # Bash has no visible selection, so there is no selection case; after a
        # double press Readline needs two undo steps.
        run_shell_cases(terminal, Files(), dump, report, shell_cases(CTRL_UNDERSCORE, None), undo_after_double=2)
        with open(prompts) as handle:
            report.check("no command line was run", handle.read().count("p"), 1)
        if args.key in ("shared", "shared-meta"):
            report.check("loading the script left the integration marker", os.path.exists(os.path.join(settings, "terminal-integration")), True)
    finally:
        terminal.close()
        shutil.rmtree(home, ignore_errors=True)
    return report.finish()


def check_pwsh(args):
    report = Report("PowerShell command line (PSReadLine)")
    if not args.ssh:
        print("the PowerShell check runs on a Windows host: pass --ssh HOST")
        return 2
    files = Files(args.ssh)
    directory = args.remote_dir.rstrip("\\")
    dump, prompts = directory + "\\buffer.txt", directory + "\\prompts.txt"
    files.remove(dump)
    files.remove(prompts)
    shell = args.shell or "powershell"
    terminal = Terminal(["ssh", "-tt", "-o", "BatchMode=yes", args.ssh, shell, "-NoLogo", "-NoProfile"])
    try:
        terminal.pump(6)
        setup = [
            "[Console]::InputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)",
            "Set-PSReadLineOption -HistorySaveStyle SaveNothing",
            f"$env:BADDEL_BIN = '{args.bin}'; $env:BADDEL_HINT = 'none'; $env:BADDEL_SETTINGS_DIR = '{directory}\\settings'"
            + ("; $env:BADDEL_KEY = 'Ctrl+t'" if args.key == "ctrl-t" else ""),
            f". '{args.script}'",
            "Set-PSReadLineKeyHandler -Chord 'Ctrl+x,Ctrl+d' -ScriptBlock { $l = $null; $c = 0; "
            "[Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$l, [ref]$c); "
            f"[IO.File]::WriteAllText('{dump}', $l, (New-Object System.Text.UTF8Encoding($false))) }}",
            f"function prompt {{ Add-Content -LiteralPath '{prompts}' -Value p; 'ready> ' }}",
            "\"psreadline $((Get-Module PSReadLine).Version) powershell $($PSVersionTable.PSVersion)\"",
        ]
        for line in setup:
            terminal.send(line + "\r", 1.5)
        if not terminal.wait_for("ready> ", 20):
            report.check("PowerShell starts", "no prompt", "prompt")
            return report.finish()
        import re
        version = re.findall(r"psreadline [0-9][0-9.]* powershell [0-9][0-9.]*", terminal.output.decode("utf-8", "replace"))
        print("   ", version[-1] if version else "PSReadLine version unknown")
        before = (files.read(prompts) or "").count("p")
        global KEY
        # PSReadLine reads Ctrl+Alt as AltGr and would bind Ctrl+Alt+Space as plain
        # Space, so with the default shortcut the integration must fall back to Ctrl+T.
        KEY = CTRL_T
        print("    key under test:", "Ctrl+T set with BADDEL_KEY" if args.key == "ctrl-t"
              else "Ctrl+T, the fallback for the default Ctrl+Alt+Space, which PSReadLine cannot bind")
        files.remove(dump + ".keys")
        terminal.send("[IO.File]::WriteAllText('" + dump + ".keys', ((Get-PSReadLineKeyHandler -Bound | Where-Object Function -eq 'BaddelFix' | ForEach-Object Key) -join ','))\r", 2.0)
        report.check("the handler is bound to Ctrl+T and to nothing else (in particular not to Space)", files.read(dump + ".keys"), "Ctrl+t")
        files.remove(dump + ".keys")
        # Twelve Shift+Left keys select the last two words.
        selection = "echo ugd;l hgsghl" + "\x1b[1;2D" * 12 + KEY
        cases = shell_cases(CTRL_Z, selection)
        # In PSReadLine's Windows mode Home is the start of the line.
        cases = [(n, k.replace(CTRL_A + "\x1b[C", "\x1b[H\x1b[C"), e) for n, k, e in cases]
        run_shell_cases(terminal, files, dump, report, cases, undo_after_double=1, clear="\x1b")
        report.check("no command line was run", (files.read(prompts) or "").count("p"), before)
    finally:
        terminal.send("\x1b", 0.2)
        terminal.send("exit\r", 1.0)
        terminal.close()
        files.remove(dump)
        files.remove(prompts)
    return report.finish()


def check_claude(args):
    report = Report("Claude Code composer (external editor, Ctrl+G)")
    remote = bool(args.ssh)
    files = Files(args.ssh)
    if remote:
        directory = args.remote_dir.rstrip("\\")
        join = lambda name: directory + "\\" + name
    else:
        directory = os.path.realpath(tempfile.mkdtemp(prefix="baddel-claude-check-"))
        join = lambda name: os.path.join(directory, name)
    work, config, dump, mode = join("work"), join("config"), join("draft.txt"), join("mode.txt")
    state = {"hasCompletedOnboarding": True, "theme": "dark", "numStartups": 3,
             "customApiKeyResponses": {"approved": [PLACEHOLDER_KEY[-20:]], "rejected": []},
             "projects": {work.replace("\\", "/"): {"hasTrustDialogAccepted": True, "hasCompletedProjectOnboarding": True,
                                                   "projectOnboardingSeenCount": 5}}}
    if remote:
        # The editor is a small script: in "dump" mode it copies the draft out for
        # the check to read, otherwise it runs the packaged Baddel on it.
        editor = join("editor.cmd")
        script = (f"@echo off\r\nif exist \"{mode}\" (copy /y \"%~1\" \"{dump}\" >nul & del \"{mode}\" & exit /b 0)\r\n"
                  f"\"{args.bin}\" --fix-draft --hint none \"%~1\"\r\nexit /b 0\r\n")
        import base64
        payload = base64.b64encode(json.dumps({"editor": script, "state": json.dumps(state)}).encode()).decode()
        setup = (f"$d = '{directory}'; New-Item -ItemType Directory -Force \"$d\\work\", \"$d\\config\" | Out-Null; "
                 f"$p = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('{payload}')) | ConvertFrom-Json; "
                 "[IO.File]::WriteAllText(\"$d\\editor.cmd\", $p.editor, [Text.Encoding]::ASCII); "
                 "[IO.File]::WriteAllText(\"$d\\config\\.claude.json\", $p.state, (New-Object Text.UTF8Encoding($false))); 'ready'")
        if "ready" not in remote_powershell(args.ssh, setup).stdout:
            report.check("the test folder on the host is prepared", "failed", "ready")
            return report.finish()
        # Windows Terminal reports Ctrl+Alt+Space as a console key event. An SSH
        # terminal has no way to send one, so the shortcut itself is not pressed here.
        shared_key = None
        bindings = json.dumps({"bindings": [{"context": "Chat", "bindings": {"ctrl+alt+space": "chat:externalEditor"}}]})
        remote_powershell(args.ssh, f"[IO.File]::WriteAllText('{config}\\keybindings.json', '{bindings}', (New-Object Text.UTF8Encoding($false)))")
        command = (f"$env:CLAUDE_CONFIG_DIR='{config}'; $env:ANTHROPIC_API_KEY='{PLACEHOLDER_KEY}'; $env:VISUAL='{editor}'; "
                   f"$env:BADDEL_SETTINGS_DIR='{directory}\\settings'; "
                   f"$env:EDITOR='{editor}'; $env:DISABLE_AUTOUPDATER='1'; $env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC='1'; "
                   f"Set-Location '{work}'; & '{args.claude or 'claude'}'")
        terminal = Terminal(["ssh", "-tt", "-o", "BatchMode=yes", args.ssh, "powershell", "-NoLogo", "-NoProfile", "-EncodedCommand", encoded(command)])
    else:
        os.makedirs(work)
        os.makedirs(config)
        with open(os.path.join(config, ".claude.json"), "w") as handle:
            json.dump(state, handle)
        editor = join("editor.sh")
        with open(editor, "w") as handle:
            handle.write(f"""#!/bin/sh
# In "dump" mode: copy the draft out for the check to read. Otherwise: the packaged Baddel.
if [ -f {shlex.quote(mode)} ]; then cp "$1" {shlex.quote(dump)}.tmp && mv {shlex.quote(dump)}.tmp {shlex.quote(dump)}; rm -f {shlex.quote(mode)}; exit 0; fi
exec {shlex.quote(os.path.abspath(args.bin))} --fix-draft --hint "$(cat {shlex.quote(join('hint'))} 2>/dev/null || echo none)" "$1"
""")
        os.chmod(editor, 0o755)
        # Claude Code's own keybindings file, in the throwaway configuration, holding
        # the entry `--terminal-key claude` prints for Baddel's shortcut.
        isolation = {"BADDEL_SETTINGS_SUITE": f"app.baddel.check{os.getpid()}", "BADDEL_SETTINGS_DIR": join("settings")}
        snippet = subprocess.run([os.path.abspath(args.bin), "--terminal-key", "claude"], env=dict(os.environ, **isolation),
                                 stdout=subprocess.PIPE, universal_newlines=True).stdout
        with open(os.path.join(config, "keybindings.json"), "w") as handle:
            handle.write("\n".join(line for line in snippet.splitlines() if not line.startswith("#")))
        shared_key = ESC_SPACE if sys.platform == "darwin" else CTRL_ALT_SPACE
        env = {"PATH": os.environ["PATH"], "HOME": directory, "TERM": "xterm-256color", "LANG": "en_US.UTF-8", **isolation,
               "CLAUDE_CONFIG_DIR": config, "ANTHROPIC_API_KEY": PLACEHOLDER_KEY, "VISUAL": editor, "EDITOR": editor,
               "DISABLE_AUTOUPDATER": "1", "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"}
        terminal = Terminal([args.claude or "claude"], env, work)

    def draft():
        """Reads the composer through the same Ctrl+G hand-over, without changing it."""
        files.remove(dump)
        if remote:
            remote_powershell(args.ssh, f"Set-Content -LiteralPath '{mode}' -Value dump")
        else:
            open(mode, "w").close()
        terminal.send(CTRL_G, 2.5)
        return files.read(dump, 10)

    def clear():
        terminal.send("\x1b", 0.2)
        terminal.send("\x1b", 0.6)  # Esc twice clears the draft; nothing is submitted
        terminal.send(CTRL_E + CTRL_U, 0.4)

    try:
        if not terminal.wait_for("for shortcuts", 60):
            report.check("Claude Code starts", "no composer", "composer")
            return report.finish()
        terminal.pump(2)
        version = "" if remote else subprocess.run(
            [args.claude or "claude", "--version"], stdout=subprocess.PIPE, universal_newlines=True).stdout.strip()
        if version:
            print("   ", version)

        terminal.send("ugd;l hgsghl", 0.8)
        report.check("the check reads the draft back unchanged", draft(), "ugd;l hgsghl")
        terminal.send(CTRL_G, 2.5)
        report.check("Ctrl+G corrects the whole draft", draft(), "عليكم السلام")
        terminal.send(CTRL_UNDERSCORE, 0.8)
        report.check("Ctrl+_ restores the draft", draft(), "ugd;l hgsghl")
        clear()

        terminal.send("اثممخ صخقمي", 0.8)
        terminal.send(CTRL_G, 2.5)
        report.check("Arabic typed for English", draft(), "hello world")
        clear()

        # Baddel's own shortcut, bound in Claude Code's keybindings file to the same action.
        if shared_key:
            terminal.send("ugd;l hgsghl", 0.8)
            terminal.send(shared_key, 2.5)
            report.check("Baddel's shortcut, bound in keybindings.json, corrects the draft", draft(), "عليكم السلام")
            terminal.send(CTRL_UNDERSCORE, 0.8)
            report.check("and Ctrl+_ restores it", draft(), "ugd;l hgsghl")
            clear()
        else:
            print("NOTE  Baddel's shortcut through keybindings.json: not run (an SSH terminal cannot send Ctrl+Alt+Space as a key event)")

        terminal.send("ugd;l [Image #1] hgsghl", 0.8)
        terminal.send(CTRL_G, 2.5)
        report.check("an [Image #1] marker typed as text is kept", draft(), "عليكم [Image #1] السلام")
        clear()

        terminal.send("first line ugd;l\\\rsecond", 0.8)
        terminal.send(CTRL_G, 2.5)
        corrected = draft()
        report.check("a draft of two lines keeps its line break", (corrected or "").count("\n"), 1)
        clear()

        terminal.send("[Image #1]", 0.8)
        terminal.send(CTRL_G, 2.5)
        report.check("a draft with nothing to convert is left alone", draft(), "[Image #1]")
        clear()

        # A paste long enough for Claude Code to fold into "[Pasted text #1 +N lines]".
        # Claude Code hands the editor the pasted text itself, not the marker.
        pasted = "\n".join(f"error line {i}: file not found" for i in range(1, 31))
        terminal.send("\x1b[200~" + pasted + "\x1b[201~", 2.0)
        terminal.send(" اثممخ", 0.8)
        before = draft()
        report.check("the editor receives a folded paste as its full text", (before or "").startswith(pasted), True)
        if not remote:
            with open(join("hint"), "w") as handle:
                handle.write("arabic")
            terminal.send(CTRL_G, 2.5)
            report.check("pasted English stays when Arabic was the active layout", draft(), pasted + " hello")
            os.remove(join("hint"))
        clear()
        if not remote:
            report.check("nothing was submitted", _has_transcript(config), False)
    finally:
        terminal.send("\x03", 0.5)
        terminal.send("\x03", 1.0)
        terminal.close()

    # The setting as documented, without the check's own editor script: VISUAL
    # names the packaged Baddel directly. The corrected draft is read off the
    # terminal output here.
    direct = f"{args.bin if remote else os.path.abspath(args.bin)} --fix-draft --hint none"
    if remote:
        command = command.replace(f"$env:VISUAL='{editor}'; $env:EDITOR='{editor}'", f"$env:VISUAL='{direct}'; Remove-Item Env:EDITOR -ErrorAction SilentlyContinue")
        terminal = Terminal(["ssh", "-tt", "-o", "BatchMode=yes", args.ssh, "powershell", "-NoLogo", "-NoProfile", "-EncodedCommand", encoded(command)])
    else:
        env = dict(env, VISUAL=direct)
        del env["EDITOR"]
        terminal = Terminal([args.claude or "claude"], env, work)
    try:
        if terminal.wait_for("for shortcuts", 60):
            terminal.pump(2)
            terminal.send("ugd;l", 0.8)
            terminal.output = b""
            terminal.send(CTRL_G, 3.0)
            seen = terminal.output.decode("utf-8", "replace")
            # Claude Code on Windows writes right-to-left text in visual order.
            shown = "عليكم" in seen or "عليكم"[::-1] in seen
            report.check("VISUAL=<Baddel> --fix-draft corrects the draft", shown, True)
            if not shown:
                import re
                print("      terminal output:", repr(re.sub(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07]*\x07", " ", seen)[-400:]))
            terminal.send("\x1b", 0.2)
            terminal.send("\x1b", 0.6)
        else:
            report.check("Claude Code starts with VISUAL set to Baddel", "no composer", "composer")
    finally:
        terminal.send("\x03", 0.5)
        terminal.send("\x03", 1.0)
        terminal.close()
        if not remote:
            shutil.rmtree(directory, ignore_errors=True)
            subprocess.run(["defaults", "delete", isolation["BADDEL_SETTINGS_SUITE"]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) \
                if sys.platform == "darwin" else None
    return report.finish()


def _has_transcript(config):
    projects = os.path.join(config, "projects")
    for _, _, names in os.walk(projects) if os.path.isdir(projects) else []:
        if any(name.endswith(".jsonl") for name in names):
            return True
    return False


def main():
    if (sys.stdout.encoding or "").lower().replace("-", "") != "utf8":
        import io
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", line_buffering=True)
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("target", choices=["zsh", "bash", "pwsh", "claude"])
    parser.add_argument("--bin", required=True, help="the packaged Baddel executable")
    parser.add_argument("--script", help="the shell integration script")
    parser.add_argument("--key", choices=["shared", "shared-meta", "ctrl-t", "command"], default="shared",
                        help="which key to press: Baddel's own shortcut as a terminal delivers it (default), the same with "
                             "Option as Meta (macOS), Ctrl+T set through BADDEL_KEY, or the Ctrl+T fallback when the stored "
                             "shortcut uses Command")
    parser.add_argument("--shell", help="the shell program to start (default: the target's usual name)")
    parser.add_argument("--claude", help="the claude command (default: claude)")
    parser.add_argument("--ssh", help="run on this SSH host (Windows checks)")
    parser.add_argument("--remote-dir", help="an empty working folder on the SSH host")
    args = parser.parse_args()
    if args.target in ("zsh", "bash", "pwsh") and not args.script:
        parser.error("--script is required for shell checks")
    if args.ssh and not args.remote_dir:
        parser.error("--remote-dir is required with --ssh")
    return {"zsh": check_zsh, "bash": check_bash, "pwsh": check_pwsh, "claude": check_claude}[args.target](args)


if __name__ == "__main__":
    sys.exit(main())
