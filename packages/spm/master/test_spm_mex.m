% MEX-enabled smoke test for SPM.
%
% Exercises the pure-MATLAB layer plus a handful of compiled MEX
% functions so that a broken build/link is caught by `mip test` rather
% than surfacing later in user code.

rng('default');

%% --- Pure MATLAB -------------------------------------------------------

fprintf('Testing that spm.m is on the path...\n');
assert(~isempty(which('spm')), 'spm.m is not on the MATLAB path');

fprintf('Testing spm_file...\n');
b = spm_file('/tmp/foo.txt', 'basename');
assert(strcmp(b, 'foo'), ...
    sprintf('spm_file basename returned "%s", expected "foo"', b));

fprintf('Testing spm_platform...\n');
ext = spm_platform('mexext');
assert(ischar(ext) && startsWith(ext, 'mex'), ...
    sprintf('spm_platform(''mexext'') returned "%s"', ext));

%% --- MEX: spm_bsplinc (MEX-only, no MATLAB fallback) -------------------

fprintf('Testing spm_bsplinc...\n');
V = rand(7, 7, 7);
c = spm_bsplinc(V, [3 3 3 0 0 0]);
assert(isequal(size(c), size(V)), ...
    sprintf('spm_bsplinc returned size [%s], expected [%s]', ...
            num2str(size(c)), num2str(size(V))));
assert(isa(c, 'single') || isa(c, 'double'), ...
    'spm_bsplinc returned unexpected class');

%% --- MEX: spm_cat ------------------------------------------------------

fprintf('Testing spm_cat...\n');
M = spm_cat({eye(2), zeros(2); zeros(2), [1 1; 1 1]});
expected = [1 0 0 0; 0 1 0 0; 0 0 1 1; 0 0 1 1];
assert(isequal(full(M), expected), 'spm_cat did not produce the expected block matrix');

%% --- MEX: spm_jsonread -------------------------------------------------

fprintf('Testing spm_jsonread...\n');
j = spm_jsonread('{"a": 1, "b": [2, 3]}');
assert(isstruct(j) && isfield(j, 'a') && isfield(j, 'b'), ...
    'spm_jsonread did not return a struct with fields a and b');
assert(j.a == 1, sprintf('spm_jsonread: j.a = %g, expected 1', j.a));
assert(isequal(j.b(:)', [2 3]), 'spm_jsonread: j.b was not [2 3]');

fprintf('SUCCESS\n');
