# Consumer Usage Guide

Complete integration guide for using Zoop in your Zig projects.

---

## Table of Contents

- [Installation](#installation)
- [Integration Patterns](#integration-patterns)
  - [Pattern A: Automatic Build-Time Generation](#pattern-a-automatic-build-time-generation)
  - [Pattern B: Manual Generation (WebIDL/FFI)](#pattern-b-manual-generation-webidlffi)
- [Writing Classes](#writing-classes)
- [Configuration](#configuration)
- [Advanced Features](#advanced-features)
- [Troubleshooting](#troubleshooting)

---

## Installation

### 1. Add Dependency

**build.zig.zon:**
```zig
.{
    .name = "myproject",
    .version = "0.1.0",
    .dependencies = .{
        .zoop = .{
            .url = "https://github.com/yourname/zoop/archive/v0.2.0-beta.tar.gz",
            .hash = "1220...",  // zig build will calculate this for you
        },
    },
}
```

First run will prompt you for the correct hash:

```bash
$ zig build
error: hash mismatch for package 'zoop':
  expected: 1220abc...
  found:    1220def...

# Copy the "found" hash to build.zig.zon
```

### 2. Choose Your Integration Pattern

Zoop supports two workflows:

| Pattern | When to Use | Code Location |
|---------|-------------|---------------|
| **A: Automatic** | Normal development, classes part of your codebase | Generated code in cache, regenerates every build |
| **B: Manual** | WebIDL, FFI, hand-tuned code you'll edit | Generated code in `src/`, manual merge workflow |

See below for setup instructions for each pattern.

---

## Integration Patterns

### Pattern A: Automatic Build-Time Generation

**Best for:** Most projects where classes are part of your normal codebase.

**How it works:**
1. Write classes in `src/` with `zoop.class()`
2. On every `zig build`, zoop-codegen runs and outputs to `.zig-cache/`
3. Compiler builds from generated code
4. Changes to source automatically trigger regeneration

**build.zig:**

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Get Zoop dependency
    const zoop_dep = b.dependency("zoop", .{
        .target = target,
        .optimize = optimize,
    });

    // 2. Set up code generation
    const codegen_exe = zoop_dep.artifact("zoop-codegen");
    const gen_cmd = b.addRunArtifact(codegen_exe);
    gen_cmd.addArgs(&.{
        "--source-dir", "src",
        "--output-dir", ".zig-cache/zoop-generated",
        "--getter-prefix", "get_",
        "--setter-prefix", "set_",
    });

    // 3. Build from generated code
    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_source_file = b.path(".zig-cache/zoop-generated/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 4. Add Zoop module (so generated code can import it)
    exe.root_module.addImport("zoop", zoop_dep.module("zoop"));

    // 5. Ensure codegen runs before compilation
    exe.step.dependOn(&gen_cmd.step);

    b.installArtifact(exe);

    // Optional: run step
    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
```

**Usage:**
```bash
zig build        # Regenerates and builds
zig build run    # Regenerates, builds, runs
```

**.gitignore:**
```gitignore
zig-cache/
zig-out/
.zig-cache/
```

---

### Pattern B: Manual Generation (WebIDL/FFI)

**Best for:** Generating from external specs (WebIDL, protocol definitions) where you'll hand-edit the output.

**How it works:**
1. External tool generates `.zig` files with `zoop.class()` markers to `.codegen-input/`
2. Run `zig build gen` manually when you want to update
3. Zoop outputs to `src-generated/` for review
4. You manually merge changes into `src/`
5. Normal builds use `src/` (no codegen runs)

**build.zig:**

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zoop_dep = b.dependency("zoop", .{
        .target = target,
        .optimize = optimize,
    });

    // 1. Manual codegen step (opt-in)
    const codegen_exe = zoop_dep.artifact("zoop-codegen");
    const gen_cmd = b.addRunArtifact(codegen_exe);
    gen_cmd.addArgs(&.{
        "--source-dir", ".codegen-input",      // Intermediate files
        "--output-dir", "src-generated",        // Review here
        "                  // Often cleaner for FFI
        "--getter-prefix", "get_",
        "--setter-prefix", "set_",
    });

    // Create manual generation step
    const gen_step = b.step("gen", "Generate classes (manual - review before merging)");
    gen_step.dependOn(&gen_cmd.step);

    // 2. Build from manually-maintained src/
    const lib = b.addStaticLibrary(.{
        .name = "mylib",
        .root_source_file = b.path("src/main.zig"),  // Your edited code
        .target = target,
        .optimize = optimize,
    });

    lib.root_module.addImport("zoop", zoop_dep.module("zoop"));
    
    // Note: NO lib.step.dependOn(&gen_cmd.step) - manual workflow!
    
    b.installArtifact(lib);
}
```

**Workflow:**

```bash
# 1. Update external spec (e.g., WebIDL)
zig build parse-webidl  # Your custom step that generates to .codegen-input/

# 2. Generate Zoop classes (only when you want to update)
zig build gen

# 3. Review changes
git diff --no-index src/ src-generated/
# Or use your editor:
code --diff src/Element.zig src-generated/Element.zig

# 4. Manually merge updates
# For new classes:
cp src-generated/HTMLElement.zig src/

# For updated classes:
# Hand-edit src/Element.zig with relevant changes from src-generated/

# 5. Clean up temporary files
rm -rf src-generated/

# 6. Normal build (no codegen runs)
zig build

# 7. Commit your manual edits
git add src/
git commit -m "Update DOM bindings from WebIDL spec"
```

**.gitignore:**
```gitignore
zig-cache/
zig-out/
.codegen-input/    # Intermediate generated files
src-generated/     # Temporary diff output
```

**Directory structure:**
```
myproject/
├── build.zig
├── build.zig.zon
├── specs/
│   └── dom.webidl              # External spec
├── .codegen-input/             # Step 1: WebIDL → Zoop markers (gitignored)
│   ├── Element.zig
│   └── Node.zig
├── src-generated/              # Step 2: Zoop output for review (gitignored)
│   ├── Element.zig
│   └── Node.zig
└── src/                        # Step 3: Your edited versions (committed)
    ├── main.zig
    ├── Element.zig             # Hand-tuned, includes your additions
    └── Node.zig
```

---

## Writing Classes

### Basic Class

```zig
const zoop = @import("zoop");

pub const Animal = zoop.class(struct {
    name: []const u8,
    age: u8,
    
    pub fn speak(self: *Animal) void {
        std.debug.print("{s} says hello\n", .{self.name});
    }
});
```

### Inheritance

```zig
pub const Dog = zoop.class(struct {
    pub const extends = Animal,  // Inheritance declaration
    
    breed: []const u8,
    
    pub fn speak(self: *Dog) void {  // Override parent method
        std.debug.print("{s} barks!\n", .{self.name});
    }
    
    pub fn fetch(self: *Dog) void {  // New method
        std.debug.print("{s} fetches\n", .{self.name});
    }
});
```

**Usage:**
```zig
var dog = Dog{
    .name = "Max",        // From Animal (flattened)
    .age = 3,             // From Animal (flattened)
    .breed = "Golden Retriever",
};

dog.speak();                  // Dog's override: "Max barks!"
dog.fetch();                  // Dog's method
dog.speak();             // ERROR: Can't call overridden parent method
std.debug.print("{}\n", .{dog.age});  // Direct field access: 3
```

### Properties

```zig
pub const User = zoop.class(struct {
    pub const properties = .{
        .email = .{
            .type = []const u8,
            .access = .read_write,  // get + set
        },
        .id = .{
            .type = u64,
            .access = .read_only,   // get only
        },
    };
    
    name: []const u8,  // Regular field (public)
});
```

**Generated:**
```zig
pub const User = struct {
    email: []const u8,
    id: u64,
    name: []const u8,
    
    pub inline fn get_email(self: *const User) []const u8 { return self.email; }
    pub inline fn set_email(self: *User, value: []const u8) void { self.email = value; }
    pub inline fn get_id(self: *const User) u64 { return self.id; }
};
```

**Usage:**
```zig
var user = User{
    .email = "alice@example.com",
    .id = 42,
    .name = "Alice",
};

user.set_email("newemail@example.com");
const email = user.get_email();
const id = user.get_id();
// user.set_id(99);  // ERROR: read_only property
```

### Cross-File Inheritance

**src/base/entity.zig:**
```zig
const zoop = @import("zoop");

pub const Entity = zoop.class(struct {
    id: u64,
    
    pub fn save(self: *Entity) !void {
        // Database logic...
    }
});
```

**src/game/player.zig:**
```zig
const zoop = @import("zoop");
const base = @import("../base/entity.zig");

pub const Player = zoop.class(struct {
    pub const extends = base.Entity,
    
    name: []const u8,
    health: i32,
});
```

**Usage:**
```zig
var player = Player{
    .id = 1,         // From Entity (flattened)
    .name = "Hero",
    .health = 100,
};

try player.save();  // Inherited from Entity (copied method)
```

### Multi-Level Inheritance

```zig
const Entity = zoop.class(struct { id: u64 });

const Character = zoop.class(struct {
    pub const extends = Entity,
    name: []const u8,
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

// Direct field access:
std.debug.print("ID: {}\n", .{player.id});  // 1
```

### Mixins

Compose multiple behaviors without creating deep inheritance hierarchies:

```zig
const zoop = @import("zoop");

// Define reusable mixins
const Timestamped = zoop.class(struct {
    created_at: i64,
    updated_at: i64,
    
    pub fn updateTimestamp(self: *Timestamped) void {
        self.updated_at = std.time.timestamp();
    }
    
    pub fn getAge(self: *const Timestamped) i64 {
        return std.time.timestamp() - self.created_at;
    }
});

const Serializable = zoop.class(struct {
    pub fn toJson(self: *const Serializable, allocator: std.mem.Allocator) ![]const u8 {
        // Your serialization implementation
        return try allocator.dupe(u8, "{}");
    }
});

// Use mixins with or without parent
const User = zoop.class(struct {
    pub const extends = Entity;  // Optional parent
    pub const mixins = .{ Timestamped, Serializable };  // Multiple mixins
    
    name: []const u8,
    email: []const u8,
});

// Usage:
var user = User{
    .id = 1,               // From Entity (flattened)
    .created_at = std.time.timestamp(),  // From Timestamped (flattened)
    .updated_at = std.time.timestamp(),  // From Timestamped (flattened)
    .name = "Alice",
    .email = "alice@example.com",
};

// Mixin methods available directly:
user.updateTimestamp();
const age = user.getAge();
const json = try user.toJson(allocator);

// Parent methods work (copied):
user.save();
```

**How it works:**
- **Parent and mixin fields** are both flattened directly into the child class
- **Parent and mixin methods** are both copied with type names rewritten
  - Mixin: `*Timestamped` → `*User`
  - Parent: `*Entity` → `*User`
- Child methods override mixin/parent methods (no duplication)
- Multiple mixins can be applied: `pub const mixins = .{ A, B, C };`
- **Zero overhead**: No casting, no indirection, just pure method copying

---

## Configuration

### Directory Options

```zig
gen_cmd.addArgs(&.{
    "--source-dir", "src",                       // Input: your source code
    "--output-dir", ".zig-cache/zoop-generated", // Output: generated code
});
```

**Common patterns:**

| Pattern | Source Dir | Output Dir | Use Case |
|---------|-----------|------------|----------|
| Standard | `src` | `.zig-cache/zoop-generated` | Normal development |
| Separate | `src` | `src_generated` | Review generated code |
| Manual | `.codegen-input` | `src-generated` | WebIDL/FFI workflow |

### Prefix Options

Control method naming:

```zig
gen_cmd.addArgs(&.{
    "   // inherited_method → call_inherited_method
    "--getter-prefix", "get_",    // property → get_property
    "--setter-prefix", "set_",    // property → set_property
});
```

**Examples:**

```zig
// Default (call_, get_, set_)
employee.greet();
user.get_email();
user.set_email("new@example.com");

// No prefixes ("", "", "")
employee.greet();
user.email();
user.email("new@example.com");

// Custom (invoke_, read_, write_)
employee.invoke_greet();
user.read_email();
user.write_email("new@example.com");
```

**Recommendation:** Use prefixes for clarity, especially in large codebases. Empty prefixes can cause naming conflicts.

---

## Advanced Features

### Init/Deinit Inheritance

Parent constructors/destructors work automatically:

```zig
const Parent = zoop.class(struct {
    allocator: Allocator,
    data: []u8,
    
    pub fn init(allocator: Allocator, size: usize) !Parent {
        return .{
            .allocator = allocator,
            .data = try allocator.alloc(u8, size),
        };
    }
    
    pub fn deinit(self: *Parent) void {
        self.allocator.free(self.data);
    }
});

const Child = zoop.class(struct {
    pub const extends = Parent,
    extra: []u8,
    
    pub fn init(allocator: Allocator) !Child {
        return .{
            .allocator = allocator,   // From Parent (flattened)
            .buffer = try allocator.alloc(u8, 1024),  // From Parent (flattened)
            .extra = try allocator.alloc(u8, 512),
        };
    }
    
    pub fn deinit(self: *Child) void {
        self.allocator.free(self.extra);
        self.allocator.free(self.buffer);
    }
});
```

With flattened fields, you access parent fields directly (no `.super`).

### Override Detection

When a child overrides a parent method, Zoop doesn't generate a wrapper:

```zig
const Animal = zoop.class(struct {
    pub fn speak(self: *Animal) void { /* ... */ }
});

const Dog = zoop.class(struct {
    pub const extends = Animal,
    
    pub fn speak(self: *Dog) void {  // Override
        // Custom implementation
    }
});

// Generated code does NOT include call_speak()
// dog.speak() calls Dog.speak() directly
```

### Helper Function (Alternative API)

For cleaner build.zig integration, use the helper:

```zig
const zoop = @import("zoop");

// Instead of manual addArgs:
const gen_cmd = zoop.createCodegenStep(b, codegen_exe, .{
    .source_dir = "src",
    .output_dir = ".zig-cache/zoop-generated",
    
    .getter_prefix = "get_",
    .setter_prefix = "set_",
});
```

---

## Troubleshooting

### Error: "zoop-codegen not found"

**Cause:** Dependency not fetched yet.

**Fix:** Just run `zig build` - Zig auto-fetches dependencies.

### Error: "no such file src_generated/main.zig"

**Cause:** Code generation hasn't run.

**Checklist:**
1. Is `exe.step.dependOn(&gen_cmd.step)` present?
2. Does `--output-dir` match `root_source_file`?
3. Does `src/main.zig` have any `zoop.class()` calls?

**Debug:**
```bash
# Run codegen manually to see errors:
zig build-exe build.zig
./build codegen  # Or whatever your codegen step is named
```

### Generated code not updating

**Cause:** Stale cache.

**Fix:**
```bash
rm -rf zig-cache .zig-cache src_generated
zig build
```

### Type mismatch errors

**Common mistakes:**

```zig
// ❌ Wrong: extends as a field
pub const Child = zoop.class(struct {
    extends: Parent,  // ERROR
});

// ✅ Correct: extends as a const
pub const Child = zoop.class(struct {
    pub const extends = Parent,
});

// ❌ Wrong: flat initialization
var child = Child{
    .name = "value",  // ERROR: no such field (if you didn't use zoop.class)
};

// ✅ Correct: fields are flattened with zoop
var child = Child{
    .name = "value",  // From Parent (flattened)
};
```

### Import resolution issues

**Problem:** Zoop can't find parent class across files.

**Check:**
1. Parent class is `pub const`
2. Import path is correct: `@import("../path/to/file.zig")`
3. Both files are in `--source-dir` tree

**Example:**
```zig
// src/game/player.zig
const base = @import("../base/entity.zig");  // ✅ Relative path

pub const Player = zoop.class(struct {
    pub const extends = base.Entity,  // ✅ Fully qualified
});
```

### Path traversal security error

**Error:** `Source directory contains '..' - path traversal not allowed`

**Cause:** Using `..` in `--source-dir` or `--output-dir`.

**Fix:** Use absolute paths or paths without `..`:
```bash
# ❌ Not allowed
--source-dir ../other-project/src

# ✅ Allowed
--source-dir /absolute/path/to/other-project/src

# ✅ Best (relative to project root)
--source-dir src
```

---

## Examples

Complete working examples:

- **[test_consumer/](test_consumer/)** - Standard automatic generation workflow
- **[examples/cross_file/](examples/cross_file/)** - Cross-file inheritance example
- **[tests/](tests/)** - Comprehensive test suite with edge cases

---

## Next Steps

- **[README.md](README.md)** - Overview, quick start, features
- **[API_REFERENCE.md](API_REFERENCE.md)** - Detailed API documentation
- **[IMPLEMENTATION.md](IMPLEMENTATION.md)** - How Zoop works internally

---

## Getting Help

- **GitHub Issues:** Report bugs or request features
- **GitHub Discussions:** Ask questions, share use cases
- **Check existing tests:** `tests/` has examples of every feature
