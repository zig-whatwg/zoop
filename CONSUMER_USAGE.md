# Using Zoop in Your Project

Complete guide for integrating Zoop into your Zig project.

## Quick Start

### 1. Add Zoop to `build.zig.zon`

```zig
.{
    .name = .myproject,
    .version = "0.1.0",
    .fingerprint = 0x1234567890abcdef,  // zig will generate this
    .dependencies = .{
        .zoop = .{
            .url = "https://github.com/yourname/zoop/archive/main.tar.gz",
            .hash = "1220...",  // Run `zig build` and it will tell you the correct hash
        },
    },
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
    },
}
```

### 2. Configure `build.zig`

**IMPORTANT**: Your executable must be built from the **generated** code, not the source code.

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get zoop dependency
    const zoop_dep = b.dependency("zoop", .{
        .target = target,
        .optimize = optimize,
    });
    
    // Get the code generator tool
    const codegen_exe = zoop_dep.artifact("zoop-codegen");
    
    // Run code generation
    const gen_cmd = b.addRunArtifact(codegen_exe);
    gen_cmd.addArgs(&.{
        "--source-dir", "src",              // Where your source code is
        "--output-dir", "src_generated",    // Where to write generated code
        "--method-prefix", "call_",
        "--getter-prefix", "get_",
        "--setter-prefix", "set_",
    });

    // Build executable from GENERATED code
    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src_generated/main.zig"),  // ← GENERATED
            .target = target,
            .optimize = optimize,
        }),
    });
    
    // Add zoop module so generated code can use it
    const zoop_module = zoop_dep.module("zoop");
    exe.root_module.addImport("zoop", zoop_module);
    
    // Make compilation depend on code generation
    exe.step.dependOn(&gen_cmd.step);

    b.installArtifact(exe);
    
    // Add run step
    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
```

### 3. Write Your Code

**src/main.zig** (source code):
```zig
const std = @import("std");
const zoop = @import("zoop");

pub const Animal = zoop.class(struct {
    name: []const u8,
    
    pub fn makeSound(self: *Animal) void {
        std.debug.print("{s} makes a sound\n", .{self.name});
    }
});

pub const Dog = zoop.class(struct {
    pub const extends = Animal,
    
    breed: []const u8,
    
    pub fn bark(self: *Dog) void {
        std.debug.print("{s} barks!\n", .{self.super.name});
    }
});

pub fn main() void {
    var dog = Dog{
        .super = Animal{ .name = "Buddy" },
        .breed = "Golden Retriever",
    };
    
    dog.call_makeSound();  // Calls inherited method
    dog.bark();            // Calls own method
}
```

### 4. Build and Run

```bash
zig build run
```

The build will:
1. Run `zoop-codegen` to generate `src_generated/main.zig`
2. Compile the generated code
3. Run your application

## How It Works

### Source Code (What You Write)

You write classes using `zoop.class()` as markers:

```zig
pub const MyClass = zoop.class(struct {
    pub const extends = ParentClass,  // Optional inheritance
    
    my_field: i32,
    
    pub fn myMethod(self: *MyClass) void {
        // ...
    }
});
```

### Generated Code (What Gets Built)

The build system generates enhanced code:

```zig
pub const MyClass = struct {
    super: ParentClass,  // Embedded parent
    my_field: i32,
    
    pub fn myMethod(self: *MyClass) void {
        // ... (your code unchanged)
    }
    
    // Auto-generated method wrappers
    pub inline fn call_parentMethod(self: *MyClass, args: ...) ReturnType {
        return self.super.parentMethod(args);
    }
};
```

## Configuration Options

### Code Generation Paths

```zig
gen_cmd.addArgs(&.{
    "--source-dir", "src",           // Where to find your .zig files
    "--output-dir", "src_generated", // Where to write generated code
});
```

### Method Prefixes

```zig
gen_cmd.addArgs(&.{
    "--method-prefix", "call_",  // Prefix for inherited methods
    "--getter-prefix", "get_",   // Prefix for property getters
    "--setter-prefix", "set_",   // Prefix for property setters
});
```

**Example with no prefixes:**
```zig
gen_cmd.addArgs(&.{
    "--method-prefix", "",
    "--getter-prefix", "",
    "--setter-prefix", "",
});

// Then use: dog.makeSound() instead of dog.call_makeSound()
```

## Cross-File Inheritance

You can have classes in different files inherit from each other:

**src/base/entity.zig:**
```zig
const zoop = @import("zoop");

pub const Entity = zoop.class(struct {
    id: u64,
});
```

**src/models/player.zig:**
```zig
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
- Generates proper cross-file inheritance

## Properties

Define properties with automatic getters/setters:

**Source:**
```zig
pub const User = zoop.class(struct {
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
    
    name: []const u8,  // Regular field
});
```

**Generated:**
```zig
pub const User = struct {
    email: []const u8,
    id: u32,
    name: []const u8,
    
    pub inline fn get_email(self: *const User) []const u8 {
        return self.email;
    }
    pub inline fn set_email(self: *User, value: []const u8) void {
        self.email = value;
    }
    pub inline fn get_id(self: *const User) u32 {
        return self.id;
    }
    // No setter for read_only property
};
```

## Project Structure

Recommended structure:

```
myproject/
├── build.zig
├── build.zig.zon
├── src/
│   ├── main.zig           # Your source code
│   ├── models/
│   │   └── user.zig
│   └── base/
│       └── entity.zig
└── src_generated/         # Auto-generated (git ignore this)
    ├── main.zig
    ├── models/
    │   └── user.zig
    └── base/
        └── entity.zig
```

**.gitignore:**
```
zig-cache/
zig-out/
src_generated/    # Don't commit generated code
```

## Troubleshooting

### Error: "zoop-codegen not found"

The zoop dependency needs to be fetched first. Just run:
```bash
zig build
```

Zig will automatically fetch dependencies and build the code generator.

### Error: "no such file src_generated/main.zig"

Code generation hasn't run yet. Make sure:
1. Your `exe.step.dependOn(&gen_cmd.step)` is set up correctly
2. The `--output-dir` matches your executable's `root_source_file`

### Generated code not updating

Clear the cache:
```bash
rm -rf zig-cache src_generated
zig build
```

### Type mismatch errors

Make sure you're:
1. Using `pub const extends = ParentClass` (not `extends: ParentClass`)
2. Initializing through `super` field: `.super = ParentClass{ ... }`
3. Calling inherited methods with prefix: `obj.call_method()`

## Examples

See the working example in `test_consumer/` directory for a complete project setup.

## Security

Zoop includes path traversal protection. The code generator will:
- ❌ Block `..` in file paths
- ❌ Block absolute paths (with warning)
- ✅ Only process files within specified directories

This prevents malicious source files from causing the generator to read/write outside intended directories.

## Next Steps

- Read [API_REFERENCE.md](API_REFERENCE.md) for detailed API docs
- Check [README.md](README.md) for examples
- See [IMPLEMENTATION.md](IMPLEMENTATION.md) for how it works
