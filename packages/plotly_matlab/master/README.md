# plotly_matlab

[plotly_matlab](https://plotly.com/matlab/) converts MATLAB figures into interactive [Plotly](https://plotly.com) graphs. The main entry points are `fig2plotly` and the `plotlyfig` class.

- **Author**: Plotly Technologies Inc.
- **License**: MIT
- **Version**: `master` (the latest tagged release, `3.0.0`, has a bug that breaks the core figure→Plotly conversion — an undefined `toC` in `extractAxisData.m`, fixed on master — and there is no newer tag)
- **Repository**: https://github.com/plotly/plotly_matlab

## Install

```matlab
mip install --channel mip-org/dev plotly_matlab
mip load plotly_matlab
```

`mip load` puts the whole `plotly/` tree on the path (the same set `plotlysetup_offline.m` adds via `genpath`). You can immediately convert a figure to a Plotly figure structure:

```matlab
plot(1:10, (1:10).^2);
p = plotlyfig(gcf, 'Offline', true);   % p.data / p.layout hold the Plotly spec
```

## Offline rendering and online accounts

The conversion itself (MATLAB figure → Plotly `data`/`layout`) needs neither a network connection nor a Plotly account. Two optional, user-level setup steps enable more:

- **Offline HTML rendering** — to render figures to self-contained HTML, download the Plotly JavaScript bundle once (writes to `~/.plotly/`, requires network):

  ```matlab
  getplotlyoffline('https://cdn.plot.ly/plotly-latest.min.js')
  ```

- **Online (plot.ly cloud)** — to push graphs to a Plotly account, run `plotlysetup_online(username, api_key)`.

Neither step is performed by `mip` (both write to your home directory / require credentials), matching how the toolbox is set up upstream.

## Architecture

Pure MATLAB — a single `[any]` build, no compiled code.

## Tests

`test_plotly_channel.m` builds a simple line plot, converts it with `plotlyfig(..., 'Offline', true)`, and checks that the resulting Plotly trace and layout match the figure — exercising the core conversion path without a network connection or account.
