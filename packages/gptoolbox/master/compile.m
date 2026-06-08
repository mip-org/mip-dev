% Compile gptoolbox MEX files (linux_x86_64, macos_arm64, windows_x86_64).
% compile.m runs with cwd set to the package source root.
%
% Approach (see BUILD_NOTES.md): CMake builds ONLY the C/C++ dependency
% libraries as static libs (predicates, tetgen, triangle, libccd, tinyxml2,
% embree) and discovers the header-only deps (libigl, Eigen, cyCodeBase, CGAL,
% Boost) + static gmp/mpfr, emitting a manifest. CMake never touches MATLAB, so
% there is no find_package(Matlab). Each MEX is then compiled and linked with
% mex(), driven by the `groups` table below (mirrors upstream's compile_each),
% so it uses the channel's mexopts (static libstdc++/libgcc, MATLAB libs by
% basename — no patchelf). The full feature set is built (CGAL, Embree, XML;
% El Topo and the macOS-only impaste are handled separately / TODO).

fprintf('=== Compiling gptoolbox MEX files ===\n');

% MATLAB injects its own libcurl/libstdc++ onto LD_LIBRARY_PATH, which breaks
% the system git/curl that CMake FetchContent shells out to. Clear it for the
% duration of this script; onCleanup restores it.
if isunix && ~ismac
    origLdPath = getenv('LD_LIBRARY_PATH');
    setenv('LD_LIBRARY_PATH', '');
    restoreLdPath = onCleanup(@() setenv('LD_LIBRARY_PATH', origLdPath)); %#ok<NASGU>
end

srcRoot = pwd;
mexDir = fullfile(srcRoot, 'mex');
if ~exist(mexDir, 'dir')
    error('mex/ directory not found at %s', mexDir);
end
if ~exist(fullfile(srcRoot, 'CMakeLists.txt'), 'file')
    error('CMakeLists.txt (dependency builder) not found at %s', srcRoot);
end

% ---- 1. Build the dependency static libraries with CMake ----------------
depsBuild = tempname;
mkdir(depsBuild);
cleanupDeps = onCleanup(@() rmdir_silent(depsBuild)); %#ok<NASGU>

% Per-arch dependency discovery. macOS: Homebrew prefix for CGAL + static
% gmp/mpfr. Linux: CGAL/Boost from dnf (/usr), static gmp/mpfr built from
% source here and passed explicitly. (Windows will pass a vcpkg toolchain —
% handled when that arch is wired up.)
prefixArg = '';
extraInc = {};   % extra -I flags prepended to the MEX include path (Linux gmp/mpfr)
if ismac
    % Use Apple Clang on macOS (the native toolchain for CGAL/libigl/embree,
    % uniform libc++, and it can compile the Objective-C++ impaste). This
    % overrides the channel-default gcc selected by bundle_one and exports
    % CC/CXX so the CMake deps build uses the same clang.
    setup_mex_compilers('macos_arm64', 'clang');

    [s, brewPrefix] = system('brew --prefix');
    if s == 0
        brewPrefix = strtrim(brewPrefix);
    else
        brewPrefix = '/opt/homebrew';
    end
    % Build the static deps for macOS 11.0 (oldest Apple-Silicon macOS) so they
    % don't out-version the MEX. The MEX's own minimum-load version is set by
    % the selected mexopts (-mmacosx-version-min=11.0 in clang.xml/clang++.xml);
    % this just keeps the CMake-built .a's consistent (no "built for newer
    % macOS" link warnings).
    prefixArg = sprintf(' -DCMAKE_PREFIX_PATH="%s" -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0', brewPrefix);
