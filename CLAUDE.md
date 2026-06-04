# CLAUDE.md

Guidance for working in this repository.

## What this is

A MIP package channel. Packages live under `packages/<name>/<release>/` with
a `recipe.yaml` and (usually) a `mip.yaml` declaring supported architectures.
Builds run one `(package, architecture)` pair at a time via GitHub Actions.

## Layout

- `packages/<name>/<release>/` — package definitions.
- `scripts/` — Python/MATLAB helpers used by the workflows.
- `.github/workflows/` — build, scheduled, and issue-driven build triggers.
- `mexopts/`, `site/` — MEX compiler configs and the channel site.

## Conventions

- Record every notable change in `CHANGELOG.md`. Keep entries brief.
- Supported channel architectures: `any`, `linux_x86_64`, `macos_arm64`,
  `windows_x86_64`.
- Build requests are submitted via issues (title starts with `build`); each
  body line is `<name>@<release> <architecture>`. See `README.md` for details.
