# Zoop - Zero-Cost OOP for Zig

> ⚠️ **BETA SOFTWARE**: Core features working! Inheritance, properties, and cross-file support implemented. See [Project Status](#project-status) below.

Automatic code generation for object-oriented programming in Zig with configurable method prefixes and zero runtime overhead.

## Features

- ✅ **Automatic code generation** - Via `zoop-codegen` tool
- ✅ **Embedded parent structs** - Type-safe composition pattern
- ✅ **Cross-file inheritance** - Classes can inherit across files
- ✅ **Properties** - Automatic getters/setters (read_only / read_write)
- ✅ **Configurable prefixes** - `call_`, `get_`, `set_` or custom
- ✅ **Override detection** - No duplicate methods
- ✅ **Multi-level inheritance** - Chains through `super` fields
- ✅ **Init/deinit inheritance** - Automatic parent method adaptation
- ✅ **Zero runtime cost** - Everything inlined
- ✅ **Type safe** - Compile-time guarantees
- ✅ **Zig 0.15+** - Works with modern Zig
- ✅ **Security hardened** - Path traversal protection, memory leak fixes

## Quick Start

### 1. Add to your project

**build.zig.zon**:
```zig
.{
    .name = .myproject,
    .version = "0.1.0",
    .dependencies = .{
        .zoop = .{
            .url = "https://github.com/yourname/zoop/archive/main.tar.gz",
            .hash = "...",
        },
    },
}
```

**build.zig**:
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add zoop module
    const zoop_dep = b.dependency("zoop", .{
        .target = target,
        .optimize = optimize,
    });
    const zoop_module = zoop_dep.module("zoop");
    exe.root_module.addImport("zoop", zoop_module);

    // Add code generation step
    const codegen_exe = zoop_dep.artifact("zoop-codegen");
    const gen_cmd = b.addRunArtifact(codegen_exe);
    gen_cmd.addArgs(&.{
        "--source-dir", "src",
        "--output-dir", ".zig-cache/zoop-generated",
        "--method-prefix", "call_",
        "--getter-prefix", "get_",
        "--setter-prefix", "set_",
    });
    exe.step.dependOn(&gen_cmd.step);

    b.installArtifact(exe);
}
```

### 2. Build your project

```bash
# Just build - code generation runs automatically
zig build
```

### 3. Write classes

**Source code** (`src/main.zig`):
```zig
const std = @import("std");
const zoop = @import("zoop");

const Person = zoop.class(struct {
    name: []const u8,
    age: u32,
    
    pub fn greet(self: *Person) void {
        std.debug.print("Hello, I'm {s}\n", .{self.name});
    }
    
    pub fn getAge(self: *Person) u32 {
        return self.age;
    }
});

const Employee = zoop.class(struct {
    pub const extends = Person,
    
    employee_id: u32,
    
    pub fn work(self: *Employee) void {
        std.debug.print("{s} is working\n", .{self.super.name});
    }
});

pub fn main() void {
    var employee = Employee{
        .super = Person{
            .name = "Alice",
            .age = 30,
        },
        .employee_id = 1234,
    };
    
    employee.call_greet();   // ✅ Calls parent method via self.super
    employee.work();          // ✅ Own method
    
    const age = employee.call_getAge();  // ✅ Returns 30
    std.debug.print("Age: {}\n", .{age});
}
```

**Generated code** (automatic):
```zig
const Person = struct {
    name: []const u8,
    age: u32,
    
    pub fn greet(self: *Person) void {
        std.debug.print("Hello, I'm {s}\n", .{self.name});
    }
    
    pub fn getAge(self: *Person) u32 {
        return self.age;
    }
};

const Employee = struct {
    super: Person,  // ✅ Embedded parent
    
    employee_id: u32,
    
    pub fn work(self: *Employee) void {
        std.debug.print("{s} is working\n", .{self.super.name});
    }
    
    // ✅ Generated method wrappers
    pub inline fn call_greet(self: *Employee) void {
        self.super.greet();
    }
    
    pub inline fn call_getAge(self: *Employee) u32 {
        return self.super.getAge();
    }
};
```

## How It Works

1. **You write** `zoop.class(struct { extends: Parent, ... })`
2. **Codegen runs** before every build via `zoop.build()`
3. **Generates**:
   - `super: ParentType` field (embedded parent)
   - Wrapper methods like `call_parentMethod()`
   - Chains through `self.super.method()` calls
4. **You use**: `child.super.parent_field` and `child.call_parent_method()`

### Multi-Level Inheritance

```zig
// Source
const Vehicle = zoop.class(struct {
    brand: []const u8,
    pub fn start(self: *Vehicle) void { ... }
});

