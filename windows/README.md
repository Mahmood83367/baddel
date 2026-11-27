# Baddel for Windows

A notification-area app for Windows 10 and 11 (x64), built with .NET 8.

| Project | What it is |
|---|---|
| `src/Baddel.Core` | Platform-independent logic: layouts, conversion, planning, double-press detector, correction engine. No Windows dependency. |
| `src/Baddel.Windows` | Windows integration: edit-control messages, UI Automation, input languages, clipboard, `RegisterHotKey`. |
| `src/Baddel.App` | The app (`Baddel.exe`): tray icon, Undo popup, Settings, About. |
| `src/Baddel.WinCheck` | Developer tool that checks the engine and the running app against a throwaway window. |
| `tests/Baddel.Core.Tests` | Shared fixtures and engine tests. |
| `tests/Baddel.Windows.Tests` | Layout data against the system's layout DLLs, shortcut parsing, settings, popup placement. |

## Build, test, run

```powershell
dotnet test windows/tests/Baddel.Core.Tests/Baddel.Core.Tests.csproj
dotnet test windows/tests/Baddel.Windows.Tests/Baddel.Windows.Tests.csproj
dotnet run --project windows/src/Baddel.App
```

## Package

```powershell
./windows/scripts/package-release.ps1
```

creates `dist\Baddel-<version>-windows-x64.zip` and its `.sha256`. See
[docs/RELEASING.md](../docs/RELEASING.md).

## Desktop checks

In a logged-in desktop session (not over SSH or as a service — there is no
desktop to press keys on):

```powershell
dotnet build windows/src/Baddel.WinCheck -c Release
windows\src\Baddel.WinCheck\bin\Release\net8.0-windows\baddel-wincheck.exe `
  --engine --e2e <path to Baddel.exe> --notepad --out results.txt
```

The tool creates its own window with fixture text, never touches other
windows, skips the Notepad case if Notepad is already open, uses a temporary
settings folder, and writes only outcome codes to `results.txt`. Layout
switching is exercised only if both an Arabic and an English layout are
installed. The recorded results are in [docs/TESTING.md](../docs/TESTING.md).

How it works: [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md#windows).
