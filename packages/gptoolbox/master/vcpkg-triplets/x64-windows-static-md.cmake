# Overlay triplet that shadows vcpkg's builtin x64-windows-static-md. Same NAME
# (so compile.m's VCPKG_TARGET_TRIPLET is unchanged), but adds
# VCPKG_BUILD_TYPE=release. By default vcpkg builds BOTH debug and release of
# every port; we only ever link the release libs (the MEX build is
# -DCMAKE_BUILD_TYPE=Release / --config Release), so the debug half roughly
# doubles a cold gmp/mpfr build for nothing. This only affects `vcpkg install`;
# at consume time CMake's vcpkg toolchain just reads installed/<triplet>/lib.
# Selected via --overlay-triplets in mip.yaml's windows setup.
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_BUILD_TYPE release)
