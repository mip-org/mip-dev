# Build ONLY the C/C++ dependency libraries the gptoolbox MEX files link
# against, as static libs. CMake never touches MATLAB: the .mex* files are
# compiled and linked by mex() in compile.m (so there's no find_package(Matlab)
# and no dependence on gptoolbox's stale bundled FindMatlab version mapping).
#
# This is a channel-provided file overlaid at the gptoolbox source root (the
# upstream repo has no root CMakeLists.txt). compile.m configures it into a temp
# build dir and reads the manifest.txt emitted below — include dirs ("I <dir>")
# and categorized static libs ("L <category> <path>") — to assemble the mex()
# command lines. See BUILD_NOTES.md for the full rationale.
cmake_minimum_required(VERSION 3.16)

# libccd v2.1 / tetgen / triangle / predicates declare ancient
# cmake_minimum_required; allow them to configure under CMake 4.
set(CMAKE_POLICY_VERSION_MINIMUM 3.5 CACHE STRING "" FORCE)

# Build every dependency statically so the linked MEX ships nothing extra.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

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

# --- El Topo (eltopo MEX) -------------------------------------------------
# Pin mirrors gptoolbox/mex/CMakeLists.txt. eltopo3d adds -march=native via
# check_cxx_compiler_flag(COMPILER_SUPPORTS_MARCH_NATIVE) -- which would bake
# the build host's CPU ISA into the binary and crash on older end-user CPUs.
# Pre-seed that cache var OFF so the check is skipped and the flag never added.
# eltopo links BLAS/LAPACK; compile.m satisfies them with MATLAB's
# -lmwlapack/-lmwblas at the mex link (no external/bundled BLAS).
set(COMPILER_SUPPORTS_MARCH_NATIVE OFF CACHE BOOL "" FORCE)
FetchContent_Declare(eltopo
  GIT_REPOSITORY https://github.com/alecjacobson/eltopo.git
  GIT_TAG 3cf988aae467392d1066bdde0be3f54487a0ba2c)
FetchContent_GetProperties(eltopo)
if(NOT eltopo_POPULATED)
  FetchContent_Populate(eltopo)
  add_subdirectory(${eltopo_SOURCE_DIR}/eltopo3d ${eltopo_BINARY_DIR})
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
# CGAL is header-only; its link deps are static gmp + mpfr.
string(APPEND _m "L cgal ${GMP_STATIC}\n")
string(APPEND _m "L cgal ${MPFR_STATIC}\n")
# El Topo static lib (eltopo3d's target is aliased to libeltopo).
string(APPEND _m "L eltopo $<TARGET_FILE:libeltopo>\n")

file(GENERATE OUTPUT "${CMAKE_BINARY_DIR}/manifest.txt" CONTENT "${_m}")
