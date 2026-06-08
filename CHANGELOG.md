# Changelog

## Unreleased

- Dropped `-static-libstdc++`/`-static-libgcc` from the Linux `gcc`/`g++` mexopts:
  the MEX now dynamic-links `libstdc++`/`libgcc_s` (like it already does `libgfortran`)
  and lets MATLAB resolve them (all in `linux_skip_set`). The static linking was
  redundant defense — the GCC-8.5 pin caps `GLIBCXX` at 3.4.25 (within MATLAB's bundled
  `libstdc++`) and the strip-test gate catches any overshoot — and was inconsistent with
  `libgfortran`, whose `.a` is non-PIC and can't be static-linked anyway. Dynamic is
  uniform, matches stock, and avoids a second `libstdc++`/unwinder copy alongside
  MATLAB's. (macOS keeps static linking — MATLAB ships no GNU runtime there.) Verified on
  R2022a that a dynamic C++ MEX builds, loads, and runs. Also documents the macOS-vs-Linux
  GCC-version and static-link distinction in `notes/MACOS-DEPLOYMENT-TARGET.md`.

- Pinned the `macos_arm64` CI runner to `macos-14` (from `macos-latest`) and set the
  macOS `clang`/`clang++`/`gcc`/`g++` mexopts `MACOSX_DEPLOYMENT_TARGET` to `14.0`. A
  macOS MEX's real deployment floor is set by the statically-linked Homebrew bottles
  (`gmp`/`mpfr`; and `libgfortran`/`libstdc++`/`libquadmath` from Homebrew GCC), which
  are built for the runner's macOS — not by `-mmacosx-version-min` (which `dyld` does not
  even enforce at `dlopen`). `macos-latest` drifts upward (macOS 15 today → floor 15+);
  `macos-14` is the oldest arm64 runner Homebrew bottles exist for, giving floor 14+.
  `14.0` matches the bottle so the stamp is honest and the version-min warning stays
  meaningful. See `notes/MACOS-DEPLOYMENT-TARGET.md`.

- Removed `-w` from the macOS `g++` mexopts (both arches). It suppressed *all*
  linker warnings — including the `-mmacosx-version-min` mismatch warning, which
  catches an object or dependency built for a newer macOS than the 11.0 floor (a
  MEX that would fail to load on macOS 11), the macOS analogue of the glibc-floor
  check. The `-ld_classic` deprecation warning now shows too, doubling as a
  reminder to migrate off it. Consistent with leaving the `clang++` link warnings
  visible. See `notes/MACOS-MEX-CPP-LINKER.md`.

- Restored stock's C++ MEX API support in the macOS `clang++` mexopts
  (`LINKEXPORTCPP`/`cppMexFunction.map`, `-lMatlabDataArray`, libc++ via
  `-stdlib=libc++`) and added `-ld_classic` (as `g++.xml` already does) so the
  `cppMexFunction.map` export list works on Apple's new linker (`ld-prime`,
  Xcode 15+), which no longer honors `-U` for undefined export-list symbols.
  One static XML now builds both classic `mexFunction` and class-based
  `matlab::mex::Function` MEX. See `notes/MACOS-MEX-CPP-LINKER.md` — including how
  R2025b/R2026a fixed this differently (a symbol-triggered conditional relink in
  the `mex` driver) and when to drop `-ld_classic`.

- Dropped `-std=c++17` from the macOS `clang++` mexopts, leaving the C++
  standard unset like the channel's gcc/g++ mexopts (which dropped stock's
  `-std=c++11`). The standard is a per-package property declared at the call
  site: gptoolbox already passes `-std=c++17` in its `compile.m`, so the build
  is unchanged. Keeps the channel's toolchains uniformly std-neutral.

- Dropped `-fno-omit-frame-pointer` from the macOS `clang`/`clang++` mexopts.
  These target `-arch arm64`, and Apple's ARM64 ABI mandates the frame-pointer
  chain — clang keeps it even under `-fomit-frame-pointer` — so the flag is a
  no-op there; stock macOS clang omits it. (The macOS `gcc`/`g++` mexopts keep
  it, as it is meaningful for x86_64.)

