# Build ONLY the C/C++ dependency libraries the gptoolbox MEX files link
# against, as static libs. CMake never touches MATLAB: the .mex* files are
# compiled and linked by mex() in compile.m (so there's no find_package(Matlab)
# and no dependence on gptoolbox's stale bundled FindMatlab version mapping).
#
# This is a channel-provided file overlaid at the gptoolbox source root (the
# upstream repo has no root CMakeLists.txt). compile.m configures it into a temp
# build dir and reads the manifest-<CONFIG>.txt emitted below — include dirs ("I <dir>")
# and categorized static libs ("L <category> <path>") — to assemble the mex()
# command lines. See BUILD_NOTES.md for the full rationale.
cmake_minimum_required(VERSION 3.16)

# libccd v2.1 / tetgen / triangle / predicates declare ancient
# cmake_minimum_required; allow them to configure under CMake 4.
set(CMAKE_POLICY_VERSION_MINIMUM 3.5 CACHE STRING "" FORCE)

# Build every dependency statically so the linked MEX ships nothing extra.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

# These static libs get linked into the shared MEX, so every object must be
# position-independent. On Linux, gcc builds non-PIC by default and ld rejects a
# non-PIC .a in a shared object ("relocation R_X86_64_32 ... recompile with
# -fPIC"); macOS/arm64 is always PIC so this only matters here. Force PIC as the
# default target property for all deps (libccd, tetgen, triangle, tinyxml2,
# embree, eltopo, predicates) built below.
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

project(gptoolbox_mex_deps CXX C)

# --- System CGAL (headers) -------------------------------------------------
# Providing CGAL::CGAL before include(libigl) makes libigl's cgal.cmake return
# early, so it neither re-downloads CGAL nor builds Boost 1.86 from source. CGAL
# and Boost are header-only here; the only compiled CGAL deps are gmp/mpfr,
# which we link statically (found below). Installed per-arch: brew (macOS),
# dnf/EPEL (Linux), vcpkg (Windows).
find_package(CGAL REQUIRED)

# --- libigl modules --------------------------------------------------------
# Keep all the modules the full MEX set needs. embree is NOT given a system
# target, so libigl builds it from source (EMBREE_STATIC_LIB ON,
# EMBREE_TASKING_SYSTEM INTERNAL → static, no TBB — see BUILD_NOTES.md).
set(LIBIGL_COPYLEFT_CGAL       ON  CACHE BOOL "")
set(LIBIGL_EMBREE              ON  CACHE BOOL "")
set(LIBIGL_XML                 ON  CACHE BOOL "")
set(LIBIGL_PREDICATES          ON  CACHE BOOL "")
set(LIBIGL_COPYLEFT_TETGEN     ON  CACHE BOOL "")
set(LIBIGL_RESTRICTED_TRIANGLE ON  CACHE BOOL "")
set(LIBIGL_CYCODEBASE          ON  CACHE BOOL "")
# RESTRICTED_MATLAB OFF: its headers ship with libigl regardless, and enabling
# the module would pull MATLAB back into the CMake configure.
set(LIBIGL_RESTRICTED_MATLAB   OFF CACHE BOOL "")

# Reuse gptoolbox's own mex/cmake/libigl.cmake so the pinned libigl commit
# tracks upstream. It FetchContent's libigl, which fetches Eigen / predicates /
# triangle / tetgen / cyCodeBase / embree per the options above.
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/mex/cmake")
include(libigl)

# --- libccd (gjk_*/mpr_* MEX) ---------------------------------------------
# Pin mirrors gptoolbox/mex/CMakeLists.txt.
set(ENABLE_DOUBLE_PRECISION ON CACHE BOOL "" FORCE)
include(FetchContent)
FetchContent_Declare(libccd
  GIT_REPOSITORY https://github.com/danfis/libccd.git
  GIT_TAG v2.1)
FetchContent_MakeAvailable(libccd)

# libccd's ccd_export.h defaults CCD_EXPORT to __declspec(dllimport) unless
# CCD_STATIC_DEFINE is defined, and libccd's CMake never sets it for a static
# build. On MSVC that makes even ccd.lib's OWN objects reference their cross-TU
# API via __imp_* (e.g. ccd.obj -> __imp_ccdVec3PointSegmentDist2), so the static
# lib has unresolved imports (LNK2019). Define it on the static target. Windows
# only (GCC/Clang have no import stubs, so macOS/Linux link fine without it).
# compile.m passes the same define to the consuming MEX, which link via mex()
# (not CMake) and so don't inherit this PUBLIC interface define.
if(WIN32 AND TARGET ccd)
  target_compile_definitions(ccd PUBLIC CCD_STATIC_DEFINE)
endif()

