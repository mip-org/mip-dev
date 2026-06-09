# gptoolbox build design notes

How this package is built, and why. Read this before changing `compile.m` or
`CMakeLists.txt`.

## Architecture: CMake builds the *libraries*, `mex()` builds the *MEX*

gptoolbox's `mex/` is a CMake project that, upstream, both fetches the C/C++
dependencies (libigl + CGAL/Embree/El Topo/etc.) **and** compiles the ~50 MEX
files itself. We deliberately split those two jobs:

1. **CMake builds only the dependency libraries** (predicates, tetgen,
   triangle, libccd, tinyxml2, embree, eltopo) as **static** libs, plus
   discovers the header-only deps (libigl, Eigen, cyCodeBase, CGAL, Boost) and
   the system static libs (gmp, mpfr). It emits a **manifest** (include dirs +
   categorized static-lib paths). CMake never touches MATLAB.
2. **`mex()` compiles and links each MEX**, driven by a hand-maintained
   `groups` table in `compile.m` that mirrors upstream's `compile_each(...)`
   calls (which source needs which libs + `-DWITH_*` defines).

### Why this split (Option A) over letting CMake build the MEX (Option B)

| | Option A (this) | Option B (CMake builds MEX) |
|---|---|---|
| MATLAB lib linking | `mex()` links by basename → **no patchelf** | `find_package(Matlab)` bakes absolute paths into `DT_NEEDED` → needs a Linux patchelf fixup |
| `find_package(Matlab)` | not used | relies on gptoolbox's bundled `FindMatlab` version map (breaks when CI MATLAB > the map; bit us locally on R2025b) |
| Toolchain | the channel's `gcc`/`g++` mexopts (static libstdc++/libgcc), same as every other package | CMake's own; static linking + ABI must be re-managed |
| Source→lib/define map | **hand-maintained** in `compile.m` (the cost) | read directly from upstream `compile_each` (no duplication) |

We accept the one cost of A — keeping the ~12-group table in sync with
upstream's `mex/CMakeLists.txt` — in exchange for never needing patchelf or
`find_package(Matlab)`, and for binaries built exactly like the rest of the
channel. Upstream regroupings surface as **loud build failures** on the
scheduled build, not silent breakage. libigl is pinned, so drift is rare.

## ABI rule (important)

The dependency **C++** libraries (embree, tetgen, triangle, tinyxml2, eltopo)
must be built with the **same compiler family** as `mex()` uses, so their C++
runtime matches (libstdc++ vs libc++ vs MSVC-STL). The deps CMake therefore
uses the mex toolchain: `CC`/`CXX` exported by `scripts/setup_mex_compilers`
on Linux/macOS, and the MSVC generator on Windows. The **C** libraries
(predicates, ccd, gmp, mpfr) are C-ABI and compiler-agnostic. **CGAL and Boost
are header-only** — compiled *into* the MEX by the mex compiler — so there is
no Boost build and no ABI concern for them.

## Per-architecture `mex()` compiler

| Arch | compiler | how |
|---|---|---|
| macos_arm64 | `clang++.xml` (Apple Clang, libc++) | `compile.m` selects clang via `setup_mex_compilers('macos_arm64','clang')` — native toolchain for CGAL/libigl/embree; overrides the channel-default gcc |
| linux_x86_64 | `gcc.xml` (gcc-toolset-10, GCC 10.3, libstdc++) | channel default |
| windows_x86_64 | **MSVC 2022** | `compile.m` re-selects MSVC, overriding the channel's MinGW default (gptoolbox has no Fortran; MinGW gcc 8.1 is too old for CGAL 6 / Boost 1.86 / embree 4) |

## Dependencies — per architecture

