% Test script for gptoolbox (pure-MATLAB `any` fallback build).

rng('default');

%% Test normalizerow
fprintf('Testing normalizerow...\n');
A = [3 4; 0 5; 1 0];
B = normalizerow(A);
norms = sqrt(sum(B.^2, 2));
assert(all(abs(norms - 1) < 1e-12), 'normalizerow did not produce unit rows');

%% Test doublearea on a unit-square mesh (two triangles, total area 1)
fprintf('Testing doublearea...\n');
V = [0 0; 1 0; 1 1; 0 1];
F = [1 2 3; 1 3 4];
dblA = doublearea(V, F);
assert(abs(sum(abs(dblA)) - 2) < 1e-12, ...
    sprintf('doublearea sum was %g, expected 2', sum(abs(dblA))));

%% Test cotmatrix returns a symmetric square matrix of the right size
fprintf('Testing cotmatrix...\n');
V3 = [0 0 0; 1 0 0; 0 1 0; 1 1 0];
L = cotmatrix(V3, F);
assert(isequal(size(L), [4 4]), 'cotmatrix returned wrong size');
assert(max(max(abs(L - L.'))) < 1e-12, 'cotmatrix is not symmetric');

fprintf('SUCCESS\n');
