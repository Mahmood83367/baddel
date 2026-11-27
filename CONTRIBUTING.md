# Contributing

## Forks and pull requests

- When you fork on GitHub, leave **"Copy the `main` branch only"** selected.
  `main` is the only branch contributions should start from.
- Open pull requests against `main`. It is protected: changes arrive through
  pull requests, and the `macos` and `windows-core` checks must pass.
- This is a recommendation, not something the repository enforces. GitHub does
  not let a public repository restrict which branches are forked.

## License of contributions and copies

Baddel is under the [MIT License](LICENSE), Copyright (c) 2026 Mahmood.
Contributions are accepted under the same license. If you redistribute Baddel
or a modified version, in source or binary form, the MIT License requires you
to keep the copyright notice and the license notice — in practice, keep the
`LICENSE` file intact. Nothing here adds to or changes the license.

## Before opening a pull request

```bash
cd macos && swift test
```

```powershell
dotnet test windows/tests/Baddel.Core.Tests/Baddel.Core.Tests.csproj
dotnet test windows/tests/Baddel.Windows.Tests/Baddel.Windows.Tests.csproj
```

- Behaviour shared by the platforms belongs in
  [`shared/fixtures/cases.json`](shared/fixtures/cases.json), which every
  platform's tests run.
- Layout data is generated from the operating system's own tables
  (`tools/dump-macos-layouts.swift`, `baddel-wincheck --dump-layouts`). Do not
  hand-edit it, and do not assume two layouts match because their names do.
- Test fixtures must be clearly synthetic. Never commit real typed text,
  personal data, credentials or machine names.
- Diagnostics must never contain text read from or written to a field.

## CI

Public CI runs only on GitHub-hosted runners. No self-hosted runner is attached
to this repository, so pull-request code never runs on a private machine.