**Linkage** = how it ends up in the `.mex*`. Header-only deps are compiled
*into* the MEX, so they're neither static nor dynamic. **Source** = built from
source here vs. installed as a prebuilt binary/headers. **Build time** is a
rough estimate (the small from-source libs are measured locally; embree, El
Topo, and from-source gmp/mpfr are estimated) — it's the cost paid per CI run
until/unless we add deps caching. embree dominates. The dependency C++ libs are
built with the same compiler `mex()` uses (ABI rule above).

### macos_arm64 — `mex` compiler: `clang++` (Apple Clang, libc++)

| Library | Linkage | Source | Build time (est.) |
|---|---|---|---|
| libigl | header-only | from source (FetchContent) | — (fetch) |
| Eigen | header-only | from source (FetchContent, via libigl) | — (fetch) |
| cyCodeBase | header-only | from source (FetchContent, via libigl) | — (fetch) |
| CGAL | header-only | prebuilt (`brew install cgal`) | — (install) |
| Boost | header-only | prebuilt (`brew`, dep of cgal) | — (install) |
| GMP | **static** | prebuilt (`brew`, `libgmp.a`) | — (install) |
| MPFR | **static** | prebuilt (`brew`, `libmpfr.a`) | — (install) |
| predicates | **static** | from source | ~5 s |
| tetgen | **static** | from source | ~15 s |
| triangle | **static** | from source | ~5 s |
| libccd | **static** | from source | ~10 s |
| tinyxml2 | **static** | from source | ~5 s |
| embree | **static** (`INTERNAL` tasking → no TBB) | from source | **~5–8 min** |
| El Topo | **static** | from source | ~30 s |
| MATLAB libmx/libmex | dynamic (basename) | MATLAB-provided | — |

→ self-contained MEX; nothing bundled. Deps build dominated by embree (~5–8 min).

### linux_x86_64 — `mex` compiler: `gcc` (gcc-toolset-10 GCC 10.3, glibc 2.28)

| Library | Linkage | Source | Build time (est.) |
|---|---|---|---|
| libigl | header-only | from source (FetchContent) | — (fetch) |
| Eigen | header-only | from source (FetchContent, via libigl) | — (fetch) |
| cyCodeBase | header-only | from source (FetchContent, via libigl) | — (fetch) |
| CGAL | header-only | prebuilt (`dnf`/EPEL `CGAL-devel`, or CGAL header tarball) | — (install) |
| Boost | header-only | prebuilt (`dnf boost-devel`) | — (install) |
| GMP | **static** | **from source** (RHEL/EPEL ship no static `.a`) | ~1–2 min |
| MPFR | **static** | **from source** | ~45 s |
| predicates | **static** | from source | ~5 s |
| tetgen | **static** | from source | ~15 s |
| triangle | **static** | from source | ~5 s |
| libccd | **static** | from source | ~10 s |
| tinyxml2 | **static** | from source | ~5 s |
| embree | **static** (`INTERNAL` tasking → no TBB) | from source (gcc-toolset-10) | **~5–8 min** |
| El Topo | **static** | from source | ~30 s |
| libgomp | **dynamic, BUNDLED** (leaf `.so`) | *only if* libigl pulls OpenMP; MATLAB doesn't ship it (same as fmm2d) | — (install) |
| MATLAB libmx/libmex | dynamic (basename) | MATLAB-provided | — |

→ static everything ⇒ glibc-2.28 gate trivially passes (all built in ubi8); the
only possibly-bundled lib is the `libgomp` leaf. Deps build ≈ embree (~5–8 min)
+ gmp/mpfr (~2–3 min) + the small libs.

### windows_x86_64 — `mex` compiler: **MSVC 2022**

