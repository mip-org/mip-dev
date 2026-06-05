% Channel test for SeDuMi.
% Solves a tiny LP with a known optimum to exercise the MEX layer.

fprintf('Testing that sedumi is on the path...\n');
assert(exist('sedumi', 'file') == 2, 'sedumi.m not found on path');

%% Minimize 2*x1 + 3*x2 subject to x1 + x2 = 1, x >= 0.
% Optimum: x = [1; 0], c'x = 2.
fprintf('Solving small LP...\n');
A = sparse([1, 1]);
b = 1;
c = [2; 3];
K = struct('l', 2);
pars = struct('fid', 0);
[x, y, info] = sedumi(A, b, c, K, pars);

assert(info.pinf == 0 && info.dinf == 0, ...
    sprintf('sedumi reported infeasibility (pinf=%d, dinf=%d)', ...
        info.pinf, info.dinf));
assert(info.numerr ~= 2, ...
    'sedumi reported complete numerical failure (numerr == 2)');

cx = c' * x;
by = b' * y;
assert(abs(cx - 2) < 1e-6, ...
    sprintf('primal cost c''x = %g, expected 2', cx));
assert(abs(by - 2) < 1e-6, ...
    sprintf('dual cost b''y = %g, expected 2', by));
assert(abs(x(1) - 1) < 1e-4 && abs(x(2)) < 1e-4, ...
    sprintf('x = [%g; %g], expected [1; 0]', x(1), x(2)));

fprintf('SUCCESS\n');
