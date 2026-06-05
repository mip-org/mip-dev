# Changelog

## Unreleased

- `scripts/setup_mex_compilers.m` now takes an optional compiler name
  (`setup_mex_compilers(arch, 'clang')`) in addition to the architecture, and
  exports `CMAKE_C_COMPILER`/`CMAKE_CXX_COMPILER` (alongside `CC`/`CXX`) so a
  package's CMake builds use the same compiler as MEX. Defaults to `gcc`
  (Windows still uses MinGW), so existing packages are unaffected. Also dropped
  the Objective-C-only `-fobjc-arc` from `clang++.xml` (it warned on every C++
  source and isn't needed for the one Objective-C++ file that motivated it).
- `macos_arm64` mexopts now pin the deployment target to macOS 11.0
  (`-mmacosx-version-min=11.0` in `gcc_static.xml` and `g++_static.xml`).
  Previously no minimum was set, so each MEX inherited the *build runner's*
  macOS version as its minimum-load version (e.g. `minos 15.0` on the macos-15
  runner), refusing to load on older end-user Macs. 11.0 is the oldest
  Apple-Silicon macOS; the MEX then load on any Mac where MATLAB itself runs.
  Existing macOS packages keep their baked-in minimum until rebuilt.
- Added `clang.xml` and `clang++.xml` mexopts for `macos_arm64` — Apple Clang
  (Xcode) + libc++, deployment target 11.0. A clang alternative to the
  Homebrew-gcc `gcc_static.xml`/`g++_static.xml` for C++ packages where clang is
  the native toolchain (CGAL/libigl/embree) or Objective-C++ sources are
  involved; the channel default remains gcc. Flags are matched to the gcc
  mexopts (`-O3`, `-ffp-contract=off`, `-fwrapv`, frame pointers, …), except the
  legitimately compiler-specific ones (`-isysroot`/`-syslibroot`, libc++ vs
  static `libstdc++`). Produced MEX depend only on OS-provided
  `libc++`/`libSystem`, so end users need neither Xcode nor Command Line Tools.
- Added the `sedumi` package (1.3.8, upstream tag `v1.3.8` from sqlp/sedumi)
  for `linux_x86_64`, `macos_arm64`, and `windows_x86_64`. `compile.m`
  reproduces upstream `install_sedumi`'s 34 MEX targets linking `-lmwblas`,
  with static `libstdc++`/`libgcc` on Linux. Repo root and `conversion/` are
  on the default path; `examples/` is gated behind `--with examples` and
  `doc/` is dropped from the bundle. The MEX sources include f2c-translated
  K&R code, so the build pins `-std=gnu17` (the C23 default in GCC 15, used by
  macos_arm64's Homebrew toolchain, reads `()` as `(void)` and rejects the
  unprototyped calls; harmless on the pinned GCC 8.5 / MinGW 8.1.0 used for
  Linux/Windows). Ported from mip-staging#10, dropping the unsupported
  `macos_x86_64` architecture.
- Windows builds now use the MathWorks-certified MinGW-w64 8.1.0 instead of
  the runner's modern GCC, so `mex` builds the C gateway against a supported
  compiler (no more "unsupported MinGW" warning). A new build-job step
  installs the certified toolchain and exports `MW_MINGW64_LOC`, and
  `scripts/setup_mex_compilers.m` now selects MinGW as the session MEX
  compiler on Windows (mirroring the Linux/macOS `gcc_static.xml` setup).
  Per-package `compile_windows.m` scripts (fmm2d, fmmlib2d) no longer set
  `MW_MINGW64_LOC`/`PATH`, pass `-f mingw64.xml`, or pass
  `-fallow-argument-mismatch` (unneeded on gfortran 8) — removing duplicated,
  drifting toolchain setup. With the modern-GCC blocker gone, the Windows
  MATLAB floor drops from R2023b to R2023a (the oldest release certifying
  8.1.0) for wider forward compatibility. See `notes/MATLAB-MINGW.md`.
- Fixed `push-build.yml` failing with `fatal: bad object <BEFORE>` on any push
  carrying more than one new commit: the changed-files diff needs the push's
  BEFORE commit, but `fetch-depth: 2` only reached AFTER's immediate parent.
  Checkout now uses `fetch-depth: 0` (full history).
- Windows strip step now renames toolchain directories (`Move-Item` to
  `*.deleted`) instead of running the slow VS uninstaller and
  `Remove-Item -Recurse` over million-file trees. An NTFS same-volume rename is
  metadata-only, cutting the step from ~4 min to seconds. Mirrors the macOS
  strip step; the runner is ephemeral so leaving bytes on disk is fine. Added a
  "Verify strip (Windows)" gate (mirrors Linux) that fails the job if a
  compiler/linker still resolves under a stripped root, so a silently-failed
  rename can't let a non-self-contained package pass. The gate matches on
  resolved path (not bare name) so benign collisions — e.g. Git for Windows'
  GNU coreutils `link.exe` — don't trip it.
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
