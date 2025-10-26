# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2025-10-25

### Added
- **Mixins**: Full support for multiple inheritance via composition
  - Mixin fields are flattened directly into child classes
  - Mixin methods are copied with automatic type name rewriting
  - Works alongside parent inheritance (`extends` + `mixins`)
  - Child methods automatically override mixin methods
  - Comprehensive mixin test suite (`tests/test_mixins.zig`)
  - Mixin documentation in README.md, API_REFERENCE.md, and CONSUMER_USAGE.md
- **Inheritance**: Single and multi-level inheritance with embedded `super` fields
  - Cross-file inheritance support
  - Override detection (no duplicate method generation)
  - Init/deinit inheritance
- **Properties**: Auto-generated getters/setters with `read_only`/`read_write` access control
- **Method forwarding**: Automatic delegation with configurable prefixes
- **Build-time code generator** (`zoop-codegen`)
  - Two integration patterns (Automatic and Manual)
  - Configurable source/output directories
  - Configurable method name prefixes
- **Safety & Performance**
  - Zero runtime overhead (all inline)
  - Path traversal protection
  - Memory-safe code generation
  - Circular dependency detection
- **Testing**: Comprehensive test suite with 39 tests
- **Documentation**: Complete guides (README, API_REFERENCE, CONSUMER_USAGE, IMPLEMENTATION)

[Unreleased]: https://github.com/yourname/zoop/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/yourname/zoop/releases/tag/v0.1.0
