# Zoop

**Zero-cost object-oriented programming for Zig through compile-time code generation.**

[![Zig](https://img.shields.io/badge/zig-0.15+-orange.svg)](https://ziglang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Zoop brings familiar OOP patterns to Zig while maintaining zero runtime overhead and compile-time type safety. Write classes with inheritance and properties using natural syntax, then let Zoop generate optimized code that compiles away to nothing.

```zig
const Employee = zoop.class(struct {
    pub const extends = Person,
    employee_id: u32,
    
    pub fn work(self: *Employee) void {
        std.debug.print("{s} is working\n", .{self.name});
    }
});

employee.greet();  // Inherited from Person - zero overhead
```

> **Status:** Beta - Core features complete and tested. Production-ready for real projects.

---

## Table of Contents

- [Why Zoop?](#why-zoop)
- [Features](#features)
- [Quick Start](#quick-start)
- [Core Concepts](#core-concepts)
- [Advanced Usage](#advanced-usage)
- [Integration Patterns](#integration-patterns)
- [Performance](#performance)
- [Documentation](#documentation)
- [Contributing](#contributing)

---

## Why Zoop?

**The Problem:** Zig doesn't have built-in inheritance or OOP patterns. When modeling domains with natural hierarchies (UI components, game entities, DOM nodes), you end up with verbose boilerplate and manual delegation.

**The Solution:** Zoop generates clean inheritance code at build time. You get:

- 🎯 **Natural syntax** - `extends`, properties, method inheritance
- ⚡ **Zero cost** - Everything inlines to direct field access
- 🔒 **Type safe** - Full Zig compiler checks, no runtime surprises  
- 🏗️ **Build-time only** - Generated code is normal Zig, debug normally
- 🔧 **Configurable** - Control prefixes, directories, generation strategy

**Perfect for:** Game engines, UI frameworks, DOM libraries, protocol implementations, or any domain with clear type hierarchies.

---

## Features

### Core

- ✅ **Single & multi-level inheritance** - Unlimited depth with flattened parent fields
- ✅ **Cross-file inheritance** - Import and extend classes from any module
- ✅ **Mixins** - Multiple inheritance via composition with field and method flattening
- ✅ **Properties** - Auto-generated getters/setters with `read_only`/`read_write` access
- ✅ **Method copying** - Inherited methods copied directly without prefixes
- ✅ **Override detection** - No duplicate method generation
- ✅ **Init/deinit inheritance** - Parent constructors/destructors automatically adapted

### Build & Tooling

- ✅ **Build-time codegen** - `zoop-codegen` executable integrates with Zig build
- ✅ **Configurable output** - Control source/output directories, property accessor prefixes
- ✅ **Manual mode** - Optional: generate once, edit manually (perfect for WebIDL/FFI)
- ✅ **Circular dependency detection** - Catches inheritance cycles early

### Safety & Performance

- ✅ **Zero runtime overhead** - All calls inline to direct field access
- ✅ **Path traversal protection** - Validates file paths during generation
- ✅ **Memory safe** - No leaks, proper cleanup on all error paths
- ✅ **Type safe** - Leverages Zig's compile-time type system

---

## Quick Start

### Installation

Add to your `build.zig.zon`:

```zig
.{
    .name = "myproject",
    .version = "0.1.0",
    .dependencies = .{
        .zoop = .{
            .url = "https://github.com/yourname/zoop/archive/v0.2.0-beta.tar.gz",
            .hash = "1220...",  // zig build will calculate this
        },
    },
}
```

### Build Integration

**Option A: Automatic (standard workflow)**

Generated code stays in cache, regenerates on every build:

```zig
// build.zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get zoop dependency
    const zoop_dep = b.dependency("zoop", .{
        .target = target,
        .optimize = optimize,
    });

    // Run code generation (automatic)
    const codegen_exe = zoop_dep.artifact("zoop-codegen");
    const gen_cmd = b.addRunArtifact(codegen_exe);
    gen_cmd.addArgs(&.{
        "--source-dir", "src",
        "--output-dir", ".zig-cache/zoop-generated",
        "--getter-prefix", "get_",
        "--setter-prefix", "set_",
    });

    // Build your app from generated code
    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_source_file = b.path(".zig-cache/zoop-generated/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    exe.root_module.addImport("zoop", zoop_dep.module("zoop"));
    exe.step.dependOn(&gen_cmd.step);  // Generate before building
    
    b.installArtifact(exe);
}
```

**Option B: Manual (for WebIDL, FFI, hand-tuned code)**

Generate once, commit to `src/`, edit manually:

```zig
// Create opt-in generation step (doesn't run on normal builds)
const gen_step = b.step("gen", "Generate classes (manual - review diffs before merging)");
gen_cmd.addArgs(&.{
    "--source-dir", ".codegen-input",
    "--output-dir", "src-generated",  // Review here, then copy to src/
});
gen_step.dependOn(&gen_cmd.step);

// Your exe builds from manually-maintained src/
const exe = b.addExecutable(.{
    .root_source_file = b.path("src/main.zig"),  // Your edited code
    // ...
});
// Note: No exe.step.dependOn(&gen_cmd.step) - manual workflow
```

**Usage:**
```bash
# Option A: Automatic regeneration
zig build

# Option B: Manual workflow
zig build gen              # Generate to src-generated/
diff -r src src-generated  # Review changes
# Manually merge, then:
zig build                  # Normal build
```

### Your First Class

**Source** (`src/main.zig`):

```zig
const std = @import("std");
const zoop = @import("zoop");

pub const Animal = zoop.class(struct {
    name: []const u8,
    age: u8,
    
    pub fn init(name: []const u8, age: u8) Animal {
        return .{ .name = name, .age = age };
    }
    
    pub fn speak(self: *Animal) void {
        std.debug.print("{s} makes a sound\n", .{self.name});
    }
});

pub const Dog = zoop.class(struct {
    pub const extends = Animal,  // Inheritance
    
    breed: []const u8,
    
    pub fn init(name: []const u8, age: u8, breed: []const u8) Dog {
        return .{
            .name = name,
            .age = age,
            .breed = breed,
        };
    }
    
    pub fn speak(self: *Dog) void {  // Override
        std.debug.print("{s} barks!\n", .{self.name});
    }
    
    pub fn fetch(self: *Dog) void {
        std.debug.print("{s} the {s} fetches\n", .{ self.name, self.breed });
    }
});

pub fn main() !void {
    var dog = Dog.init("Max", 3, "Golden Retriever");
    
    dog.speak();        // "Max barks!"
    dog.fetch();        // "Max the Golden Retriever fetches"
}
```

**Build:**
```bash
zig build run
# Output:
# Max barks!
# Max the Golden Retriever fetches
```

---

## Core Concepts

### Inheritance via Flattened Fields

Zoop uses **flattened parent fields** for natural property access:

```zig
// You write:
const Employee = zoop.class(struct {
    pub const extends = Person,
    employee_id: u32,
});

// Zoop generates:
const Employee = struct {
    name: []const u8,   // From Person (flattened)
    age: u32,           // From Person (flattened)
    employee_id: u32,   // Own field
    
    // Auto-generated methods (copied from parent with type rewriting)...
};
```

**Benefits:**
- ✅ Direct field access: `employee.name` instead of `employee.super.name`
- ✅ Natural initialization: `.{ .name = "Alice", .age = 30, .employee_id = 123 }`
- ✅ Zero overhead: Parent methods are copied, not delegated
- ✅ Works like traditional OOP languages

### Properties

Automatic getter/setter generation with access control:

```zig
const User = zoop.class(struct {
    pub const properties = .{
        .email = .{ .type = []const u8, .access = .read_write },
        .id = .{ .type = u64, .access = .read_only },
    };
    
    name: []const u8,  // Regular field
});

// Generated:
const User = struct {
    email: []const u8,
    id: u64,
    name: []const u8,
    
    pub inline fn get_email(self: *const User) []const u8 { return self.email; }
    pub inline fn set_email(self: *User, value: []const u8) void { self.email = value; }
    pub inline fn get_id(self: *const User) u64 { return self.id; }
    // No setter for read_only
};
```

### Method Prefixes

Inherited methods are copied directly without prefixes. Property accessors use configurable prefixes:

```zig
// Inherited methods - no prefix
employee.greet();  // Copied from Person

// Properties - default prefixes: get_, set_
user.get_email();
user.set_email("new@example.com");

// Custom property prefixes: --getter-prefix "read_" --setter-prefix "write_"
user.read_email();
user.write_email("new@example.com");

// No property prefixes: --getter-prefix "" --setter-prefix ""
user.email();
user.email("new@example.com");
```

---

## Advanced Usage

### Multi-Level Inheritance

Unlimited depth, automatic chaining:

```zig
const Entity = zoop.class(struct {
    id: u64,
    pub fn save(self: *Entity) void { /* ... */ }
});

const Character = zoop.class(struct {
    pub const extends = Entity,
    name: []const u8,
    pub fn move(self: *Character) void { /* ... */ }
});

const Player = zoop.class(struct {
    pub const extends = Character,
    username: []const u8,
});

var player = Player{
    .id = 1,           // From Entity (flattened)
    .name = "Hero",    // From Character (flattened)
    .username = "player1",
};

player.save();  // Entity.save() (copied and type-rewritten)
player.move();  // Character.move() (copied and type-rewritten)
```

### Cross-File Inheritance

Import and extend classes from anywhere:

```zig
// src/base/entity.zig
const zoop = @import("zoop");

pub const Entity = zoop.class(struct {
    id: u64,
    
    pub fn init(id: u64) Entity {
        return .{ .id = id };
    }
});

// src/game/player.zig
const zoop = @import("zoop");
const base = @import("../base/entity.zig");

pub const Player = zoop.class(struct {
    pub const extends = base.Entity,
    
    name: []const u8,
    health: i32,
});
```

### Mixins (Multiple Inheritance)

Use mixins for code reuse without creating deep hierarchies:

```zig
// Define reusable behaviors using zoop.mixin()
const Timestamped = zoop.mixin(struct {
    created_at: i64,
    updated_at: i64,
    
    pub fn updateTimestamp(self: *Timestamped) void {
        self.updated_at = std.time.timestamp();
    }
});

const Serializable = zoop.mixin(struct {
    pub fn toJson(self: *const Serializable, allocator: std.mem.Allocator) ![]const u8 {
        // Implementation...
    }
});

// Combine parent + mixins
const User = zoop.class(struct {
    pub const extends = Entity;  // Single parent
    pub const mixins = .{ Timestamped, Serializable };  // Multiple mixins
    
    name: []const u8,
    email: []const u8,
});

// Generated:
const User = struct {
    id: u64,               // From Entity (flattened!)
    created_at: i64,       // From Timestamped (flattened!)
    updated_at: i64,       // From Timestamped (flattened!)
    name: []const u8,
    email: []const u8,
    
    pub fn save(self: *User) void { ... }  // From Entity (copied)
    pub fn updateTimestamp(self: *User) void { ... }    // From Timestamped (type rewritten!)
    pub fn toJson(self: *const User, ...) ![]const u8 { ... }  // From Serializable
};

var user = User{
    .id = 1,
    .created_at = std.time.timestamp(),
    .updated_at = std.time.timestamp(),
    .name = "Alice",
    .email = "alice@example.com",
};

user.updateTimestamp();  // Mixin method
user.save();            // Parent method
```

**How mixins work:**
- Fields are **flattened** directly into the child class
- Methods are **copied** with type names rewritten (`*Timestamped` → `*User`)
- Child methods override mixin methods (no duplication)
- Works alongside parent inheritance (`extends` + `mixins`)

Zoop automatically:
- Parses all `@import()` statements
- Resolves relative paths
- Finds parent classes across files
- Generates correct cross-file wrappers

### Init/Deinit Inheritance

Parent constructors/destructors work automatically:

```zig
const Parent = zoop.class(struct {
    allocator: std.mem.Allocator,
    data: []u8,
    
    pub fn init(allocator: std.mem.Allocator) !Parent {
        return .{
            .allocator = allocator,
            .data = try allocator.alloc(u8, 1024),
        };
    }
    
    pub fn deinit(self: *Parent) void {
        self.allocator.free(self.data);
    }
});

const Child = zoop.class(struct {
    pub const extends = Parent,
    extra: []u8,
    
    pub fn init(allocator: std.mem.Allocator) !Child {
        return .{
            .allocator = allocator,  // From Parent (flattened)
            .extra = try allocator.alloc(u8, 512),
        };
    }
    
    pub fn deinit(self: *Child) void {
        self.allocator.free(self.extra);
        // Parent's deinit would be copied as call_deinit if needed
    }
});
```

With flattened fields, you can access parent fields directly in `init`/`deinit`.

---

## Integration Patterns

### Pattern 1: Standard Build-Time Generation

**Use when:** Your classes are part of your normal codebase.

```zig
gen_cmd.addArgs(&.{ "--source-dir", "src", "--output-dir", ".zig-cache/zoop-generated" });
exe.root_source_file = b.path(".zig-cache/zoop-generated/main.zig");
exe.step.dependOn(&gen_cmd.step);  // Auto-regenerate
```

**Workflow:** Just `zig build` - everything auto-updates.

### Pattern 2: Manual Generation for Specs (WebIDL, FFI, etc.)

**Use when:** Generating from external specs, hand-tuning generated code.

```zig
const gen_step = b.step("gen-dom", "Generate DOM from WebIDL");
gen_cmd.addArgs(&.{ "--source-dir", ".webidl-gen", "--output-dir", "src-generated" });
gen_step.dependOn(&gen_cmd.step);

exe.root_source_file = b.path("src/main.zig");  // Manually maintained
// No exe.step.dependOn - manual only
```

**Workflow:**
```bash
# 1. Update WebIDL → .webidl-gen/
zig build webidl-parse

# 2. Generate Zoop classes (when you want)
zig build gen-dom

# 3. Review & merge
diff -r src/ src-generated/
# Manually integrate changes

# 4. Normal build (no codegen)
zig build
```

See [CONSUMER_USAGE.md](CONSUMER_USAGE.md) for complete examples.

---

## Performance

**Zero runtime overhead** - all generated methods inline away:

```zig
// Your code:
employee.greet();

// Generated (copied from parent):
pub fn greet(self: *Employee) void {
    std.debug.print("Hello, I'm {s}\n", .{self.name});
}

// No overhead - method is copied directly, not delegated
```

**Benchmark results** (see `tests/performance_test.zig`):

| Operation | Debug | ReleaseFast |
|-----------|-------|-------------|
| Property getter | 4 ns/op | **0 ns/op** (optimized away) |
| Method call | 3 ns/op | **0 ns/op** (inlined) |
| Object creation | 5 ns/op | 2 ns/op |
| Deep chain (5 levels) | 3 ns/op | **0 ns/op** |

Run: `zig build benchmark -Doptimize=ReleaseFast`

---

## Documentation

- **[CONSUMER_USAGE.md](CONSUMER_USAGE.md)** - Complete integration guide with all patterns
- **[API_REFERENCE.md](API_REFERENCE.md)** - Full API documentation and examples
- **[IMPLEMENTATION.md](IMPLEMENTATION.md)** - How Zoop works internally
- **[test_consumer/](test_consumer/)** - Working example project

---

## Project Status

### ✅ Complete & Tested (v0.2.0-beta)

- Cross-file inheritance with import resolution
- Properties (read_only / read_write)
- Init/deinit inheritance with field rewriting
- Multi-level inheritance (unlimited depth)
- Method forwarding with configurable prefixes
- Override detection
- Circular dependency detection
- Path traversal protection
- Memory safety (zero leaks verified)
- **36 tests passing**, extensively validated

### ⚠️ Known Limitations

- **Mixins not implemented** - Only single parent inheritance
- **No field alignment optimization** - Fields not sorted by size
- **Static methods get wrappers** - Harmless but unnecessary

### 🔮 Future Considerations

- Mixin support for multiple inheritance patterns
- Field reordering for optimal memory layout
- Static method detection to skip wrapper generation
- LSP/editor integration for better jump-to-definition

---

## Security

Zoop is designed to be safe for use in build scripts:

**Path traversal protection:**
```bash
# ❌ Blocked
zoop-codegen --source-dir ../../../etc --output-dir out
# Error: Source directory contains '..' - path traversal not allowed

# ✅ Safe
zoop-codegen --source-dir src --output-dir generated
```

**Memory safety:**
- All allocations properly freed
- `errdefer` cleanup on all error paths
- No unsafe pointer casts
- Comprehensive leak testing (see `tests/memory_benchmark.zig`)

---

## Building From Source

```bash
git clone https://github.com/yourname/zoop
cd zoop

# Build code generator
zig build codegen

# Run tests (all 36 should pass)
zig build test

# Run benchmarks
zig build benchmark -Doptimize=ReleaseFast

# Build example
zig build run
```

**Requirements:** Zig 0.15 or later

---

## Contributing

Contributions welcome! Areas where help is needed:

1. **Mixin system** - Design and implement multiple inheritance
2. **Field optimization** - Sort fields by alignment for better packing
3. **Static method detection** - Skip wrapper generation for static methods
4. **Documentation** - More examples, tutorials, use case guides
5. **Testing** - Additional edge cases, real-world usage validation

See [GitHub Issues](https://github.com/yourname/zoop/issues) for specific tasks.

**Before submitting PRs:**
- Run `zig build test` - all tests must pass
- Update relevant docs (README, API_REFERENCE, etc.)
- Add tests for new features
- Follow existing code style

---

## License

MIT License - See [LICENSE](LICENSE) for details.

Copyright (c) 2025 Brian Cardarella

---

## Acknowledgments

- Built for the Zig community's need for ergonomic domain modeling
- Inspired by classic OOP while respecting Zig's philosophy
- Thanks to all contributors and early adopters

**Questions?** Open an issue or discussion on GitHub.