- Dropped `-pthread` from the macOS `clang`/`clang++` mexopts. On Darwin it adds
  no `-lpthread` (pthreads live in `libSystem`) and only defines the `_REENTRANT`
  macro, which the system headers ignore; stock macOS clang omits it. (Linux
  keeps `-pthread` — it is required there and is in stock.)

- Dropped `-fPIC` from the macOS `clang`/`clang++` mexopts. Darwin compiles
  position-independent code by default for dylibs/bundles, so the flag is a
  no-op there; stock macOS clang omits it for the same reason. (Linux keeps
  `-fPIC` — it is required for ELF shared objects and is already in stock.)

- Reverted the macOS `clang`/`clang++` mexopts from weak-linking the MATLAB
  libraries (`-weak-lmx -weak-lmex -weak-lmat`) back to hard `-lmx -lmex -lmat`,
  matching stock and the channel's own gcc mexopts. The weak link was a vestige
  of the old MathWorks Mac template: a MEX only loads inside MATLAB, where
  `@rpath/libmx.dylib` always resolves, so weak-linking bought nothing and only
  degraded a missing-symbol error from a clean load failure to a NULL-pointer
  runtime crash. Verified on R2023b: hard/weak load identically.

- Documented the MEX-API compatibility axis in `notes/MATLAB-GCC.md` (with a
  cross-reference in `notes/MATLAB-GLIBC.md`): a MEX is forward-compatible only
  on the `libmx`/`libmex` + MEX-file-version axis, so the build MATLAB — not the
  GCC version — sets the minimum supported release. Corrects the note's earlier
  "GCC 8 → R2020b+" claim (true only for the libstdc++ axis) and adds a
  three-axis (glibc / compiler-runtime / MEX-API) summary table.

- Added `linux_x86_64` to the `gptoolbox` package. Same split build as macOS
  (CMake builds the static dependency libs; `mex()` links each MEX through the
  channel `gcc_static` mexopts), adapted for the ubi8 / GCC-8.5 container: CGAL,
  Boost, and OpenBLAS headers come from dnf (the Rocky repos added below;
  OpenBLAS only satisfies El Topo's configure-time `find_package(BLAS)` and is
  not linked in), and static `gmp`/`mpfr` are built from source into an
  ephemeral prefix `compile.m` owns (RHEL ships no `.a`; no `/usr/local`
  pollution). El Topo links MATLAB's Fortran BLAS (`-lmwlapack -lmwblas`).
  Everything static keeps the shipped binaries within the glibc-2.28 floor; a
  `libgomp` leaf is bundled if it appears. The dependency build (incl. embree 4
  and El Topo under GCC 8.5) was validated on a RHEL 8.10 container.
- Linux builds now add the Rocky 8 BaseOS/AppStream/PowerTools repos in the
  `build-package.yml` toolchain step. UBI 8's AppStream is a subset that lacks
  `boost-devel`, and EPEL's `CGAL-devel` requires that unversioned package, so
  CGAL/Boost couldn't resolve on UBI alone. Rocky 8 is a 1:1 RHEL 8 rebuild with
  open repos (same glibc 2.28 / GCC 8.5), so only RHEL8-compatible leaf packages
  are pulled — verified to not replace glibc/base. `gpgcheck=1` with the Rocky
  GPG key.
- Added the `gptoolbox` package (`master`, Alec Jacobson's Geometry Processing
  Toolbox) for `macos_arm64`. Built with Apple Clang: CMake builds the C/C++
  dependency static libs (predicates, tetgen, triangle, libccd, tinyxml2, embree
  with internal tasking, El Topo) and discovers header-only CGAL/Boost + static
  gmp/mpfr; `compile.m` then links each MEX with `mex()` so it goes through the
  channel mexopts. Ships the full feature set — CGAL, Embree, XML, El Topo, and
  the macOS-only impaste — ~59 MEX, all self-contained (only MATLAB + OS
  libraries). See `packages/gptoolbox/master/BUILD_NOTES.md`. Windows build to
  follow.
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
