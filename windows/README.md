# Baddel for Windows (in progress)

Windows correction is on the [roadmap](../docs/ROADMAP.md). What exists today:

- `src/Baddel.Core` — a C# port of the platform-independent logic: layout
  loading, layout conversion, direction detection, correction planning
  (selection / last word / whole field) and the double-press detector.
- `tests/Baddel.Core.Tests` — runs the shared fixtures in
  [`shared/fixtures/cases.json`](../shared/fixtures/cases.json) against the
  shared layout data in [`shared/layouts`](../shared/layouts), so both
  platforms are held to the same expected results.

```
dotnet test windows/tests/Baddel.Core.Tests/Baddel.Core.Tests.csproj
```

There is no Windows app yet: the global hot key, UI Automation text access,
layout switching and the Undo UI are still to be written.
