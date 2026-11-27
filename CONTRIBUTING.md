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

```bash
dotnet test linux/tests/Baddel.Linux.Tests/Baddel.Linux.Tests.csproj   # on Linux
```

- Behaviour shared by the platforms belongs in
  [`shared/fixtures/cases.json`](shared/fixtures/cases.json), which every
  platform's tests run.
- Layout data is generated from the operating system's own tables
  (`tools/dump-macos-layouts.swift`, `baddel-wincheck --dump-layouts`). Do not
  hand-edit it, and do not assume two layouts match because their names do.
- The terminal integrations (`shared/shell/`, `TextFix` in both cores) share
  [`shared/fixtures/text-fix.json`](shared/fixtures/text-fix.json). Their
  end-to-end checks are `tools/terminal-check.py zsh|bash|pwsh|claude`, which
  start a separate shell or Claude Code with a throwaway configuration.
- Test fixtures must be clearly synthetic. Never commit real typed text,
  personal data, credentials or machine names.
- Diagnostics must never contain text read from or written to a field.

## Keep both language guides current

- Update the [English README](README.md) and [Arabic README](README.ar.md)
  in the same pull request when a change affects installation, usage,
  shortcuts, settings, supported platforms, or privacy.
- Review both guides before publishing any release. Check the download links,
  package and signing details, and the capabilities actually tested. Update
  the illustrated how-to video when the workflow it shows changes: edit and
  run `swift tools/render-demo-video.swift docs/media`, check the frames with
  its `--frames` option, and copy the same files to the download page.
- Each published update gets a higher number in `VERSION`. Use that number
  for the release tag, packages, and notes. Keep previously published versions
  and their checksums intact. The `version` CI job checks on
  every pull request that `VERSION` is not lower than any published version;
  a change that publishes nothing does not have to raise it. When a release is
  tagged, `tools/check-version.sh --release` requires a version that has not
  been published from any other commit.

## CI

Public CI runs only on GitHub-hosted runners. No self-hosted runner is attached
to this repository, so pull-request code never runs on a private machine.