| Library | Linkage | Source | Build time (est.) |
|---|---|---|---|
| libigl | header-only | from source (FetchContent) | — (fetch) |
| Eigen | header-only | from source (FetchContent, via libigl) | — (fetch) |
| cyCodeBase | header-only | from source (FetchContent, via libigl) | — (fetch) |
| CGAL | header-only | prebuilt (`vcpkg`) | — (install, vcpkg first-build slow) |
| Boost | header-only | prebuilt (`vcpkg`) | — (install, vcpkg first-build slow) |
| GMP | **static** | prebuilt (`vcpkg` `x64-windows-static-md`, release-only) | — (install, cached) |
| MPFR | **static** | prebuilt (`vcpkg` `x64-windows-static-md`, release-only) | — (install, cached) |
| predicates | **static** | from source (MSVC) | ~10 s |
| tetgen | **static** | from source (MSVC) | ~20 s |
| triangle | **static** | from source (MSVC) | ~10 s |
| libccd | **static** | from source (MSVC) | ~15 s |
| tinyxml2 | **static** | from source (MSVC) | ~10 s |
| embree | **static** (`INTERNAL` tasking → no TBB) | from source (MSVC) | **~6–10 min** |
| El Topo | **static** | from source — our own `eltopo_msvc` CMake target | ~45 s |
| MATLAB libmx/libmex | dynamic (import lib) | MATLAB-provided | — |
| MSVC runtime (VCRUNTIME/MSVCP) | dynamic | system / MATLAB-provided (System32, survives strip) | — |

(`vcpkg` builds CGAL/Boost/gmp/mpfr from source on a cold cache — minutes to
tens of minutes the first time. We cut this two ways: a **release-only overlay
triplet** (channel-level `vcpkg-triplets/x64-windows-static-md.cmake`, shadowing
the builtin with `VCPKG_BUILD_TYPE release`) skips each port's unused debug
build — including gmp's `{gmp, host:true}` self-dependency, which also builds for
the host triplet `x64-windows` and is covered by a sibling `x64-windows.cmake`
overlay — and `build-package.yml` persists vcpkg's binary cache across runs via
`actions/cache` (saved right after setup, so a later Bundle failure can't drop
it). Warm runs restore gmp/mpfr in seconds.)

→ self-contained MEX; only the MATLAB libs and the System32 MSVC runtime are
dynamic, both present on any machine running MATLAB.

CGAL uses GMP/MPFR (linked static) rather than libigl's `CGAL_DISABLE_GMP`
Boost-backend path, because using system CGAL headers is what lets us skip
libigl's slow Boost-1.86 source build. gmp/mpfr are tiny, so static-linking
them (and the LGPL relink housekeeping) is cheap, and it avoids the
`mpfr → gmp` transitive bundling chain.

## Bundling & self-containment

Everything is static or header-only or MATLAB-provided, so the MEX are
**self-contained — nothing bundled**. The strip-and-test CI job confirms this on
every arch: it renames the toolchain away, then loads and runs the MEX. (On
macOS the only dynamic deps across all built MEX are `@rpath/libmx`,
`@rpath/libmex`, `/usr/lib/libSystem`.)

- **Linux:** static everything → the glibc-2.28 gate trivially passes (all
  built in the ubi8/glibc-2.28 container). **One possible exception:** if
  libigl's parallel code pulls `libgomp` (GNU OpenMP, which Linux MATLAB does
  *not* ship), we bundle that single **leaf `.so`** via
  `scripts/bundle_runtime_libs` — the same pattern `fmm2d`/`fmmlib2d` already
  use. It is a clean leaf (only system deps), so the existing non-recursive
  bundler suffices. We deliberately avoid shipping any **transitive** `.so`
  chain (e.g. `mpfr→gmp`, `embree→tbb`) — that is why gmp/mpfr are static and
  embree is built TBB-free.

## Why not the obvious shortcuts