# --- El Topo (eltopo MEX) -------------------------------------------------
# Pin mirrors gptoolbox/mex/CMakeLists.txt. eltopo links BLAS/LAPACK; compile.m
# satisfies them with MATLAB's -lmwlapack/-lmwblas at the mex link (no
# external/bundled BLAS).
#
# eltopo3d's own CMakeLists adds -march=native via
# check_cxx_compiler_flag(COMPILER_SUPPORTS_MARCH_NATIVE) -- which would bake the
# build host's CPU ISA into the binary and crash on older end-user CPUs. Pre-seed
# that cache var OFF so the check is skipped and the flag never added.
set(COMPILER_SUPPORTS_MARCH_NATIVE OFF CACHE BOOL "" FORCE)
FetchContent_Declare(eltopo
  GIT_REPOSITORY https://github.com/alecjacobson/eltopo.git
  GIT_TAG 3cf988aae467392d1066bdde0be3f54487a0ba2c)
FetchContent_GetProperties(eltopo)
if(NOT eltopo_POPULATED)
  FetchContent_Populate(eltopo)
  if(NOT WIN32)
    # gcc/clang: eltopo3d's CMakeLists builds cleanly (produces target
    # eltopo_release, aliased to libeltopo).
    add_subdirectory(${eltopo_SOURCE_DIR}/eltopo3d ${eltopo_BINARY_DIR})
  else()
    # Windows/MSVC: eltopo3d's CMakeLists is gcc/clang-only -- it hardcodes
    # -std=c++11/-Wall/-fPIC into CMAKE_CXX_FLAGS and does find_package(BLAS
    # REQUIRED), which fails with no system BLAS. So build libeltopo ourselves
    # from the same source globs with MSVC-friendly settings. El Topo historically
    # shipped VS projects (vs_files/ in the repo), so the source is MSVC-buildable.
    # No BLAS is linked here -- the eltopo MEX links MATLAB's -lmwlapack/-lmwblas
    # in compile.m. NO_GUI drops the GLUT/OpenGL viewer; USE_FORTRAN_BLAS selects
    # the daxpy_-style interface matching MATLAB's Fortran BLAS (as on Linux).
    set(_eltopo3d "${eltopo_SOURCE_DIR}/eltopo3d")
    file(GLOB ELTOPO_SRC
      "${_eltopo3d}/*.cpp"
      "${_eltopo3d}/../common/*.cpp"
      "${_eltopo3d}/../common/tunicate/*.cpp"
      "${_eltopo3d}/../common/newsparse/*.cpp")
    # common/util.h polyfills lround/remainder under a bare `#ifdef _MSC_VER` for
    # old MSVC, but modern MSVC's CRT already declares them (as dllimport), so the
    # definitions collide (C2556/C2371/C2491). Rename the polyfills out of the way
    # in our private FetchContent copy so El Topo's lround()/remainder() calls
    # bind to the CRT versions. gcc/clang never compile this block, so it's an
    # MSVC-only fixup; idempotent (the renamed source no longer matches).
    set(_util_h "${_eltopo3d}/../common/util.h")
    file(READ "${_util_h}" _util_contents)
    string(REPLACE "inline int lround(double x)"
                   "inline int eltopo_unused_lround(double x)"
                   _util_contents "${_util_contents}")
    string(REPLACE "inline double remainder(double x, double y)"
                   "inline double eltopo_unused_remainder(double x, double y)"
                   _util_contents "${_util_contents}")
    file(WRITE "${_util_h}" "${_util_contents}")
    # Real target eltopo_msvc (parity with eltopo3d's eltopo_release), aliased to
    # libeltopo so the manifest's $<TARGET_FILE:libeltopo> resolves on every arch.
    add_library(eltopo_msvc STATIC ${ELTOPO_SRC})
    add_library(libeltopo ALIAS eltopo_msvc)
    set_property(TARGET eltopo_msvc PROPERTY CXX_STANDARD 17)
    target_include_directories(eltopo_msvc PUBLIC
      "${_eltopo3d}"
      "${_eltopo3d}/../common"
      "${_eltopo3d}/../common/tunicate"
      "${_eltopo3d}/../common/newsparse"
      "${_eltopo3d}/../common/meshes")
    target_compile_definitions(eltopo_msvc PRIVATE
      NO_GUI USE_FORTRAN_BLAS __LITTLE_ENDIAN__ NOMINMAX _USE_MATH_DEFINES)
    # USE_FORTRAN_BLAS makes El Topo call the trailing-underscore Fortran names
    # (daxpy_), but Win64 MATLAB's libmwblas/libmwlapack export the BARE names
    # (daxpy) -- the opposite of Linux/macOS MATLAB. Preprocessor-rename every
    # BLAS/LAPACK symbol the wrappers declare (name_ -> name) so the lib's
    # references bind to MATLAB's Windows BLAS at the eltopo MEX link.
    target_compile_definitions(eltopo_msvc PRIVATE
      dasum_=dasum daxpy_=daxpy dcopy_=dcopy ddot_=ddot dgemm_=dgemm
      dgemv_=dgemv dnrm2_=dnrm2 dscal_=dscal dsdot_=dsdot dswap_=dswap
      idamax_=idamax isamax_=isamax sasum_=sasum saxpy_=saxpy scopy_=scopy
      sdot_=sdot sgemm_=sgemm sgemv_=sgemv snrm2_=snrm2 sscal_=sscal sswap_=sswap
      dgelsd_=dgelsd dgesdd_=dgesdd dgesv_=dgesv dgetrf_=dgetrf dgetri_=dgetri
      dsyev_=dsyev sgesv_=sgesv)
    target_compile_options(eltopo_msvc PRIVATE /bigobj)
  endif()
