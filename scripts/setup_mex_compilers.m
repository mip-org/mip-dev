function setup_mex_compilers(architecture, compiler)
%SETUP_MEX_COMPILERS   Set up the MEX compilers (and export them for CMake).
%
%   setup_mex_compilers(architecture)            % uses gcc
%   setup_mex_compilers(architecture, 'clang')   % uses Apple Clang (macOS)
%
% Configures the MEX C/C++ compilers from ../mexopts/<architecture>/, persisting
% for the session so all subsequent MEX calls in per-package compile.m scripts
% pick them up. Also exports CC/CXX and CMAKE_C_COMPILER/CMAKE_CXX_COMPILER so
% CMake/autotools builds run from compile.m use the same compiler as MEX. (We
% export only the compiler, not the mexopts' full SetEnv: its LDFLAGS is the MEX
% bundle link line -- -bundle, -lmx/-lmex, exported_symbols maps -- which would
% wreck a plain static-library build.)
%
% On windows_x86_64, MEX uses MinGW-w64 (see setup_mingw_windows below). An
% architecture with no mexopts subdirectory at all (e.g. 'any', 'numbl_*') does
% not compile and is skipped silently; requesting a compiler that has no mexopts
% for an architecture that does compile is an error.

if nargin < 2 || isempty(compiler)
    compiler = 'gcc';
end

if strcmp(architecture, 'windows_x86_64')
    setup_mingw_windows();
    return;
end

scriptDir      = fileparts(mfilename('fullpath'));
mexoptsDir     = fullfile(scriptDir, '..', 'mexopts');
archMexoptsDir = fullfile(mexoptsDir, architecture);
if ~isfolder(archMexoptsDir)
    fprintf('No project mexopts for architecture "%s"\n', architecture);
    return;
end

switch compiler
    case 'gcc'
        cXML   = fullfile(archMexoptsDir, 'gcc_static.xml');
        cxxXML = fullfile(archMexoptsDir, 'g++_static.xml');
    case 'clang'
        cXML   = fullfile(archMexoptsDir, 'clang.xml');
        cxxXML = fullfile(archMexoptsDir, 'clang++.xml');
    otherwise
        error('setup_mex_compilers:badCompiler', ...
              'Unknown compiler "%s" (expected ''gcc'' or ''clang'').', compiler);
end

if ~isfile(cXML) || ~isfile(cxxXML)
    error('setup_mex_compilers:noMexopts', ...
          'No "%s" mexopts for architecture "%s" (looked for %s, %s).', ...
          compiler, architecture, cXML, cxxXML);
end

fprintf('Setting up MEX C compiler: %s\n', cXML);
mex(['-setup:' cXML], 'C');
fprintf('Setting up MEX C++ compiler: %s\n', cxxXML);
mex(['-setup:' cxxXML], 'C++');

% CC/CXX (and CMAKE_<LANG>_COMPILER) for CMake/autotools. gcc: the resolved
% path from the mexopts (can't hardcode it -- `gcc` is an alias for clang on
% macOS, and the exact gcc-N is picked dynamically). clang: the absolute Apple
% Clang path from `xcrun -find` -- the clang mexopts invoke it as
% "xcrun -sdk macosx<ver> clang" (a command, not a path CMake can use), and
% xcrun guarantees the same Apple Clang as MEX rather than another clang on PATH.
switch compiler
    case 'gcc'
        cfgC   = mex.getCompilerConfigurations('C',   'Selected');
        cfgCxx = mex.getCompilerConfigurations('C++', 'Selected');
        cc  = cfgC.Details.CompilerExecutable;
        cxx = cfgCxx.Details.CompilerExecutable;
    case 'clang'
        [~, cc]  = system('xcrun -find clang');    cc  = strtrim(cc);
        [~, cxx] = system('xcrun -find clang++');  cxx = strtrim(cxx);
end

setenv('CC', cc);    setenv('CMAKE_C_COMPILER', cc);
setenv('CXX', cxx);  setenv('CMAKE_CXX_COMPILER', cxx);
fprintf('  CC=%s\n  CXX=%s\n', cc, cxx);

end


function setup_mingw_windows()
%SETUP_MINGW_WINDOWS  Select MinGW-w64 as the session MEX compiler on Windows.
%
% MATLAB compiles Windows MEX with MinGW-w64, located via the MW_MINGW64_LOC
% environment variable that mingw64.xml reads. The CI workflow installs the
% MATLAB-certified MinGW (gfortran 8.1.0; see notes/MATLAB-MINGW.md) and
% exports MW_MINGW64_LOC; fall back to a stock C:\mingw64 for local builds.
% Put its bin first on PATH so direct gfortran/mingw32-make calls in package
% compile scripts resolve to the same toolchain, then select it as the
% session MEX C compiler so those scripts call mex() without passing
% -f mingw64.xml (mirroring the gcc_static.xml setup on Linux/macOS). The
% selection and env persist for the session.

mingw = getenv('MW_MINGW64_LOC');
if isempty(mingw)
    mingw = 'C:\mingw64';
end
setenv('MW_MINGW64_LOC', mingw);
setenv('PATH', [fullfile(mingw, 'bin') ';' getenv('PATH')]);
fprintf('Using MinGW-w64 at %s\n', mingw);

xml = fullfile(matlabroot, 'bin', 'win64', 'mexopts', 'mingw64.xml');
if ~isfile(xml)
    error('setup_mex_compilers:noMinGWxml', ...
        'MinGW64 mex options file not found: %s', xml);
end
fprintf('Setting up MEX C compiler: %s\n', xml);
mex(['-setup:' xml], 'C');

end
