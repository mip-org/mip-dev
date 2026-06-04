function compile_windows()

% Compile fmmlib2d MEX on Windows using MinGW-w64 (gfortran) + MATLAB's
% built-in mingw64 mex configuration. compile_windows.m runs with cwd set to
% the package source root.
%
% Mirrors compile.m (the Linux/macOS build): the upstream Fortran sources
% under src/ are compiled to objects with gfortran, then linked with the
% pre-generated mwrap gateway matlab/fmm2d.c into a MEX file. MATLAB's
% default Windows C compiler (MSVC) cannot link gfortran objects, so the
% gateway is compiled by the same MinGW toolchain. MATLAB's mingw64.xml
% links -static, so the resulting .mexw64 bakes in libgfortran/libquadmath/
% libgomp and carries no MinGW runtime DLL dependency, needing no bundling.
%
% OpenMP is enabled (-fopenmp); d2tstrcr_omp.f parallelizes the tree build.

fprintf('=== Compiling fmmlib2d MEX file (Windows/MinGW-w64) ===\n');

mingw = 'C:\mingw64';                       % GCC 15.x with static libgfortran.a
setenv('MW_MINGW64_LOC', mingw);            % let MATLAB's mingw64.xml find it
setenv('PATH', [fullfile(mingw, 'bin') ';' getenv('PATH')]);

srcRoot = pwd;
fSrcDir = fullfile(srcRoot, 'src');
matlabDir = fullfile(srcRoot, 'matlab');

fSources = { ...
    'hfmm2dpart.f', 'hfmm2drouts.f', 'd2tstrcr_omp.f', 'd2mtreeplot.f', ...
    'h2dterms.f', 'helmrouts2d.f', 'cdjseval2d.f', 'hank103.f', ...
    'prini.f', 'cfmm2dpart.f', 'zfmm2dpart.f', 'lfmm2dpart.f', ...
    'rfmm2dpart.f', 'lfmm2drouts.f', 'l2dterms.f', 'laprouts2d.f'};

buildDir = fullfile(srcRoot, 'build_mex');
if ~exist(buildDir, 'dir')
    mkdir(buildDir);
end

fflags = '-O3 -std=legacy -funroll-loops -fallow-argument-mismatch -fopenmp -w';

objs = cell(1, numel(fSources));
for i = 1:numel(fSources)
    srcFile = fullfile(fSrcDir, fSources{i});
    if ~exist(srcFile, 'file')
        error('fmmlib2d: missing Fortran source %s', srcFile);
    end
    [~, base] = fileparts(srcFile);
    objFile = fullfile(buildDir, [base '.o']);
    cmd = sprintf('gfortran %s -c "%s" -o "%s"', fflags, srcFile, objFile);
    fprintf('%s\n', cmd);
    [status, output] = system(cmd);
    fprintf('%s', output);
    if status ~= 0
        error('fmmlib2d: gfortran failed for %s (exit %d)', srcFile, status);
    end
    objs{i} = objFile;
end

mexGateway = fullfile(matlabDir, 'fmm2d.c');

% Directory holding libgfortran.a / libquadmath.a / libgomp.a, for -L.
[s, fdir] = system('gfortran -print-file-name=libgfortran.a');
if s ~= 0
    error('fmmlib2d: could not locate gfortran runtime libraries');
end
fdir = fileparts(strtrim(fdir));
fprintf('gfortran runtime dir: %s\n', fdir);

% Link with MATLAB's MinGW64 options file (forces MinGW over MSVC).
% mingw64.xml links -static, so -lgfortran/-lquadmath/-lgomp resolve to the
% static archives and the .mexw64 carries no MinGW runtime DLL imports.
% -DMWF77_UNDERSCORE1 selects gfortran's single-trailing-underscore symbol
% mangling for the mwrap gateway.
xml = fullfile(matlabroot, 'bin', 'win64', 'mexopts', 'mingw64.xml');
if ~isfile(xml)
    error('fmmlib2d: MinGW64 mex options file not found: %s', xml);
end

mexArgs = {'-f', xml, '-largeArrayDims', '-DMWF77_UNDERSCORE1', mexGateway};
for i = 1:numel(objs)
    mexArgs{end+1} = objs{i}; %#ok<AGROW>
end
mexArgs{end+1} = ['-L' fdir];
mexArgs{end+1} = '-lgfortran';
mexArgs{end+1} = '-lquadmath';
mexArgs{end+1} = '-lgomp';
mexArgs{end+1} = '-output';
mexArgs{end+1} = fullfile(matlabDir, 'fmm2d');

mex(mexArgs{:});

fprintf('=== fmmlib2d MEX compilation complete ===\n');

end
