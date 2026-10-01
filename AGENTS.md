# Repository Guidelines

## Project Structure & Module Organization

`pw2401.ps1` is the PowerShell 7 entry point: it loads `lib/*.psm1`, initializes configuration, resolves aliases, and dispatches to `functions/*.ps1`. Command implementations and matching declarative `.psd1` test definitions live together in `functions/`. Shared configuration, logging, file, media, documentation, and testing helpers belong in `lib/`, which also contains the bundled font. `scripts/` holds standalone utilities. `tests/` contains fixtures and sample resources; `docs/` contains generated command documentation. `target/` is ignored output storage.

## Build, Test, and Development Commands

Run from the repository root using PowerShell 7; no compilation step is required.

```powershell
pwsh -NoProfile -File ./pw2401.ps1 help           # List commands and aliases
pwsh -NoProfile -File ./pw2401.ps1 docs           # Validate help and generate docs
pwsh -NoProfile -File ./pw2401.ps1 test           # Run PowerShell-only examples
pwsh -NoProfile -File ./pw2401.ps1 test -External # Include external dependency tests
```

Media tests require `ffmpeg` and `ffprobe` on PATH. Missing encoders, filters, or NVIDIA runtime support produce skips. Windows CI in `.github/workflows/docs-and-tests.yml` checks PowerShell syntax, generated documentation consistency, and both test modes.

## Coding Style & Naming Conventions

Use four-space indentation for PowerShell and preserve surrounding style. Follow `.gitattributes` LF line endings. Name commands with existing prefixes: `dir-*`, `ff-*`, `srt-*`, `img-*`, and `sys-*`; use Verb-Noun names for shared functions. Reuse `Write-LogMessage` and `$global:GlobalConfig.runtime` helpers. No formatter or PSScriptAnalyzer configuration is present.

Maintain comment-based help in each command's `.ps1`. Edit that source and regenerate documentation; do not hand-edit `docs/commands/*.md`.

## Testing Guidelines

The custom runner in `lib/Testing.psm1` executes `.EXAMPLE` commands linked through stable `# ExampleId:` markers to same-named `.psd1` files. Use lowercase, hyphenated case IDs such as `nested-extension-summary`. Keep PSD1 files declarative: define inputs and expected exit codes, output, and file assertions. Add cases for changed behavior; no numeric coverage threshold is configured.

Never modify fixtures in place. Cases run in isolated directories under `target/pw2401-tests/`, retaining reports and process output.
Safety and EXIF regressions also run from `tests/TestRegression.ps1`.

## Commit & Pull Request Guidelines

History mixes `feat: ...` messages with terse maintenance subjects. Prefer descriptive, imperative summaries such as `feat: add dir-info extension summary`. PRs should explain behavior changes, link relevant issues, report test results and skips, and include regenerated docs when help changes.

## Configuration & File Safety

`config.json` defines media extensions, fonts, and encoding settings. Runtime paths derive from the current working directory. Exercise rename, move, and cleanup commands only against disposable copies during development.
