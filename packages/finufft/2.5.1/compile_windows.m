% Build the FINUFFT MEX (Windows / MinGW-w64).
% compile.m runs with cwd set to the package source root (the full finufft repo).
%
% The channel's Windows MEX compiler is MinGW-w64 (selected by
% setup_mex_compilers, which also exports CMAKE_C_COMPILER/CMAKE_CXX_COMPILER).
% A MEX gateway can only link object code from the same compiler, so we build
% the FINUFFT static library with the MinGW Makefiles generator (gcc/g++),
% using the bundled DUCC0 FFT backend so there is no external dependency, then
% link it with an unadorned mex(). mingw64.xml links -static, so the .mexw64
% bakes in libstdc++/libgcc and needs no runtime-library bundling.

fprintf('=== Compiling FINUFFT MEX file (Windows/MinGW-w64) ===\n');

srcRoot = pwd;
buildDir = fullfile(srcRoot, 'build_mex');
if ~exist(buildDir, 'dir')
    mkdir(buildDir);
end

% FINUFFT supplies its own rand_r() under _WIN32 because MSVC lacks the POSIX
% function. Under MinGW-w64 that declaration clashes with the toolchain's own
% rand_r and fails to compile. rand_r is only used by the (unbuilt) test code,
% so guard FINUFFT's version out for MinGW.
guard_mingw(fullfile(srcRoot, 'include', 'finufft', 'finufft_utils.hpp'), ...
    'generator for Windows platform[^\n]*\r?\n');
guard_mingw(fullfile(srcRoot, 'src', 'finufft_utils.cpp'), ...
    'supplied in linux/macosx\)[^\n]*\r?\n');

% Step 1: Build the FINUFFT static library with CMake (MinGW Makefiles).
fprintf('Configuring FINUFFT with CMake (MinGW Makefiles)...\n');
cfgCmd = sprintf(['cmake -S "%s" -B "%s" -G "MinGW Makefiles"', ...
    ' -DCMAKE_BUILD_TYPE=Release', ...
    ' -DFINUFFT_USE_OPENMP=OFF', ...
    ' -DFINUFFT_USE_DUCC0=ON', ...
    ' -DFINUFFT_STATIC_LINKING=ON', ...
    ' -DFINUFFT_BUILD_TESTS=OFF', ...
    ' -DFINUFFT_BUILD_EXAMPLES=OFF', ...
    ' -DFINUFFT_ENABLE_INSTALL=OFF'], srcRoot, buildDir);
[status, output] = system(cfgCmd, '-echo');
if status ~= 0
    error('CMake configuration failed (exit code %d)', status);
end

fprintf('Building FINUFFT static library...\n');
buildCmd = sprintf('cmake --build "%s" --target finufft -j%d', buildDir, maxNumCompThreads);
[status, output] = system(buildCmd, '-echo');
if status ~= 0
    error('CMake build failed (exit code %d)', status);
end

% Step 2: Locate the static libraries (MinGW Makefiles is single-config).
libFinufft = fullfile(buildDir, 'src', 'libfinufft.a');
libCommon  = fullfile(buildDir, 'src', 'common', 'libfinufft_common.a');
ducc0Path  = find_file_recursive(buildDir, 'libducc0.a');

if ~exist(libFinufft, 'file')
    error('finufft library not found at %s', libFinufft);
end
if ~exist(libCommon, 'file')
    error('finufft_common library not found at %s', libCommon);
end
fprintf('Libraries found:\n  finufft: %s\n  common:  %s\n', libFinufft, libCommon);
if ~isempty(ducc0Path)
    fprintf('  ducc0:   %s\n', ducc0Path);
end

% Step 3: Compile the MEX file with the (MinGW) mex.
fprintf('Compiling MEX file...\n');
mexArgs = {fullfile(srcRoot, 'matlab', 'finufft.cpp'), ...
    ['-I' fullfile(srcRoot, 'include')], ...
    '-R2018a', '-DR2008OO', ...
    libFinufft, libCommon};
if ~isempty(ducc0Path)
    mexArgs{end+1} = ducc0Path;
end
mexArgs{end+1} = '-output';
mexArgs{end+1} = fullfile(srcRoot, 'matlab', 'finufft');
mex(mexArgs{:});

fprintf('=== FINUFFT MEX compilation complete ===\n');


function filepath = find_file_recursive(searchDir, filename)
    result = dir(fullfile(searchDir, '**', filename));
    if ~isempty(result)
        filepath = fullfile(result(1).folder, result(1).name);
    else
        filepath = '';
    end
end

function guard_mingw(file, anchorPattern)
    % Replace the `#ifdef _WIN32` immediately following anchorPattern with a
    % guard that also excludes MinGW. CRLF-robust; errors if the anchor moves.
    txt = fileread(file);
    pat = ['(' anchorPattern ')#ifdef _WIN32'];
    rep = '$1#if defined(_WIN32) && !defined(__MINGW32__)';
    out = regexprep(txt, pat, rep, 'once');
    if strcmp(out, txt)
        error('guard_mingw: expected _WIN32 guard not found in %s', file);
    end
    fid = fopen(file, 'w');
    if fid < 0
        error('guard_mingw: cannot write %s', file);
    end
    fwrite(fid, out);
    fclose(fid);
    fprintf('  guarded _WIN32 rand_r block for MinGW in %s\n', file);
end
