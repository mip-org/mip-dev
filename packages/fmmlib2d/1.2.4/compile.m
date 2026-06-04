% Compile fmmlib2d MEX file.
% compile.m runs with cwd set to the package source root.
%
% The upstream matlab/fmm2d.c is a pre-generated mwrap gateway; we compile
% the Fortran library sources under src/ to object files, then link them
% with fmm2d.c into a MEX file placed next to the .m shims in matlab/.
% libgfortran, libquadmath, and libgomp are statically linked so the bundle
% runs on end-user machines without a matching gfortran runtime installed.
% OpenMP is enabled (-fopenmp); d2tstrcr_omp.f parallelizes the tree build.

fprintf('=== Compiling fmmlib2d MEX file ===\n');

srcRoot = pwd;
fSrcDir = fullfile(srcRoot, 'src');
matlabDir = fullfile(srcRoot, 'matlab');

if ismac
    setenv('PATH', ['/opt/homebrew/bin:/usr/local/bin:' getenv('PATH')]);
end

if isunix && ~ismac
    origLdPath = getenv('LD_LIBRARY_PATH');
    setenv('LD_LIBRARY_PATH', '');
    restoreLdPath = onCleanup(@() setenv('LD_LIBRARY_PATH', origLdPath));
end

fSources = { ...
    'hfmm2dpart.f', 'hfmm2drouts.f', 'd2tstrcr_omp.f', 'd2mtreeplot.f', ...
    'h2dterms.f', 'helmrouts2d.f', 'cdjseval2d.f', 'hank103.f', ...
    'prini.f', 'cfmm2dpart.f', 'zfmm2dpart.f', 'lfmm2dpart.f', ...
    'rfmm2dpart.f', 'lfmm2drouts.f', 'l2dterms.f', 'laprouts2d.f'};

buildDir = fullfile(srcRoot, 'build_mex');
if ~exist(buildDir, 'dir')
    mkdir(buildDir);
end

fflags = '-O3 -fPIC -std=legacy -funroll-loops -fopenmp -w';

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

mexArgs = {'-largeArrayDims', mexGateway};
for i = 1:numel(objs)
    mexArgs{end+1} = objs{i}; %#ok<AGROW>
end

% Statically link the Fortran/OpenMP runtime (libgfortran, libquadmath,
% libgomp) so the MEX runs on end-user machines without a matching gfortran
% runtime. The toolchain's libgfortran.a / libquadmath.a / libgomp.a must be
% -fPIC for this to succeed; Ubuntu's apt gcc-10+ and Homebrew gfortran both
% qualify. libgomp is listed last so the Fortran objects' GOMP_* references
% resolve against it.
libgfortran_a = strtrim(run_cmd('gfortran --print-file-name=libgfortran.a'));
libquadmath_a = strtrim(run_cmd('gfortran --print-file-name=libquadmath.a'));
libgomp_a = strtrim(run_cmd('gfortran --print-file-name=libgomp.a'));
fprintf('libgfortran: %s\n', libgfortran_a);
fprintf('libquadmath: %s\n', libquadmath_a);
fprintf('libgomp: %s\n', libgomp_a);
mexArgs{end+1} = libgfortran_a;
mexArgs{end+1} = libquadmath_a;
mexArgs{end+1} = libgomp_a;

if isunix && ~ismac
    mexArgs{end+1} = 'LDFLAGS=$LDFLAGS -static-libgcc -static-libstdc++';
end

mexArgs{end+1} = '-output';
mexArgs{end+1} = fullfile(matlabDir, 'fmm2d');

mex(mexArgs{:});

fprintf('=== fmmlib2d MEX compilation complete ===\n');


function out = run_cmd(cmd)
    [status, out] = system(cmd);
    if status ~= 0
        error('fmmlib2d: command failed (%d): %s\n%s', status, cmd, out);
    end
end
