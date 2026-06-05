function setup_mex_compilers(architecture)
%SETUP_MEX_COMPILERS   Setup the default MEX compilers.
%
% Configures MEX C/C++ compilers to use the gcc_static.xml/g++_static.xml files
% under ../mexopts/<architecture>/, if present. The setup persists for the
% current MATLAB session, so all subsequent MEX calls in per-package compile.m
% scripts pick it up automatically. Also exports CC and CXX environment
% variables to match the resolved compilers, so CMake/autotools invocations
% from compile.m scripts use the same toolchain as MEX.
%
% On windows_x86_64, MEX uses MinGW-w64 instead (see setup_mingw_windows
% below). Other architectures without a matching mexopts subdirectory (e.g.
% 'any', 'numbl_*') are skipped silently.

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

gccXML = fullfile(archMexoptsDir, 'gcc_static.xml');
gxxXML = fullfile(archMexoptsDir, 'g++_static.xml');

if isfile(gccXML)
    fprintf('Setting up MEX C compiler: %s\n', gccXML);
    mex(['-setup:' gccXML], 'C');
    cfg = mex.getCompilerConfigurations('C');
    setenv('CC', cfg.Details.CompilerExecutable);
    fprintf('  CC=%s\n', cfg.Details.CompilerExecutable);
end

if isfile(gxxXML)
    fprintf('Setting up MEX C++ compiler: %s\n', gxxXML);
    mex(['-setup:' gxxXML], 'C++');
    cfg = mex.getCompilerConfigurations('C++');
    setenv('CXX', cfg.Details.CompilerExecutable);
    fprintf('  CXX=%s\n', cfg.Details.CompilerExecutable);
end

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
