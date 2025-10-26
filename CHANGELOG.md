# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **BREAKING**: Removed `method_prefix` configuration option
  - Inherited methods are now always copied directly without prefixes
  - Only property accessors (getters/setters) use configurable prefixes
  - Migration: Remove `--method-prefix` from build.zig and update method calls (e.g., `employee.call_greet()` → `employee.greet()`)
  - Rationale: Simplifies API and matches actual implementation behavior
  - See migration guide below for details

### Fixed
- Updated all documentation to reflect flattened field inheritance
- Updated examples to use direct field access instead of `.super` references

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

---

## Migration Guide: Method Prefix Removal

### Breaking Changes in Unreleased Version

#### Configuration Changes

**Before:**
```zig
pub const CodegenConfig = struct {
    method_prefix: []const u8 = "call_",
    getter_prefix: []const u8 = "get_",
    setter_prefix: []const u8 = "set_",
};
```

**After:**
```zig
pub const CodegenConfig = struct {
    getter_prefix: []const u8 = "get_",
    setter_prefix: []const u8 = "set_",
};
```

#### Usage Changes

**Before:**
```zig
employee.call_greet();  // Inherited method with prefix
employee.work();        // Own method
user.get_email();       // Property getter
```

**After:**
```zig
employee.greet();    // Inherited method (no prefix)
employee.work();     // Own method
user.get_email();    // Property getter (still has prefix)
```

#### CLI Changes

The `--method-prefix` flag is deprecated:

**Before:**
```bash
zoop-codegen --source-dir src --output-dir gen \
    --method-prefix "call_" \
    --getter-prefix "get_" \
    --setter-prefix "set_"
```

**After:**
```bash
zoop-codegen --source-dir src --output-dir gen \
    --getter-prefix "get_" \
    --setter-prefix "set_"
```

#### Migration Steps

1. Remove `--method-prefix` from your build.zig
2. Update method calls: `obj.call_method()` → `obj.method()`
3. Property accessors remain unchanged

---

[Unreleased]: https://github.com/yourname/zoop/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/yourname/zoop/releases/tag/v0.1.0