elseif isunix
    % Linux: CGAL/Boost headers come from dnf (mip.yaml setup), but RHEL/EPEL
    % ship no static gmp/mpfr (.a). Build them from source into an isolated,
    % ephemeral prefix this script owns (no /usr/local pollution, auto-cleaned)
    % and pass the .a paths so CMakeLists skips its find_library. CGAL links
    % these. Built with the same gcc as mex (CC exported by setup_mex_compilers
    % in bundle_one). LD_LIBRARY_PATH was cleared above so system curl works.
    gmpmpfr = tempname;
    mkdir(gmpmpfr);
    cleanupGmpMpfr = onCleanup(@() rmdir_silent(gmpmpfr)); %#ok<NASGU>
    % --enable-fat: gmp otherwise bakes the build runner's CPU assembly into the
    % .a (an -march=native-style hazard → SIGILL on older end-user CPUs). Fat
    % builds all x86 variants and dispatches at runtime.
    build_autotools_static('https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz', ...
        'gmp-6.3.0', {'--enable-static', '--disable-shared', '--with-pic', ...
        '--enable-fat'}, gmpmpfr);
    build_autotools_static('https://ftp.gnu.org/gnu/mpfr/mpfr-4.2.1.tar.xz', ...
        'mpfr-4.2.1', {'--enable-static', '--disable-shared', '--with-pic', ...
        sprintf('--with-gmp=%s', gmpmpfr)}, gmpmpfr);
    prefixArg = sprintf(' -DGMP_STATIC="%s/lib/libgmp.a" -DMPFR_STATIC="%s/lib/libmpfr.a"', ...
        gmpmpfr, gmpmpfr);
    % Put our gmp.h/mpfr.h first: they must match the .a we just built (CGAL's
    % dnf deps may also drop older headers in /usr/include).
    extraInc = {['-I' fullfile(gmpmpfr, 'include')]};
end

genArg = '';
if ispc
    genArg = ' -G "MinGW Makefiles"';   % placeholder; Windows uses MSVC (TODO)
end

% feature('numcores'), not maxNumCompThreads: the latter is MATLAB's
% computational-thread cap, which the matlab-actions CI session pins to 1, so
% the cmake build ran -j1. feature('numcores') re-probes the hardware.
nproc = feature('numcores');
cfgCmd = sprintf('cmake -S "%s" -B "%s"%s%s -DCMAKE_BUILD_TYPE=Release', ...
    srcRoot, depsBuild, genArg, prefixArg);
fprintf('Configuring dependency libraries:\n  %s\n', cfgCmd);
[status, out] = system(cfgCmd);
fprintf('%s', out);
if status ~= 0
    error('CMake configuration of dependency libraries failed (exit %d)', status);
end

% embree's internal archives (sys/math/...) build as deps of the `embree`
% target; predicates/tetgen/triangle/ccd/tinyxml2 are explicit.
buildCmd = sprintf(['cmake --build "%s" --config Release --target ' ...
    'embree predicates tetgen triangle ccd tinyxml2 eltopo_release -j%d'], ...
    depsBuild, nproc);
fprintf('Building dependency libraries:\n  %s\n', buildCmd);
[status, out] = system(buildCmd);
fprintf('%s', out);
if status ~= 0
    error('CMake build of dependency libraries failed (exit %d)', status);
end

% ---- 2. Parse the manifest: include dirs + categorized lib paths --------
manifest = fileread(fullfile(depsBuild, 'manifest.txt'));
incFlags = {};
libsByCat = containers.Map();
for ln = splitlines(string(manifest))'
    s = strtrim(char(ln));
    if startsWith(s, 'I ')
        d = strtrim(s(3:end));
        if ~isempty(d) && isfolder(d) && ~any(strcmp(incFlags, ['-I' d]))
            incFlags{end+1} = ['-I' d]; %#ok<SAGROW>
        end
    elseif startsWith(s, 'L ')
        rest = strtrim(s(3:end));
        sp = find(rest == ' ', 1);
        cat = rest(1:sp-1);
        p = strtrim(rest(sp+1:end));
        if ~isKey(libsByCat, cat); libsByCat(cat) = {}; end
        v = libsByCat(cat); v{end+1} = p; libsByCat(cat) = v;
    end
