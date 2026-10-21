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

## 0.2.0 - [unreleased]

### Added
- Added persistent bookmarks for articles and comments, with a Saved items screen for browsing them and opening comments on Hacker News.
- Added a native reading view that extracts the main article text, with a per-article Reader toggle and automatic website fallback.
- Added persistent read marks, an Only unread feed filter, and controls to mark stories as unread without clearing reading progress.
- Reopening a story restores its Article/Discussion tab, Reader mode, separate reading positions for the reader, website and discussion, and expanded and paginated comment threads.

### Changed
- The displayed application version is now read from `shard.yml`.
- Articles open in Reader mode by default; this can be disabled persistently in Settings.
- Story headers use a compact shared row for Article/Discussion tabs and save/unread actions, with an icon button for marking a story unread.
- The application, desktop entry and icon now use the ID `com.makridenko.HNReader`.

### Fixed
- Reader mode no longer waits for images, analytics and other secondary page resources before rendering an article.
- Reader mode renders headings, paragraphs, quotes, lists and code as separate native blocks so long article layouts remain readable.
- Reader mode cleans hidden and service content before extraction, omits empty links, and falls back to the website when too little readable text remains.
- Reader text collapses HTML whitespace while preserving preformatted code; numbered lists retain their numbering and nested headings no longer create excessive spacing.
- Release workflow reruns preserve existing published assets and upload only missing files, verifying incomplete archive/checksum pairs before upload.

## 0.1.0

### Added
- Added changelog.
- Added Settings with circular theme previews for System, Light, Sepia and Dark appearance. Theme changes apply immediately and persist between launches.
- Add app info page.
- Added a persistent default feed setting for Top, New, Best, Ask, Show or Jobs, applied on the next launch.
- Added `make clean` to remove generated release artifacts from `dist/`.

### Changed
- `make build` now also creates a Fedora 43 x86_64 release archive and its SHA-256 checksum in `dist/`, using the version from `shard.yml`. The archive includes the binary, desktop entry, icon, license and README without bundling system libraries.
- Release packaging recreates the staging directory on each build to exclude stale files.

### Fixed
- Embedded the application icon in the binary so it appears in the About dialog without a desktop installation.
- `make install` now refreshes the icon cache so the installed application icon is discoverable.
- GUI smoke screenshots now wait for a rendered frame instead of failing when the window has not finished drawing.
