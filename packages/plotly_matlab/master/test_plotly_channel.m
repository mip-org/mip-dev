% Channel post-install test for plotly_matlab (pure MATLAB).
% Exercises the core MATLAB-figure -> Plotly conversion offline, without a
% Plotly account or network access.

fprintf('=== Testing plotly_matlab ===\n');

assert(~isempty(which('plotlyfig')), 'plotlyfig is not on the path');
assert(~isempty(which('fig2plotly')), 'fig2plotly is not on the path');

% Build a simple figure and convert it to a Plotly figure structure.
fig = figure('Visible', 'off');
cleanup = onCleanup(@() close(fig));
plot(1:10, (1:10).^2);

p = plotlyfig(fig, 'Offline', true);
assert(isa(p, 'plotlyfig'), 'plotlyfig did not return a plotlyfig object');
assert(~isempty(p.data), 'conversion produced no traces');

trace = p.data{1};
assert(strcmp(trace.type, 'scatter'), 'expected a scatter trace, got %s', trace.type);
assert(numel(trace.y) == 10 && abs(trace.y(3) - 9) < 1e-12, ...
    'trace y-data does not match the plotted curve');
assert(~isempty(fieldnames(p.layout)), 'conversion produced an empty layout');

fprintf('  Figure -> Plotly conversion OK (%d trace, %d layout fields)\n', ...
    numel(p.data), numel(fieldnames(p.layout)));

fprintf('=== plotly_matlab test passed ===\n');
