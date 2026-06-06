% Test script for gptoolbox (MEX-enabled builds).
%
% Exercises both the pure-MATLAB layer and a handful of compiled MEX
% functions so that a broken build/link is caught by `mip test`. The MEX
% functions used here (fast_sparse, orient2d, winding_number) are all in the
% retained libigl-core / igl::predicates set, so they are built on every
% compiled architecture.

rng('default');

%% --- Pure MATLAB ------------------------------------------------------

fprintf('Testing normalizerow...\n');
A = [3 4; 0 5; 1 0];
B = normalizerow(A);
norms = sqrt(sum(B.^2, 2));
assert(all(abs(norms - 1) < 1e-12), 'normalizerow did not produce unit rows');

fprintf('Testing doublearea...\n');
V2 = [0 0; 1 0; 1 1; 0 1];
F  = [1 2 3; 1 3 4];
dblA = doublearea(V2, F);
assert(abs(sum(abs(dblA)) - 2) < 1e-12, ...
    sprintf('doublearea sum was %g, expected 2', sum(abs(dblA))));

fprintf('Testing cotmatrix...\n');
V3 = [0 0 0; 1 0 0; 0 1 0; 1 1 0];
L = cotmatrix(V3, F);
assert(isequal(size(L), [4 4]), 'cotmatrix returned wrong size');
assert(max(max(abs(L - L.'))) < 1e-12, 'cotmatrix is not symmetric');

%% --- MEX: fast_sparse (libigl-core) -----------------------------------

fprintf('Testing fast_sparse...\n');
I = [1; 2; 3; 1];
J = [1; 2; 3; 2];
Vv = [10; 20; 30; 5];
S_fast = fast_sparse(I, J, Vv, 3, 3);
S_ref  = sparse(I, J, Vv, 3, 3);
assert(isequal(full(S_fast), full(S_ref)), ...
    'fast_sparse disagrees with sparse');

%% --- MEX: orient2d (libigl::predicates) -------------------------------

fprintf('Testing orient2d...\n');
Ap = [0 0];
Bp = [1 0];
Cp_ccw = [0 1];    % counter-clockwise -> positive
Cp_cw  = [0 -1];   % clockwise         -> negative
assert(orient2d(Ap, Bp, Cp_ccw) > 0, 'orient2d(ccw) should be positive');
assert(orient2d(Ap, Bp, Cp_cw)  < 0, 'orient2d(cw) should be negative');

%% --- MEX: winding_number (libigl-core) --------------------------------

fprintf('Testing winding_number...\n');
% Unit cube mesh centered at the origin.
Vc = [ ...
    -1 -1 -1;  1 -1 -1;  1  1 -1; -1  1 -1; ...
    -1 -1  1;  1 -1  1;  1  1  1; -1  1  1] * 0.5;
Fc = [ ...
    1 3 2; 1 4 3;   % -z
    5 6 7; 5 7 8;   % +z
    1 2 6; 1 6 5;   % -y
    4 7 3; 4 8 7;   % +y
    1 5 8; 1 8 4;   % -x
    2 3 7; 2 7 6];  % +x
inside  = [0 0 0];
outside = [10 0 0];
w_in  = winding_number(Vc, Fc, inside);
w_out = winding_number(Vc, Fc, outside);
assert(abs(abs(w_in) - 1) < 1e-6, ...
    sprintf('winding_number inside was %g, expected |w|=1', w_in));
assert(abs(w_out) < 1e-6, ...
    sprintf('winding_number outside was %g, expected 0', w_out));

fprintf('SUCCESS\n');