end
incFlags{end+1} = ['-I' mexDir];   % gptoolbox's own mex/ headers
incFlags = [extraInc, incFlags];   % Linux gmp/mpfr headers first (no-op elsewhere)

% ---- 3. Compile each MEX with mex() -------------------------------------
% -largeArrayDims (classic API), -std=c++17 (libigl/CGAL), -DMEX (upstream's
% global define), -DCY_NO_INTRIN_H (no x86 <immintrin.h> in cyCodeBase / no AVX
% baking). Per-group -DWITH_CGAL/-DWITH_EMBREE/-DWITH_PREDICATES go with the
% matching library link.
common = [{'-largeArrayDims', 'CXXFLAGS=$CXXFLAGS -std=c++17', ...
           '-DMEX', '-DCY_NO_INTRIN_H'}, incFlags, {'-outdir', mexDir}];

% Groups mirror upstream mex/CMakeLists.txt compile_each() with all features
% on. Each row: { extra-defines, {lib categories}, {source basenames} }.
groups = {
    {}, {}, { ...
        'aabb','angle_derivatives','bone_visible','blue_noise', ...
        'collapse_small_triangles','decimate_libigl','dual_laplacian', ...
        'exact_geodesic','fast_sparse','fit_rotations_mex','fit_cubic_bezier', ...
        'icp','isolines','in_element_aabb','psd_project_rows', ...
        'principal_curvature','readMSH','read_triangle_mesh','segment_graph', ...
        'signed_distance','simplify_polyhedron','slim','split_nonmanifold', ...
        'solid_angle'};
    {},                        {'ccd'},        {'gjk_intersect','gjk_penetration','mpr_intersect','mpr_penetration'};
    {},                        {},             {'fast_roots','point_spline_squared_distance','point_cubic_squared_distance'};
    {},                        {'tetgen'},     {'tetrahedralize'};
    {},                        {'triangle'},   {'refine_triangulation'};
    {'-DWITH_CGAL'},           {'triangle','cgal'}, {'triangulate'};
    {'-DWITH_PREDICATES'},     {'predicates'}, {'orient2d','orient3d','point_spline_signed_distance','spline_winding_number'};
    {'-DWITH_EMBREE'},         {'embree'},     {'ambient_occlusion','bone_visible_embree','ray_mesh_intersect','ray_mesh_intersect_all','reorient_facets'};
    {'-DWITH_EMBREE','-DWITH_CGAL'}, {'embree','cgal'}, {'winding_number'};
    {'-DWITH_CGAL'},           {'cgal'},       { ...
        'box_intersect','form_factor','intersect_other','mesh_boolean', ...
        'outer_hull','point_mesh_squared_distance','selfintersect', ...
        'signed_distance_isosurface','snap_rounding','trim_with_solid', ...
        'upper_envelope','wire_mesh'};
    {'-DWITH_CGAL'},           {'cgal','xml'}, {'read_mesh_from_xml'};
    };

nBuilt = 0;
for g = 1:size(groups, 1)
    extra = groups{g, 1};
    cats  = groups{g, 2};
    names = groups{g, 3};
    libs = {};
    for c = 1:numel(cats)
        if ~isKey(libsByCat, cats{c})
            error('Manifest is missing lib category "%s".', cats{c});
        end
        libs = [libs, libsByCat(cats{c})]; %#ok<AGROW>
    end
    for k = 1:numel(names)
        name = names{k};
        src = fullfile(mexDir, [name '.cpp']);
        if ~exist(src, 'file')
            error('Expected MEX source missing: %s', src);
        end
        fprintf('  mex %s\n', name);
        mex(common{:}, extra{:}, '-output', name, src, libs{:});
        nBuilt = nBuilt + 1;
    end
