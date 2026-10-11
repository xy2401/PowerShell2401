# Repository Guidelines

## Project Structure & Module Organization

`pw2401.ps1` is the PowerShell 7 entry point: it loads `lib/*.psm1`, initializes configuration, resolves aliases, and dispatches to `functions/*.ps1`. Command implementations and matching declarative `.psd1` test definitions live together in `functions/`. Shared configuration, logging, file, media, documentation, and testing helpers belong in `lib/`, which also contains the bundled font. `standalone/` holds scripts with their own execution entry points, run directly with `pwsh -File`. `tests/` contains fixtures and sample resources; `docs/` contains generated command documentation. `target/` is ignored output storage.

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
Chrome launcher regressions in `tests/TestChromeLauncher.ps1` are invoked by the same regression entry point. Use isolated directories under `target/` and a replacement process-start function; never open a real browser or write to the user's actual launcher configuration in automated tests.

## Commit & Pull Request Guidelines

History mixes `feat: ...` messages with terse maintenance subjects. Prefer descriptive, imperative summaries such as `feat: add dir-info extension summary`. PRs should explain behavior changes, link relevant issues, report test results and skips, and include regenerated docs when help changes.

## Configuration & File Safety

`config.json` defines media extensions, fonts, and encoding settings. Runtime paths derive from the current working directory. Exercise rename, move, and cleanup commands only against disposable copies during development.

`standalone/chrome-profile.ps1` is a self-contained Windows PowerShell 7 launcher. Its instance configuration is fixed under the Windows user profile at `.pw2401/chrome.<instance>/launch.json`, with browser data in the adjacent `user-data/` directory. Keep `-Try` read-only, including when combined with configuration changes: it must apply all supplied options in memory before printing custom environment override statements followed by the full executable command and arguments, regardless of where `-Try` appears after the instance name. Do not dump inherited environment variables. Preview must not create directories, save settings, change the parent environment, or start a process.
With no arguments, show a few lines of brief usage and the `.pw2401/chrome.{Profile}` directory template, followed by all saved profiles in name order from the immediate `chrome.`-prefixed directories under `.pw2401/`, using the same preview computation and rendering as `-Try`. Keep this overview read-only and report individual profile errors without preventing previews of other profiles. Explicit `-Help` shows full comment-based help, including examples, without listing profiles.
