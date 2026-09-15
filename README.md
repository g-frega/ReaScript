# ReaScript

Personal REAPER scripts by Giacomo Frega, packaged for installation with [ReaPack](https://reapack.com/).

## Install with ReaPack

1. In REAPER, open **Extensions > ReaPack > Manage repositories**.
2. Choose **Import**.
3. Add this index URL:

   `https://raw.githubusercontent.com/g-frega/ReaScript/main/index.xml`

4. Synchronize packages and select the scripts you want to install.

Packages install below `Scripts/gf_scripts/` so they match this source directory.

## Single source of truth

This directory is both the development source and the Git repository root:

`C:\REAPER\Scripts\gf_scripts`

Edit, test, commit, and push scripts from this directory. There is no separate staging or copy step. The repository index and documentation live beside the scripts they describe.

The source tree also contains local-only development files, including tests, user presets, the MCP bridge, and third-party-derived utilities. Those files remain available locally but are excluded from the public Git repository through `.gitignore` unless explicitly packaged later.

## Dependencies

- `gf_MorphMatrix/gf_MorphMatrix-TrackFX.lua` requires the [ReaImGui](https://github.com/cfillion/reaimgui) extension version 0.10.0.5 or newer.
- `gf_Scatter-Instrument/gf_Scatter-Instrument.lua` requires the [ReaImGui](https://github.com/cfillion/reaimgui) extension version 0.9.2 or newer.
- The standalone utilities use the REAPER Lua API and do not bundle third-party libraries.

Install ReaImGui through ReaPack before launching either graphical package.

## Repository layout

- `index.xml` — ReaPack repository index.
- Root-level `gf_*.lua` files — standalone installable scripts.
- `gf_MorphMatrix/` — Track-FX Morph Matrix and its internal modules.
- `gf_Scatter-Instrument/` — Scatter Instrument and its internal data files/assets.

The index uses ReaPack's supported `../../gf_scripts/...` destination paths. ReaPack resolves script package paths relative to `Scripts/<repository>/<category>`, so this intentionally installs into the default `Scripts/gf_scripts/` folder.

## Release workflow

1. Make and test changes directly in `C:\REAPER\Scripts\gf_scripts`.
2. Update the package version in `index.xml` and the corresponding script header when behavior or packaging changes.
3. Add a concise changelog entry to the corresponding `<version>` element.
4. Validate the XML and run the applicable REAPER tests.
5. Commit and push from this directory.
6. Keep the raw `index.xml` URL stable; ReaPack will discover later versions after synchronization.

Version `1.0.2` (or `1.1.2` for the marker utility) is the single-source migration release. It moves the Git repository root from the former staging layout into this source directory; no script behavior changes are intended.

## License

A repository-wide license has not yet been selected. Until an explicit license is added, copyright remains with the respective authors. Third-party-derived scripts are not included in the public package set.
