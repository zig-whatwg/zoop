# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0-beta] - 2025-10-25

### Added
- **Mixins**: Full support for multiple inheritance via composition
  - Mixin fields are flattened directly into child classes
  - Mixin methods are copied with automatic type name rewriting
  - Works alongside parent inheritance (`extends` + `mixins`)
  - Child methods automatically override mixin methods
- Comprehensive mixin test suite (`tests/test_mixins.zig`)
- Mixin documentation in README.md, API_REFERENCE.md, and CONSUMER_USAGE.md
- Updated `class.zig` comptime stub to handle mixin field merging

### Changed
- Enhanced `mergeFields()` function to support parent, mixins, and child fields
- Updated feature lists across all documentation

## [0.1.0-beta] - 2025-10-25

### Added
- Initial beta release
- Single and multi-level inheritance
- Cross-file inheritance
- Properties with auto-generated getters/setters
- Method forwarding with configurable prefixes
- Override detection
- Init/deinit inheritance
- Zero runtime overhead (all inline)
- Path traversal protection
- Memory-safe code generation
- Comprehensive test suite
- Full documentation (README, API_REFERENCE, CONSUMER_USAGE, IMPLEMENTATION)
- Build-time code generator (`zoop-codegen`)
- Two integration patterns (Automatic and Manual)

[Unreleased]: https://github.com/yourname/zoop/compare/v0.2.0-beta...HEAD
[0.2.0-beta]: https://github.com/yourname/zoop/compare/v0.1.0-beta...v0.2.0-beta
[0.1.0-beta]: https://github.com/yourname/zoop/releases/tag/v0.1.0-beta