const Car = zoop.class(struct {
    pub const extends = Vehicle,
    num_doors: u8,
    pub fn honk(self: *Car) void { ... }
});

const ElectricCar = zoop.class(struct {
    pub const extends = Car,
    battery_capacity: f32,
});

// Usage
var tesla = ElectricCar{
    .super = Car{
        .super = Vehicle{
            .brand = "Tesla",
        },
        .num_doors = 4,
    },
    .battery_capacity = 100.0,
};

tesla.call_start();  // ✅ Chains: self.super.call_start() -> self.super.super.start()
tesla.call_honk();   // ✅ Chains: self.super.honk()
```

### Properties

```zig
const User = zoop.class(struct {
    pub const properties = .{
        .email = .{
            .type = []const u8,
            .access = .read_write,
        },
        .id = .{
            .type = u32,
            .access = .read_only,
        },
    };
    
    name: []const u8,
});

// Generated code (automatic):
const User = struct {
    _email: []const u8,  // Backing field
    _id: u32,            // Backing field
    name: []const u8,
    
    pub inline fn get_email(self: *User) []const u8 {
        return self._email;
    }
    pub inline fn set_email(self: *User, value: []const u8) void {
        self._email = value;
    }
    pub inline fn get_id(self: *User) u32 {
        return self._id;
    }
    // No setter for read_only property
};

// Usage
var user = User{
    ._email = "alice@example.com",
    ._id = 123,
    .name = "Alice",
};

user.set_email("new@example.com");
const email = user.get_email();  // "new@example.com"
const id = user.get_id();        // 123
```

## Configuration

### In build.zig

Configure code generation by passing arguments to `zoop-codegen`:

```zig
const gen_cmd = b.addRunArtifact(codegen_exe);
gen_cmd.addArgs(&.{
    "--source-dir", "src",              // Where to find source files
    "--output-dir", ".zig-cache/zoop-generated",  // Where to write generated code
    "--method-prefix", "call_",         // Prefix for inherited methods
    "--getter-prefix", "get_",          // Prefix for property getters
    "--setter-prefix", "set_",          // Prefix for property setters
});
```

### Custom Prefixes

```zig
// No prefixes
gen_cmd.addArgs(&.{
    "--method-prefix", "",
    "--getter-prefix", "",
    "--setter-prefix", "",
});

// Custom prefixes
gen_cmd.addArgs(&.{
    "--method-prefix", "invoke_",
    "--getter-prefix", "read_",
    "--setter-prefix", "write_",
});
```

## Documentation

- [**Implementation Architecture**](IMPLEMENTATION.md) - **START HERE** - How Zoop actually works
- [**Consumer Usage Guide**](CONSUMER_USAGE.md) - Complete integration guide for your project
- [**API Reference**](API_REFERENCE.md) - Complete API documentation
- [**Test Consumer Example**](test_consumer/) - Working example project showing integration

## Project Status

### ✅ Working Now (v0.2.0-beta)

- ✅ **Cross-file inheritance** - Classes can inherit across files with import resolution
- ✅ **Properties** with getters/setters (read_only / read_write)
- ✅ **Init/deinit inheritance** - Automatic field access rewriting for inherited methods
- ✅ Basic inheritance with embedded `super` field
- ✅ Multi-level inheritance (3+ levels, unlimited depth)
- ✅ Method forwarding with configurable prefixes
- ✅ Override detection (skips generating wrappers for overridden methods)
- ✅ Circular inheritance detection (cross-file aware)
- ✅ Build system integration via `zoop-codegen` artifact
- ✅ Type-safe composition pattern
- ✅ **Security hardened** - Path traversal protection, memory leak fixes

### ⚠️ Not Yet Implemented

- ❌ **Mixins** - Completely missing
- ❌ **Field alignment optimization** - Fields not sorted by alignment
- ❌ **Static method detection** - Static methods get wrappers (but harmless)

### 📋 Architecture Notes

**Why embedded structs?** The original plan used `@ptrCast` for "flat" field access, but Zig's field reordering makes this unsafe. The current implementation uses **embedded parent structs** (`super` field), which is:
- ✅ Type-safe (no memory layout assumptions)
- ✅ Idiomatic Zig (composition over inheritance)
- ✅ Clear and explicit (`self.super` shows relationship)
- ✅ Works with Zig's optimizations

## Limitations

### Must Use `super` Field

```zig
// ❌ Wrong - fields are not flattened
var employee = Employee{
    .name = "Alice",
    .age = 30,
};

