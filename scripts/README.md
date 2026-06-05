# `scripts/` — the channel build framework

This directory holds the glue that turns a package definition
(`packages/<name>/<release>/`) into a published `.mhl` on GitHub Releases and
an entry in the channel index. The `.github/workflows/` files are thin: they
set up runners and call into the scripts here. **The logic lives here.**

This README is a map of that logic. It also classifies each script as
**channel-specific** or **engine** (reusable across channels) — see
[`../notes/SCRIPTS-CENTRALIZATION.md`](../notes/SCRIPTS-CENTRALIZATION.md) for
why that split matters and where this is all heading.

> **Heads-up for refactors.** Every script below is referenced *by path* from a
> workflow (`python scripts/<x>.py`) or via `addpath('scripts')` in MATLAB.
> Renaming or moving a file means editing the workflow / package `compile.m`
> that calls it. Keep the entry-point filenames and their CLIs stable, or change
> the callers in the same PR.

## The pipeline at a glance

```
        trigger layer                 per-build pipeline (one (package, arch))
  ┌───────────────────────┐   ┌──────────────────────────────────────────────┐
  push  ─ affected_builds ─┐   │ prepare_one.py  → build/prepared/<name-ver>/   │
  issue ─ build_request… ──┼─▶ │ package_setup.py  (per-OS apt/brew/choco)      │
  cron  ─ scheduled_check ─┘   │ bundle_one.m → mip.bundle → build/bundled/*.mhl│
                               │ test_one.m   → mip install/load/test/uninstall │
                               │ upload_one.py → gh release upload              │
                               └───────────────────────────────────────────────┘
                                            │
                                  assemble_index.py → build/gh-pages/index.json → Pages
```

Each trigger resolves a set of `(package_path, architecture)` pairs and
dispatches `build-package.yml` once per pair. The per-build pipeline runs on the
runner matching the architecture.

## Trigger / dispatch layer — *channel-specific*

These decide **what to build**. They are tied to this channel's conventions
(issue syntax, the four supported arches, the `packages/<name>/<release>` layout)
and are the least reusable across channels.

| Script | Role | Entry points | Imports |
|---|---|---|---|
| `build_request_from_issue.py` | Parse a `Build …` issue body into dispatches; render the validation comment; expand `all` / `all-packages`. **Also the shared library** for package discovery. | `validate`, `apply` subcommands | (stdlib + yaml) |
| `affected_builds.py` | Map files changed in a push to the affected packages × their declared arches. | `--changed-files --dispatch-file` | `build_request_from_issue.arches_from_mip_yaml` |
| `scheduled_check.py` | Daily probe: run `prepare_one.py` for every pair; emit the pairs whose `.mhl` is missing or whose source hash drifted. | `--dispatch-file --summary-file` | `build_request_from_issue.{list_all_packages, arches_from_mip_yaml}`; subprocess `prepare_one.py` |

`build_request_from_issue.py` is the de-facto home of the channel vocabulary:
`SUPPORTED_ARCHITECTURES`, `list_all_packages()`, and `arches_from_mip_yaml()`.
The other two trigger scripts import from it rather than redefining those.

## Per-build pipeline — *engine (centralizable)*

These do **the build of one pair** and know nothing about issues or pushes.
They are the strongest candidates for a shared engine repo.

