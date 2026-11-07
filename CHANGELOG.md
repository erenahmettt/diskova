# Changelog

All notable changes to Diskova are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] — 2026-11-07

First release.

### Added

- Squarified treemap of any folder or volume, with folders drawn nested inside
  one another so a big folder's shape shows what is actually inside it.
- Concurrent scanner that parallelises the top two levels of the tree and
  reports progress while it works.
- Correct totals: hard links counted once, symbolic links never followed,
  mount points not crossed, sizes measured as space allocated on disk.
- Two colour palettes — eight categories, or a measured colour-blind-safe set
  of four — plus a legend, tile labels, a hovered-item readout and an inspector,
  so colour is never the only thing identifying a tile.
- Sidebar listing the current folder's contents and the hundred biggest files
  anywhere in the scan, usable with the keyboard and VoiceOver.
- Move to Trash from inside the app, with the map correcting itself immediately
  instead of rescanning.
- A warning when macOS blocked folders from being read, with a button that opens
  the right System Settings pane.
- English and Turkish.

[Unreleased]: https://github.com/erenahmettt/diskova/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/erenahmettt/diskova/releases/tag/v0.1.0
