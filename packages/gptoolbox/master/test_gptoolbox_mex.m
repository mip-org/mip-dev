% Test script for gptoolbox (MEX-enabled builds).
%
% Exercises both the pure-MATLAB layer and a handful of compiled MEX
% functions so that a broken build/link is caught by `mip test`. The MEX
% functions used here (fast_sparse, orient2d, winding_number, eltopo) are built
% on every compiled architecture: the first three are in the retained
% libigl-core / igl::predicates set; eltopo additionally links BLAS/LAPACK and
% guards the El Topo integer-width regression (see eltopo_blas_shim.cpp).

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

%% --- MEX: eltopo (El Topo, links BLAS/LAPACK) -------------------------
% Guards the BLAS integer-width regression: El Topo declares 32-bit `int` BLAS
% args while MATLAB's libmwblas/libmwlapack take 64-bit (ptrdiff_t); the
% eltopo_blas_shim bridges that on Linux/Windows (macOS uses Accelerate). A
% wrong-width link crashes MATLAB inside MKL on the first El Topo BLAS call, so
% simply running a collision below is the regression test.

fprintf('Testing eltopo...\n');
[Vs, Fs] = subdivided_sphere(1);          % small closed icosphere (42 verts)

% (a) No collision: translate one sphere -> full step, U == V1, t == 1.
V0a = Vs;
V1a = Vs + [0.25 0 0];
[Ua, ~, ta] = eltopo(V0a, Fs, V1a);
assert(isequal(size(Ua), size(V0a)), 'eltopo returned wrong-size U');
assert(all(isfinite(Ua(:))), 'eltopo returned non-finite vertices');
assert(abs(ta - 1) < 1e-6, sprintf('eltopo no-collision t was %g, expected 1', ta));
assert(max(abs(Ua(:) - V1a(:))) < 1e-9, 'eltopo no-collision U should equal V1');

% (b) Collision: two spheres (gap 1 between surfaces) driven to fully overlap.
% El Topo resolves the collision (impact zones) and returns collision-free
% positions -- it may still report a full step (t up to 1); the guard is that
% it runs the BLAS path without crashing and keeps the spheres apart.
n  = size(Vs, 1);
V0 = [Vs + [-1.5 0 0]; Vs + [1.5 0 0]];
Fc = [Fs; Fs + n];
V1 = [Vs; Vs];                            % both target the origin
[U, ~, t] = eltopo(V0, Fc, V1);
assert(isequal(size(U), size(V0)), 'eltopo returned wrong-size U');
assert(all(isfinite(U(:))), 'eltopo returned non-finite vertices');
assert(t >= 0 && t <= 1, sprintf('eltopo collision t was %g, expected 0<=t<=1', t));
% The two components must not interpenetrate (closest vertex pair, base MATLAB).
A = U(1:n, :); B = U(n+1:end, :);
gap = sqrt(sum((permute(A,[1 3 2]) - permute(B,[3 1 2])).^2, 3));
assert(min(gap(:)) > 0, ...
    sprintf('eltopo let the spheres interpenetrate (min gap %g)', min(gap(:))));

fprintf('SUCCESS\n');