| Script | Role | Key outputs |
|---|---|---|
| `prepare_one.py` | Fetch source per `recipe.yaml` (git/zip), overlay channel files, validate version rules + arch support, compute the source hash, skip-if-already-published. | `build/prepared/<name>-<release>/` + `.source_hash` / `.release_version` / `.commit_hash` side files |
| `package_setup.py` | Run the per-OS `setup:` commands from the prepared `mip.yaml` (apt/brew/choco). | side effects on the runner |
| `bundle_one.m` | Find the single prepared dir, set up MEX compilers, call `mip.bundle`. | `build/bundled/<name>-<release>-<arch>.mhl` (+ `.mip.json`) |
| `test_one.m` | Install the `.mhl` (resolving deps from this channel), `load`, `test`, `uninstall`. | pass/fail |
| `upload_one.py` | Hash the `.mhl`, ensure the release tag exists, upload `.mhl` + `.mip.json`. | GitHub Release assets |
| `assemble_index.py` | Collect every published `.mip.json` across releases into `index.json` + copy `site/`. | `build/gh-pages/` → Pages |
| `channel_config.py` | Resolve `owner/repo`, release base URLs, and the release tag for an `.mhl`. Shared by `prepare_one`, `upload_one`, `assemble_index`. | — |

## MATLAB build-helper library — *engine, used by package `compile.m`*

These are added to the MATLAB path (`addpath('scripts')`) before a package's
`compile.m` runs, so package recipes call them directly. They are part of the
**public surface a recipe author depends on** — treat them as API.

| Script | Role | Called by |
|---|---|---|
| `setup_mex_compilers.m` | Select the per-arch MEX toolchain (pinned `gcc_static`/`g++_static` from `mexopts/`, or MinGW-w64 8.1.0 on Windows); export `CC`/`CXX`. | `bundle_one.m`, package `compile.m` |
| `bundle_runtime_libs.m` | Vendor a MEX file's dynamic-lib deps next to it and patch rpaths (`patchelf` / `install_name_tool`). Non-recursive — see `../notes/MEX-RUNTIME-LIBS.md`. | package `compile.m` (e.g. fmm2d, fmmlib2d) |
| `copy_and_sanitize_lib.m` | Copy one `.so`/`.dylib` and rewrite its SONAME / install-name + rpath. | `bundle_runtime_libs.m` |
| `dynamic_lib_ext.m` | Platform dynamic-lib extension (`so`/`dylib`/`dll`). | package `compile.m` |
| `system_echo.m` | Echo + run a shell command (logged). | `bundle_runtime_libs.m`, `copy_and_sanitize_lib.m` |

## The `mip.*` dependency surface

The channel touches the `mip` package manager (`mip-org/mip`, checked out into
`mip/`) through a **small, stable interface**:

| Call | Site | Purpose |
|---|---|---|
| `mip.bundle(pkgDir, '--output', out, '--arch', arch)` | `bundle_one.m:54` | Compile (internally via `mip.compile`/`mip.build`) and pack into `.mhl`. |
| `mip('install', …)` | `test_one.m:48` | Install the freshly built `.mhl`, resolving deps from this channel. |
| `mip('load' / 'test' / 'uninstall', name)` | `test_one.m:49-51` | Smoke-test the package in a stripped environment. |

`mip.compile` and `mip.build` (mentioned in issue #13) are **not referenced
anywhere in this repo** — they are internals of `mip` reached *through*
`mip.bundle`. Keeping our footprint at `mip.bundle` + the `mip(...)` CLI is what
makes `mip` swappable; widening it (e.g. calling `mip.compile` directly) couples
the channel to `mip`'s internals and should be a deliberate decision.

## Conventions

- **Build dirs** (all gitignored): `build/prepared/` (one subdir, the prepared
  source), `build/bundled/` (one `.mhl` + `.mip.json`), `build/gh-pages/` (the
  site), `build/scheduled-probe/` (scratch for `scheduled_check.py`).
- **Side files** written by `prepare_one.py` into the prepared dir drive
  skip-if-unchanged: `.source_hash` (recipe-tree hash combined with the resolved
  upstream commit), `.release_version`, `.commit_hash`.
- **Supported arches**: `any`, `linux_x86_64`, `macos_arm64`, `windows_x86_64`
  (defined once in `build_request_from_issue.py`).
- **`mip.yaml` stays block-scalar-free** (`|`/`>`): it is parsed by both Python
  here and `mip`'s MATLAB YAML reader, which doesn't support block scalars.
