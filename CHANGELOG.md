# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2025-10-28

### Added
- **Flattened Field Inheritance**: Zero-overhead OOP with direct field access
  - Parent and mixin fields are flattened directly into child classes
  - No `.super` field or `@ptrCast` required - all fields accessible directly
  - Methods are copied with automatic type name rewriting
  - True zero-cost abstraction matching handwritten Zig code
- **Mixins**: Full support for multiple inheritance via composition
  - Define mixins with `zoop.mixin()` API for clear intent
  - Mixin fields and methods flattened into child classes
  - Works alongside parent inheritance (`extends` + `mixins`)
  - Child methods automatically override mixin methods
  - Comprehensive mixin test suite (`tests/test_mixins.zig`)
- **Inheritance**: Single and multi-level inheritance
  - Cross-file inheritance support
  - Override detection (no duplicate method generation)
  - Init/deinit method copying from parent to child
  - Smart init generation for empty child classes
- **Properties**: Auto-generated getters/setters with `read_only`/`read_write` access control
- **Build-time code generator** (`zoop-codegen`)
  - Two integration patterns (Automatic and Manual)
  - Configurable source/output directories
  - Smart caching with descendant tracking
  - Build helper utilities for easy integration
- **Workflow Tools**: Complete development workflow support
  - Two-directory system (zoop_src/ source, src/ generated)
  - Edit → Build → Test → Commit cycle
  - Never edit generated files (strict rule)
  - Commit both source and generated files together
- **Safety & Performance**
  - Zero runtime overhead (all inline)
  - Path traversal protection
  - Memory-safe code generation
  - Circular dependency detection
  - Input validation and DoS prevention
  - String interning optimization
- **Testing**: Comprehensive test suite (39+ tests)
  - Basic inheritance tests
  - Mixin functionality tests
  - Property inheritance tests
  - Memory safety tests
  - Performance benchmarks
  - Security tests
  - Empty class handling
  - Descendant detection
- **Documentation**: Complete guides and references
  - README.md - User-facing introduction
  - API_REFERENCE.md - Complete API documentation
  - CONSUMER_USAGE.md - Integration guide
  - IMPLEMENTATION.md - Architecture deep-dive
  - WORKFLOW_IMPLEMENTATION.md - Development workflow guide
  - AGENTS.md - AI agent skills documentation
  - Skills system for Claude Code integration
- **Agent Skills**: AI-friendly development support
  - skills/zig/ - General Zig programming
  - skills/zoop-workflow/ - Developing with Zoop
  - skills/zoop-architecture/ - Understanding Zoop's design
  - skills/zoop-codegen/ - Working with code generation
  - skills/zoop-testing/ - Running and writing tests
  - skills/zoop-documentation/ - Updating documentation

---

[Unreleased]: https://github.com/zig-whatwg/zoop/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/zig-whatwg/zoop/releases/tag/v0.1.0
