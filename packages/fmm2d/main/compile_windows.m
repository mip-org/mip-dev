function compile()

% Compile fmm2d MEX on Windows using MinGW-w64 (gfortran) + MATLAB's
% built-in mingw64 mex configuration. compile.m runs with cwd set to the
% package source root.
%
% The fmm2d library is Fortran; MATLAB's default Windows C compiler (MSVC)
% cannot link gfortran objects, so the C gateway must be compiled by the
% same MinGW toolchain that builds the static library. MATLAB's
% mingw64.xml links -static, so the resulting .mexw64 carries no MinGW
% runtime DLL dependency (libgfortran/libgomp/... are baked in) and needs
% no runtime-library bundling.
%
% Toolchain selection: prefer the MinGW the CI workflow installed and
% exported via MW_MINGW64_LOC (the version MATLAB certifies for this
% release — 8.1.0 for R2023b; see notes/MATLAB-MINGW.md). MW_MINGW64_LOC
% is the documented hook MATLAB's mingw64.xml reads to locate a
% self-installed MinGW, so no XML editing or support-package install is
% needed. Fall back to the runner/dev stock C:\mingw64 when unset.

mingw = getenv('MW_MINGW64_LOC');
if isempty(mingw)
    mingw = 'C:\mingw64';
end
setenv('MW_MINGW64_LOC', mingw);            % let MATLAB's mingw64.xml find it
setenv('PATH', [fullfile(mingw, 'bin') ';' getenv('PATH')]);

fprintf('Compiling fmm2d MEX files (Windows/MinGW-w64)...\n');

% -fallow-argument-mismatch exists only on gfortran >= 10, where legacy
% rank/type argument mismatches became hard errors; the flag downgrades
% them back to warnings. On older gfortran (the certified 8.1.0) the flag
% is unrecognized and the mismatches are warnings already, so add it only
% when the active compiler needs it. Mirrors compile.m (GCC 8.5 on Linux,
% which omits the flag).
fflags = '-O3 -funroll-loops -std=legacy -w';
[vs, vout] = system('gfortran -dumpversion');
if vs == 0
    tok = regexp(strtrim(vout), '^(\d+)', 'tokens', 'once');
    if ~isempty(tok) && str2double(tok{1}) >= 10
        fflags = [fflags ' -fallow-argument-mismatch'];
    end
end

make_inc = {
    'CC=gcc'
    'CXX=g++'
    'FC=gfortran'
    ['FFLAGS=' fflags]
    'CFLAGS=-O3 -funroll-loops -w'
    'OMPFLAGS=-fopenmp'
    'OMPLIBS=-lgomp'
};
writelines(make_inc, 'make.inc');

% Build the static library (gfortran). The MEX target needs only this, not
% the shared .dll, so build the static lib explicitly.
status = system('mingw32-make libfmm2d.a');
if status ~= 0
    error('fmm2d:makeLibFailed', 'mingw32-make libfmm2d.a failed with exit code %d', status);
end

% Directory holding libgfortran.a / libquadmath.a / libgomp.a, for -L.
[s, fdir] = system('gfortran -print-file-name=libgfortran.a');
if s ~= 0
    error('fmm2d:gfortran', 'could not locate gfortran runtime libraries');
end
fdir = fileparts(strtrim(fdir));

% Link the MEX with MATLAB's MinGW64 options file (forces MinGW over MSVC).
xml = fullfile(matlabroot, 'bin', 'win64', 'mexopts', 'mingw64.xml');
mex('-f', xml, '-compatibleArrayDims', '-DMWF77_UNDERSCORE1', '-D_OPENMP', ...
    fullfile('matlab', 'fmm2d.c'), fullfile('lib-static', 'libfmm2d.a'), ...
    ['-L' fdir], '-lgfortran', '-lquadmath', '-lgomp', ...
    '-outdir', 'matlab', '-output', 'fmm2d');

fprintf('fmm2d MEX compilation completed.\n');

end
