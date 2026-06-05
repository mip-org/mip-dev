# Centralizing the channel build framework

Status: **planning / in flux.** This note records the target shape and a staged
path to it, so changes to `scripts/` and the workflows move *toward* a clean
channel ↔ engine split instead of away from it. It is the companion to
[`../scripts/README.md`](../scripts/README.md), which maps the scripts as they
exist today.

## Why

The goal (issue #13) is to support **multiple channels** — some hosted by us,
some by other users — without hand-syncing build logic into each one. That means
the reusable build machinery should eventually live in **one** place that every
channel consumes, leaving each channel repo to hold only its package
definitions and its own configuration.

Today everything is vendored into this repo. That is the right call *for now*
("things are still in flux"): we want to add packages and adjust the build
environment freely without round-tripping through another repo. This note keeps
us honest about the destination while we do that.

## The split we are aiming for

Classify every file in `scripts/` as one of:

- **Engine** — build/test/publish logic that any channel would run unchanged.
  This is what gets centralized.
- **Channel-specific** — this channel's policy: issue syntax, the supported-arch
  list, the `packages/<name>/<release>` discovery rules.

| Bucket | Files | Destination |
|---|---|---|
| **Engine — per-build pipeline** | `prepare_one.py`, `package_setup.py`, `upload_one.py`, `assemble_index.py`, `channel_config.py` | central repo |
| **Engine — MATLAB orchestration** | `bundle_one.m`, `test_one.m` | central repo (or fold into `mip`) |
| **Engine — MATLAB build helpers** | `setup_mex_compilers.m`, `bundle_runtime_libs.m`, `copy_and_sanitize_lib.m`, `dynamic_lib_ext.m`, `system_echo.m` | central repo (or fold into `mip`) |
| **Channel-specific** | `build_request_from_issue.py`, `affected_builds.py`, `scheduled_check.py` | stays in the channel (or a thin per-channel layer over an engine library) |

`mexopts/` and `notes/MATLAB-*.md` describe **toolchain policy** (pinned
compilers, glibc floor, MinGW certification). That policy is shared too and
should travel with the engine.

## The lift-out is only as cheap as the interface

The reason to do the mapping/classification *first* (this PR) is that the cost of
centralization is dominated by how clean the boundary is, not by moving files.
Two interfaces matter:

1. **Script CLIs** — the workflows call scripts by path with flags
   (`prepare_one.py --package-path … --architecture …`). As long as those
   command-line contracts are stable, the script bodies can move to another repo
   and the workflows only change *where they fetch them from*, not *how they call
   them*. Keep the CLIs stable; document them (done in `scripts/README.md`).

2. **The `mip.*` surface** — the channel uses only `mip.bundle` and the
   `mip(install|load|test|uninstall)` CLI (see README). Keeping the footprint
   that narrow is what lets `mip` and the channel evolve independently. Widening
   it (e.g. reaching into `mip.compile`/`mip.build` directly) should be a
   conscious decision, not drift.

## Should `mip.compile` / `mip.build` move into this repo?

Issue #13 floats temporarily copying `mip.compile` / `mip.build` here so "it's
all in one place."

**Recommendation: not yet.** Reasons:

- They are *not used directly* by this channel — only `mip.bundle` is, and it
  calls them internally. Copying them here would fork the package manager's
  internals into the channel and create exactly the sync burden we are trying to
  remove.
- `mip` is already consumed cleanly: pinned via `recipe.yaml` and checked out at
  build time (`build-package.yml` checks out `mip-org/mip` into `mip/`). That is
  the same consumption model a future central engine would use.
- The honest "one place" is the opposite direction: move the channel's *engine*
  scripts toward `mip` (or a sibling tools repo), not move `mip`'s internals into
  the channel.

**Revisit if** we find ourselves patching `mip.compile`/`mip.build` behaviour
specifically for channel builds and the round-trip through `mip-org/mip` becomes
the bottleneck. At that point, pin `mip` to an exact commit/tag here (instead of
a moving branch) so channel builds are reproducible, and upstream the build
changes into `mip` rather than vendoring them.

## Where the engine should ultimately live — two options

1. **Fold the engine into `mip`.** The package manager already owns
   compile/build/bundle/install/test. Adding the channel pipeline (`prepare`,
   `upload`, `assemble_index`, the MATLAB orchestration/helpers) makes `mip` the
   single dependency a channel needs. *Pro:* one repo, one version to track.
   *Con:* couples "package manager" and "channel CI" release cadences; grows
   `mip`'s scope.

2. **A dedicated engine repo** (e.g. `mip-org/mip-channel-tools`), consumed by
   each channel the same way `mip` is today (checkout + `addpath` / `python -m`).
   *Pro:* clean separation of concerns; channels pin a version. *Con:* one more
   repo to release.

Either way the consumption pattern is the same one already in `build-package.yml`
(checkout a pinned ref, put it on the path), so the migration is mechanical once
the boundary above is clean.

## Staged path

1. **Now (this PR).** Map + classify the scripts; document the CLI and `mip.*`
   contracts; write down the destination. No file moves — moving scripts means
   editing `.github/workflows/`, which should be a deliberate maintainer step.
2. **Stabilize the boundary.** Keep trigger logic depending on
   `build_request_from_issue.py`'s shared helpers (don't re-duplicate package
   discovery / arch parsing). Keep package `compile.m` scripts depending only on
   the documented MATLAB helper API. Resist widening the `mip.*` surface.
3. **Extract.** When the system settles, move the **engine** bucket to its chosen
   home and update the workflows to fetch it (a maintainer change, since the App
   can't edit workflows). The channel keeps only package definitions + the
   channel-specific trigger layer.
4. **Onboard a second channel** against the extracted engine to prove the
   boundary — the real test that sync is no longer needed.
