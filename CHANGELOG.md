# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!--
## VERSION - [unreleased]

### Added

### Changed

### Removed

### Fixed
-->

## 0.1.0 - [unreleased]

### Added
- Added changelog.
- Added Settings with circular theme previews for System, Light, Sepia and Dark appearance. Theme changes apply immediately and persist between launches.
- Add app info page.
- Added a persistent default feed setting for Top, New, Best, Ask, Show or Jobs, applied on the next launch.
- Added persistent bookmarks for articles and comments, with a Saved items screen for browsing them and opening comments on Hacker News.
- Added `make clean` to remove generated release artifacts from `dist/`.

### Changed
- The displayed application version is now read from `shard.yml`.
- `make build` now also creates a Fedora 43 x86_64 release archive and its SHA-256 checksum in `dist/`, using the version from `shard.yml`. The archive includes the binary, desktop entry, icon, license and README without bundling system libraries.
- Release packaging recreates the staging directory on each build to exclude stale files.

### Fixed
- Embedded the application icon in the binary so it appears in the About dialog without a desktop installation.
- `make install` now refreshes the icon cache so the installed application icon is discoverable.
- GUI smoke screenshots now wait for a rendered frame instead of failing when the window has not finished drawing.