// ✅ Correct - must initialize through super
var employee = Employee{
    .super = Person{
        .name = "Alice",
        .age = 30,
    },
};
```

### Must Use Prefixed Methods

```zig
// ❌ Wrong - parent methods not directly available
employee.greet();

// ✅ Correct - use configured prefix
employee.call_greet();
```

### Cross-File Inheritance (NEW!)

Cross-file inheritance is now supported! Import parent classes and use them:

```zig
// file: src/base/entity.zig
const zoop = @import("zoop");
pub const Entity = zoop.class(struct {
    id: u64,
});

// file: src/models/player.zig  
const zoop = @import("zoop");
const base = @import("../base/entity.zig");

pub const Player = zoop.class(struct {
    pub const extends = base.Entity,
    name: []const u8,
});
```

The code generator automatically:
- Parses import statements
- Resolves relative paths
- Finds parent classes across files
- Generates proper cross-file method wrappers

## Security

Zoop includes several security protections:

### Path Traversal Protection

The `zoop-codegen` tool validates all file paths to prevent path traversal attacks:
- ❌ Blocks `..` in file paths
- ❌ Blocks absolute paths starting with `/` or drive letters
- ❌ Warns when using absolute paths
- ✅ Only processes files within specified directories

### Memory Safety

- ✅ No memory leaks on error paths (uses `errdefer`)
- ✅ Proper cleanup of all allocations
- ✅ Safe bounds checking throughout
- ✅ No unsafe pointer casts

### Safe Usage

```bash
# ✅ Safe - relative paths
./zoop-codegen --source-dir src --output-dir generated

# ❌ Blocked - path traversal
./zoop-codegen --source-dir ../../../etc --output-dir out
# Error: Source directory contains '..' - path traversal not allowed

# ⚠️ Warns but allows - absolute path
./zoop-codegen --source-dir /tmp/myproject --output-dir /tmp/out
# Warning: Using absolute path for source directory: /tmp/myproject
```

## Building Zoop

```bash
# Clone the repository
git clone https://github.com/yourname/zoop
cd zoop

# Build the code generator
zig build codegen

# Run tests
zig build test

# Build example
zig build run
```

## Troubleshooting

### Error: `zoop-codegen` not found

Build the code generator first:
```bash
zig build codegen
```

### Generated code not updating

Clear cache and rebuild:
```bash
rm -rf zig-cache .zig-cache
zig build codegen
zig build
```

### Type mismatch errors

Make sure you're initializing the `super` field correctly:
```zig
.super = ParentType{ ... }
```

## Contributing

Contributions welcome! Priority areas:
1. Implement mixin system
2. Add field alignment optimization
3. Improve static method detection
4. Better error messages and diagnostics
5. Documentation improvements

See [GitHub Issues](https://github.com/yourname/zoop/issues) for detailed task list.

## Changelog

### v0.2.0-beta (Current)
- ✅ **Cross-file inheritance** implemented
- ✅ **Properties** with getters/setters working
- ✅ **Init/deinit inheritance** with automatic field access rewriting
- ✅ **Security hardening**: Path traversal protection, memory leak fixes
- 🔧 Removed broken build integration helper
- 🔧 Fixed property field duplication bug
- 🔧 All 36 tests passing

### v0.1.0-alpha
- ✅ Basic single-file inheritance
- ✅ Method forwarding
- ✅ Configurable prefixes

## License

MIT License - See [LICENSE](LICENSE) for details.

## Acknowledgments

- Inspired by the need for ergonomic OOP patterns in Zig
- Built on Zig's powerful build system and codegen capabilities
- Thanks to the Zig community for feedback and support