endif()

# --- Static gmp / mpfr (CGAL's number types) ------------------------------
# Force discovery of the static archives (CGAL itself is header-only). On macOS
# these are brew's libgmp.a/libmpfr.a; on Windows vcpkg's static triplet; on
# Linux they're built from source and their location passed via
# -DGMP_STATIC=/-DMPFR_STATIC= by compile.m. CMAKE_PREFIX_PATH (set by
# compile.m) points find_library at the right prefix.
if(NOT GMP_STATIC OR NOT MPFR_STATIC)
  set(_save_suffixes "${CMAKE_FIND_LIBRARY_SUFFIXES}")
  if(WIN32)
    set(CMAKE_FIND_LIBRARY_SUFFIXES .lib)
  else()
    set(CMAKE_FIND_LIBRARY_SUFFIXES .a)
  endif()
  if(NOT GMP_STATIC)
    find_library(GMP_STATIC NAMES gmp libgmp REQUIRED)
  endif()
  if(NOT MPFR_STATIC)
    find_library(MPFR_STATIC NAMES mpfr libmpfr REQUIRED)
  endif()
  set(CMAKE_FIND_LIBRARY_SUFFIXES "${_save_suffixes}")
endif()

# --- Manifest --------------------------------------------------------------
# "I <include dir>" per include directory (compile.m dedupes), and
# "L <category> <path>" per static lib. Categories map to compile.m's groups.
# Generator expressions resolve at configure time.
set(_inc_targets
  igl::core igl::predicates igl::cycodebase
  igl_copyleft::tetgen igl_restricted::triangle
  igl_copyleft::cgal igl::embree igl::xml
  Eigen3::Eigen CGAL::CGAL
  predicates tetgen triangle ccd tinyxml2 embree libeltopo)
set(_m "")
foreach(t ${_inc_targets})
  if(TARGET ${t})
    string(APPEND _m "I $<JOIN:$<TARGET_PROPERTY:${t},INTERFACE_INCLUDE_DIRECTORIES>,\nI >\n")
  endif()
endforeach()

# Single-archive categories.
string(APPEND _m "L predicates $<TARGET_FILE:predicates>\n")
string(APPEND _m "L tetgen $<TARGET_FILE:tetgen>\n")
string(APPEND _m "L triangle $<TARGET_FILE:triangle>\n")
string(APPEND _m "L ccd $<TARGET_FILE:ccd>\n")
string(APPEND _m "L xml $<TARGET_FILE:tinyxml2>\n")
# embree is several internal static archives; emit each (link order: embree4
# first, then its deps).
foreach(t embree sys math simd tasking lexers)
  if(TARGET ${t})
    string(APPEND _m "L embree $<TARGET_FILE:${t}>\n")
  endif()
endforeach()
# CGAL is header-only; its link deps are static mpfr + gmp. Order matters:
# mpfr depends on gmp, and GNU ld is single-pass over archives, so mpfr must
# precede gmp (gmp last) or mpfr's gmp references go unresolved ("undefined
# reference to __gmp*"). macOS's linker is multi-pass and tolerates either order.
string(APPEND _m "L cgal ${MPFR_STATIC}\n")
string(APPEND _m "L cgal ${GMP_STATIC}\n")
# El Topo static lib (eltopo3d's target is aliased to libeltopo). Skipped on
# Windows (the eltopo FetchContent is gated under NOT WIN32 above), so guard on
# the target's existence — otherwise $<TARGET_FILE:libeltopo> errors in
# file(GENERATE) ("No target libeltopo"). compile.m only reads the eltopo
# category off-Windows, matching this.
if(TARGET libeltopo)
  string(APPEND _m "L eltopo $<TARGET_FILE:libeltopo>\n")
endif()

# Per-config output: on the multi-config VS generator, $<CONFIG> makes
# file(GENERATE) emit one manifest per config, each with $<TARGET_FILE> resolved
# for that config (a fixed path errors — "written multiple times with different
# content"). On single-config Makefiles/Ninja, $<CONFIG> is CMAKE_BUILD_TYPE
# (Release here). compile.m reads manifest-Release.txt.
file(GENERATE OUTPUT "${CMAKE_BINARY_DIR}/manifest-$<CONFIG>.txt" CONTENT "${_m}")
