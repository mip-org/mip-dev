# Changelog

## Unreleased

- Upgraded all GitHub Actions to Node 24-native major versions (`checkout@v5`,
  `setup-python@v6`, `upload-artifact@v7`, `download-artifact@v8`,
  `upload-pages-artifact@v5`, `deploy-pages@v5`, `matlab-actions/*@v3`) and
  dropped the `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24` workaround, which only
  forced the runtime without silencing the Node 20 deprecation warning.
- Stop bundling `libgfortran.so.5` in Linux MEX bundles: MATLAB ships it and
  resolves it via `LD_LIBRARY_PATH`, so the bundled copy was dead weight.
  `libgomp.so.1` is still bundled (MATLAB does not ship it). See
  `notes/MEX-RUNTIME-LIBS.md`.
- Added `fmmlib2d` 1.2.4 (Greengard & Gimbutas' Laplace/Helmholtz FMM in
  R^2), built with OpenMP for `linux_x86_64`, `macos_arm64`, and
  `windows_x86_64`.
- Build-request issues now use `<name>@<release> <arch>` syntax in the body
  instead of `packages/<name>/<version> <arch>`.
- `all` now expands only to the architectures declared in the package's
  `mip.yaml`; packages without a channel-side `mip.yaml` no longer dispatch
  every architecture.
- Build-request issues now close automatically after all build jobs are
  successfully dispatched.
