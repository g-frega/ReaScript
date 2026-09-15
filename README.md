# ReaScript

Personal REAPER scripts by Giacomo Frega, packaged for installation with [ReaPack](https://reapack.com/).

## Install with ReaPack

1. In REAPER, open **Extensions > ReaPack > Manage repositories**.
2. Choose **Import**.
3. Add this index URL:

   `https://raw.githubusercontent.com/g-frega/ReaScript/main/index.xml`

4. Synchronize packages and select the scripts you want to install.

Packages install below `Scripts/gf_scripts/` so they match the development layout used in the REAPER workspace.

## Dependencies

- `gf_MorphMatrix-TrackFX.lua` requires the [ReaImGui](https://github.com/cfillion/reaimgui) extension version 0.10.0.5 or newer.
- `gf_Scatter-Instrument.lua` requires the [ReaImGui](https://github.com/cfillion/reaimgui) extension version 0.9.2 or newer.
- The standalone utilities use the REAPER Lua API and do not bundle third-party libraries.

Install ReaImGui through ReaPack before launching either graphical package.

## Repository layout

- `index.xml` — ReaPack repository index.
- `gf_scripts/` — curated installable files.
- `gf_scripts/gf_MorphMatrix/` — Track-FX Morph Matrix and its internal modules.
- `gf_scripts/gf_Scatter-Instrument/` — Scatter Instrument and its internal data files/assets.

The source/development folder remains at `C:\REAPER\Scripts\gf_scripts`. This repository is a curated staging area: changes are copied into `gf_scripts/` deliberately rather than publishing the entire REAPER profile.

## Release workflow

1. Make and test changes in `C:\REAPER\Scripts\gf_scripts`.
2. Copy only the intended files into this repository's `gf_scripts/` tree.
3. Update the package version in `index.xml` and the script header when behavior changes.
4. Add a concise changelog entry to the corresponding `<version>` element.
5. Validate the XML and run the applicable REAPER tests before committing and pushing.
6. Keep the raw `index.xml` URL stable; ReaPack will discover later versions after synchronization.

Packaging-only changes do not change runtime behavior. The first public release intentionally excludes the MCP bridge, tests, user presets, caches, and scripts derived from third-party repositories until their distribution and dependency terms are reviewed.

## License

A repository-wide license has not yet been selected. Until an explicit license is added, copyright remains with the respective authors. Third-party-derived scripts are not included in this initial package set.