- **Prebuilt embree (brew/RenderKit):** ships shared + drags in **TBB**, which
  collides with MATLAB's own bundled TBB at runtime. The from-source
  internal-tasking build has no TBB. (EPEL embree is v3 — incompatible with
  libigl's embree-4 API.)
- **dnf/brew embree-everywhere:** no version-consistent system embree across
  all three OSes; Windows has no system package manager at all.
- **`LIBIGL_USE_STATIC_LIBRARY` (precompiled libigl):** a compile-time
  optimization, but gptoolbox is built header-only upstream and is **not**
  validated against static libigl — it risks undefined-reference link errors
  for non-precompiled template instantiations, and it doesn't speed up the
  slowest (CGAL) files anyway. Header-only matches upstream; revisit only if
  per-build compile time becomes the bottleneck.

## Deferred optimizations

- **vcpkg binary cache — DONE (Windows).** Release-only overlay triplet +
  `actions/cache` over `VCPKG_DEFAULT_BINARY_CACHE` (see the Windows table note).
  The triplet is channel-level (`vcpkg-triplets/`) so a future Windows+vcpkg
  package shares the cache (identical ABI). Caveat: triplet-only edits don't
  auto-dispatch builds — `affected_builds.py` watches only `packages/`.
- **CMake deps cache (embree) — still deferred.** embree is the remaining slow
  build (~6–10 min, every arch). Caching the CMake deps dir would need a stable
  build path (`compile.m` uses a random `tempname` today) and a pin-hash key —
  and the key is the hard part: the libigl/embree pins live in gptoolbox's
  *fetched* source (`mex/cmake/libigl.cmake`), and `recipe.yaml` tracks branch
  `master`, not a commit, so a static `hashFiles` can't see upstream moves. A
  correct key needs the resolved gptoolbox commit (or pinning gptoolbox). Use
  **`actions/cache`**, **not** GitHub Releases (those are the `.mhl` channel).

## Windows / MSVC specifics (all confirmed on CI)

The Windows build is green and feature-complete: **58 MEX**, the full set bar the
macOS-only `impaste`. The non-obvious things MSVC needed, each found via the CI
loop:

- **Manifest per config.** The deps `CMakeLists.txt` emits `manifest-$<CONFIG>.txt`
  (not a fixed name): the multi-config VS generator evaluates `file(GENERATE)`
  for every config, so a fixed path carrying per-config `$<TARGET_FILE>` errors.
  `compile.m` reads `manifest-Release.txt`.
- **Static-lib consume defines.** libccd and embree decorate their API with
  `__declspec(dllimport)` by default; linked static, the MEX (built by `mex()`,
  not CMake, so they don't inherit the targets' compile defs) hit unresolved
  `__imp_*`. Fix: `-DCCD_STATIC_DEFINE` (the libccd build **and** the MEX) and
  `-DEMBREE_STATIC_LIB` (the MEX).
- **`-DWIN32`.** MSVC defines `_WIN32` but not bare `WIN32`; libigl's `Timer.h`
  guards `<windows.h>` on `WIN32` and otherwise pulls POSIX `<sys/time.h>`.
- **El Topo.** Built from our own `eltopo_msvc` target (eltopo3d's CMake is
  gcc/clang-only — hardcoded flags + `find_package(BLAS REQUIRED)`). Two source
  fixups: `util.h`'s `lround`/`remainder` polyfills (`#ifdef _MSC_VER`) collide
  with the modern CRT (renamed away); and its hand-rolled Fortran BLAS prototypes
  (`daxpy_`) don't match Win64 MATLAB's **bare** exports (`daxpy`), so the 28
  BLAS/LAPACK symbols are preprocessor-renamed `name_`→`name` on `eltopo_msvc`.
  (Unix MATLAB exports the underscore form, so Linux/macOS link unchanged.)

Previously-open risks, now resolved: embree builds under Linux gcc-toolset-10
(GCC 10.3); `libgomp` on Linux is bundled as a leaf `.so` only if it appears
(`scripts/bundle_runtime_libs`).

## Build sequence

All three architectures are landed and published (macOS, Linux, Windows). The
bring-up order was macOS → Linux → Windows; each `(package, arch)` builds
independently via `build-package.yml`.