end
% El Topo is handled on its own: it needs BLAS/LAPACK, which don't fit the
% category->lib model. Its BLAS interface is platform-gated in eltopo3d: macOS
% uses CBLAS (cblas_*), elsewhere it sets -DUSE_FORTRAN_BLAS (daxpy_, ...). So
% on macOS link Accelerate (provides CBLAS, OS-framework -> self-contained);
% off-macOS link MATLAB's Fortran BLAS/LAPACK (-lmwlapack/-lmwblas, also
% self-contained as MATLAB provides them). The .a precedes the BLAS so the
% linker resolves eltopo's references; <eltopo.h> is already in incFlags via the
% libeltopo target in the manifest.
eltopoLib = libsByCat('eltopo');
if ismac
    blasArgs = {'LDFLAGS=$LDFLAGS -framework Accelerate'};
else
    blasArgs = {'-lmwlapack', '-lmwblas'};
end
fprintf('  mex eltopo\n');
mex(common{:}, '-output', 'eltopo', fullfile(mexDir, 'eltopo.cpp'), ...
    eltopoLib{:}, blasArgs{:});
nBuilt = nBuilt + 1;

% impaste (macOS only): Objective-C++ clipboard paste, two sources
% (impaste.cpp + paste.mm) linking the Cocoa/Foundation system frameworks
% (OS-provided -> self-contained). clang compiles the .mm directly; the
% Homebrew-gcc toolchain can't, which is part of why macOS uses clang.
if ismac
    fprintf('  mex impaste\n');
    % paste.mm is manual-reference-counting Objective-C++; pass -fno-objc-arc so
    % it builds regardless of the toolchain's ARC default (the memory model is a
    % per-.mm property, declared here at the call site rather than in the mexopts).
    mex(common{:}, '-output', 'impaste', ...
        fullfile(mexDir, 'impaste.cpp'), fullfile(mexDir, 'paste.mm'), ...
        'CXXFLAGS=$CXXFLAGS -fno-objc-arc', ...
        'LDFLAGS=$LDFLAGS -framework Cocoa -framework Foundation');
    nBuilt = nBuilt + 1;
end

fprintf('Built %d MEX files.\n', nBuilt);

% ---- 4. Bundle any non-OS / non-MATLAB runtime libs ---------------------
% No-op on macOS/Windows (static mexopts / static deps → self-contained). On
% Linux it copies any genuinely third-party .so (e.g. libgomp) next to the MEX
% with an $ORIGIN rpath. Lives in scripts/, on the path via bundle_one.
mexFiles = dir(fullfile(mexDir, '*.mex*'));
for i = 1:numel(mexFiles)
    bundle_runtime_libs(fullfile(mexFiles(i).folder, mexFiles(i).name));
end

fprintf('=== gptoolbox MEX compilation complete ===\n');


function rmdir_silent(d)
if exist(d, 'dir')
    try; rmdir(d, 's'); catch; end
end
end


function build_autotools_static(url, dirName, cfgArgs, prefix)
% Download an autotools source tarball and install a static lib into `prefix`.
% Used on Linux for gmp/mpfr (no static .a in RHEL/EPEL). Builds in a scratch
% dir that's removed on return; only the installed prefix persists.
work = tempname;
mkdir(work);
cleanupWork = onCleanup(@() rmdir_silent(work)); %#ok<NASGU>
tarball = fullfile(work, 'src.tar.xz');
run_or_error(sprintf('curl -fL --retry 5 -o "%s" "%s"', tarball, url), ...
    ['download ' dirName]);
run_or_error(sprintf('tar xf "%s" -C "%s"', tarball, work), ['extract ' dirName]);
src = fullfile(work, dirName);
run_or_error(sprintf('cd "%s" && ./configure --prefix="%s" %s', ...
    src, prefix, strjoin(cfgArgs, ' ')), ['configure ' dirName]);
run_or_error(sprintf('cd "%s" && make -j%d && make install', ...
    src, feature('numcores')), ['build ' dirName]);
end


function run_or_error(cmd, what)
fprintf('  [%s]\n', what);
[st, out] = system(cmd);
fprintf('%s', out);
if st ~= 0
    error('gptoolbox:linuxDeps', '%s failed (exit %d)', what, st);
end
end
