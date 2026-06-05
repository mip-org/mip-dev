# MEX runtime-library bundling and why it is non-recursive

A companion to `MATLAB-GCC.md` and `MATLAB-GLIBC.md`. Those notes explain which
symbol versions (`libstdc++`/`libgfortran` ABI, `glibc` floor) a Linux MEX may
require. This note covers the next question: of the shared libraries a MEX
actually pulls in, which ones we **ship** next to it and which we leave to be
resolved at runtime — and the one design decision in
`scripts/bundle_runtime_libs.m` that most often looks like a bug but is not:
**bundling is deliberately non-recursive.**

## TL;DR

- `bundle_runtime_libs.m` scans only the **MEX's own** `NEEDED` entries, copies
  the non-system, non-MATLAB ones next to the MEX, and sets an `$ORIGIN` RPATH.
  It does **not** recurse into the `NEEDED` entries of the libs it copies.
- A bundled lib's own transitive dependencies are expected to be satisfied at
  runtime by the **OS** or by **MATLAB**, because the package only ever loads
  inside MATLAB, which puts its `sys/os/glnxa64` runtime libs on
  `LD_LIBRARY_PATH`.
- So we never ship `libquadmath`, `libz`, etc., even though `libgfortran.so.5`
  hard-`NEEDED`s them. Adding recursion would start bundling those — redundant
  copies of libs MATLAB already provides, the exact ABI hazard the skip-set
  guards against for `libstdc++`/`libgcc_s`.

## Three tiers of runtime library

A MEX's `NEEDED` list (and the `NEEDED` lists of its dependencies) falls into
three tiers:

| Tier | Examples | Who provides it at runtime | Do we bundle it? |
|---|---|---|---|
| **OS-guaranteed** | `libc.so.6`, `libm.so.6`, `libpthread.so.0`, `libdl.so.2`, `ld-linux-x86-64.so.2` | the end-user's OS | No — in `linux_skip_set` |
| **MATLAB-provided** | `libgfortran.so.5`, `libquadmath.so.0`, `libgomp.so.1`, `libstdc++.so.6`, `libgcc_s.so.1`, `libz.so.1` | MATLAB's `sys/os/glnxa64` (on `LD_LIBRARY_PATH`) | No — MATLAB resolves it |
| **Third-party** | anything else a package genuinely depends on | nothing, unless we ship it | **Yes** — this is what bundling is for |

The skip-set encodes the OS-guaranteed tier explicitly. The MATLAB-provided
tier is handled implicitly: those libs are `NEEDED` by the libs we copy
(`libgfortran` → `libquadmath`/`libz`), not by the MEX directly, so the
non-recursive scan never reaches them.

## Why we can lean on MATLAB for the transitive deps

The package only ever runs inside MATLAB, and MATLAB ships its own
`libgfortran`, `libquadmath`, `libgomp`, `libstdc++`, `libgcc_s`, `libz`, … in
`$MATLABROOT/sys/os/glnxa64/`, which it places on `LD_LIBRARY_PATH`. The build
toolchain is pinned (`ubi8` GCC 8.5 / R2022a) precisely so the compiled code's
`libgfortran`/`libstdc++` symbol-version requirements stay **within** what those
MATLAB copies provide — see `MATLAB-GCC.md` and the "pins the … ABI axis"
comment in `build-package.yml`.

A subtlety worth knowing: the dynamic loader searches `LD_LIBRARY_PATH`
**before** a binary's own `$ORIGIN` RPATH (RUNPATH). Since MATLAB's library
directory is on `LD_LIBRARY_PATH`, **MATLAB's `libgfortran` is in fact the
likely runtime provider**, and the copy we bundle alongside the MEX is a
fallback for load contexts that do not inherit MATLAB's library path. Either
way, `libgfortran`'s own transitive deps (`libquadmath`, `libz`) resolve against
MATLAB, not against our bundle — which is why not shipping them is correct.

## The strip-then-test gate is the proof (and its scope)

`build-package.yml` deletes the entire compiler/runtime toolchain
(`libgfortran`/`libgomp`/`libquadmath` are purged and `ldconfig` is refreshed;
"Verify strip" fails the build if any remain on the linker path) and then reruns
the package's test against the bundled `.mhl`. A MEX that needs an unbundled,
non-MATLAB library fails to load → the build goes red → nothing ships.

Note the scope: the test runs **inside MATLAB**, so the gate proves
self-containment relative to *a machine that has MATLAB* — which is exactly the
deployment target. It does **not** prove independence from MATLAB's own runtime
libs, and it is not meant to.

## Worked example: fmmlib2d 1.2.4

`objdump -p` on the shipped binaries (`linux_x86_64`):

```
fmm2d.mexa64       RUNPATH $ORIGIN   NEEDED libgfortran.so.5, libgomp.so.1, libmx.so, libmex.so, libm, libpthread, libc, ld-linux
libgfortran.so.5   RUNPATH $ORIGIN   NEEDED libquadmath.so.0, libz.so.1, libm, libgcc_s, libc
libgomp.so.1       RUNPATH $ORIGIN   NEEDED libdl, libpthread, libc
```

Bundling copied only `libgfortran.so.5` and `libgomp.so.1` (the MEX's two
non-system/non-MATLAB direct `NEEDED`s). `libquadmath.so.0` and `libz.so.1` —
transitive `NEEDED`s of `libgfortran` — were **not** bundled. The post-strip
test (`libquadmath0` purged from the host) still passed at ~1e-16 relative
error, because it ran inside MATLAB, which supplied them. This is the
non-recursive design working exactly as intended.

## When recursion *would* be needed, and how to add it safely

Recursion is only correct for a transitive dependency that is **neither
OS-guaranteed nor MATLAB-provided** — a genuinely third-party `.so` pulled in by
something we bundle. If such a package appears:

1. First extend `linux_skip_set` / `macos_skip_patterns` to exclude the
   MATLAB/OS libs that would otherwise be swept in (`libquadmath.so.0`,
   `libz.so.1`, …). Otherwise recursion will start shipping redundant copies of
   libs MATLAB already provides and risk ABI clashes with MATLAB's own.
2. Then make `bundle_linux` walk each copied lib's `NEEDED` entries to a
   fixpoint. The per-lib `$ORIGIN` RPATH stamping is already handled by
   `copy_and_sanitize_lib`, so the libs would find their siblings in the bundle
   directory — recursion is the only missing piece.

Until then, the non-recursive scan is the correct behavior; do not "fix" it.
