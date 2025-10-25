# Using Zoop as a Library Dependency

## The Problem

When Zoop is used as a library dependency (via `build.zig.zon`), the build-time code generation must work in the **consumer's** project, not just in Zoop's own build.

## Solution: Two-Phase Approach

### Phase 1: Build System Integration (Required)

Consumer's `build.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    // Get Zoop dependency
    const zoop_dep = b.dependency("zoop", .{
        .target = target,
        .optimize = optimize,
    });
    
    // Get Zoop module
    const zoop_module = zoop_dep.module("zoop");
    
    // CREATE ZOOP BUILD HELPER
    const zoop_build = zoop_dep.builder.dependency("zoop", .{}).artifact("zoop-codegen");
    
    // OPTION A: Run code generation as a build step
    const codegen_cmd = b.addRunArtifact(zoop_build);
    codegen_cmd.addArg("--source-dir");
    codegen_cmd.addArg("src");
    codegen_cmd.addArg("--output-dir");
    codegen_cmd.addArg("zig-cache/zoop-generated");
    codegen_cmd.addArg("--method-prefix");
    codegen_cmd.addArg("call_");
    codegen_cmd.addArg("--getter-prefix");
    codegen_cmd.addArg("get_");
    codegen_cmd.addArg("--setter-prefix");
    codegen_cmd.addArg("set_");
    
    // Create your module
    const my_module = b.addModule("myapp", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Add Zoop as import
    my_module.addImport("zoop", zoop_module);
    
    // Add generated code path
    my_module.addImport("generated", .{
        .root_source_file = b.path("zig-cache/zoop-generated"),
    });
    
    // Build your executable
    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_module = my_module,
    });
    
    // CRITICAL: Make exe depend on code generation
    exe.step.dependOn(&codegen_cmd.step);
    
    b.installArtifact(exe);
}
```

Consumer's `build.zig.zon`:

```zig
.{
    .name = "myapp",
    .version = "0.1.0",
    .dependencies = .{
        .zoop = .{
            .url = "https://github.com/user/zoop/archive/main.tar.gz",
            .hash = "...",
        },
    },
}
```

### Phase 2: Usage in Consumer Code

```zig
// src/main.zig
const std = @import("std");
const zoop = @import("zoop");

// Define your classes
const Parent = zoop.class(struct {
    value: u32,
    
    pub fn getValue(self: *Parent) u32 {
        return self.value;
    }
});

const Child = zoop.class(struct {
    pub const extends = Parent;
    
    pub const config = zoop.ClassConfig{
        .method_prefix = "call_",
        .getter_prefix = "get_",
        .setter_prefix = "set_",
    };
    
    name: []const u8,
});

pub fn main() !void {
    var child = Child{
        .value = 42,
        .name = "test",
    };
    
    // Generated methods with your prefixes
    child.call_getValue();
    // etc.
}
```

## Implementation Strategy

### Option A: Standalone Codegen Executable (RECOMMENDED)

Zoop provides a `zoop-codegen` executable that consumers run as a build step:

**In Zoop's `build.zig`:**

```zig
pub fn build(b: *std.Build) void {
    // ... module setup ...
    
    // Build the code generator as a separate executable
    const codegen_exe = b.addExecutable(.{
        .name = "zoop-codegen",
        .root_source_file = b.path("src/codegen_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    b.installArtifact(codegen_exe);
    
    // Consumers can run this via b.addRunArtifact()
}
```

**In Zoop's `src/codegen_main.zig`:**

```zig
const std = @import("std");
const codegen = @import("codegen.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Parse command line arguments
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    
    _ = args.next(); // skip program name
    
    var source_dir: ?[]const u8 = null;
    var output_dir: ?[]const u8 = null;
    var config = codegen.ClassConfig{};
    
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--source-dir")) {
            source_dir = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--output-dir")) {
            output_dir = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--method-prefix")) {
            config.method_prefix = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--getter-prefix")) {
            config.getter_prefix = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--setter-prefix")) {
            config.setter_prefix = args.next() orelse return error.MissingValue;
        }
    }
    
    if (source_dir == null or output_dir == null) {
        std.debug.print("Usage: zoop-codegen --source-dir <dir> --output-dir <dir> [options]\n", .{});
        return error.MissingArguments;
    }
    
    // Run code generation
    try codegen.generateAllClasses(allocator, source_dir.?, output_dir.?, config);
    
    std.debug.print("Zoop: Generated classes in {s}\n", .{output_dir.?});
}
```

### Option B: Build System Helper Function

Zoop provides a helper function for `build.zig`:

```zig
// In Zoop's build.zig
pub fn addZoopCodegen(
    b: *std.Build,
    module: *std.Build.Module,
    config: struct {
        source_dir: []const u8 = "src",
        method_prefix: []const u8 = "call_",
        getter_prefix: []const u8 = "get_",
        setter_prefix: []const u8 = "set_",
    },
) void {
    const zoop_dep = b.dependency("zoop", .{});
    const codegen_exe = zoop_dep.artifact("zoop-codegen");
    
    const codegen_cmd = b.addRunArtifact(codegen_exe);
    codegen_cmd.addArg("--source-dir");
    codegen_cmd.addArg(config.source_dir);
    // ... etc
    
    // Make module depend on codegen
    module.builder.getInstallStep().dependOn(&codegen_cmd.step);
}
```

Consumer's `build.zig` becomes simpler:

```zig
const zoop = @import("zoop");

pub fn build(b: *std.Build) void {
    const my_module = b.addModule("myapp", .{
        .root_source_file = b.path("src/main.zig"),
    });
    
    // One line setup!
    zoop.addZoopCodegen(b, my_module, .{
        .method_prefix = "call_",
    });
}
```

## Build Flow for Library Consumers

```
Consumer runs: zig build

    ↓

1. Zig downloads zoop dependency (if needed)
   
    ↓

2. Zig builds zoop-codegen executable
   
    ↓

3. Consumer's build.zig runs zoop-codegen:
   - Scans consumer's src/ directory
   - Finds zoop.class() calls
   - Generates enhanced structs
   - Writes to zig-cache/zoop-generated/
   
    ↓

4. Consumer's code compiles
   - Imports generated classes
   - All methods available with configured prefixes
   
    ↓

5. Done! Binary created.
```

## Advantages of This Approach

1. ✅ **Works as library dependency**: No special setup needed
2. ✅ **Automatic**: Runs every build
3. ✅ **Configurable**: Consumer controls prefixes
4. ✅ **Cached**: Only regenerates when source changes
5. ✅ **Standard Zig**: Uses normal build system patterns
6. ✅ **Cross-platform**: Works everywhere Zig works

## Example Repository Structure

```
consumer-project/
├── build.zig          # Uses zoop.addZoopCodegen()
├── build.zig.zon      # Lists zoop dependency
├── src/
│   ├── main.zig       # Imports zoop, defines classes
│   └── models.zig     # More classes
├── zig-cache/
│   └── zoop-generated/
│       ├── main.zig   # Generated enhanced classes
│       └── models.zig # Generated enhanced classes
└── zig-out/
    └── bin/
        └── myapp      # Final executable
```

## Next Steps

To implement this:

1. **Create `src/codegen_main.zig`**: CLI tool for code generation
2. **Update Zoop's `build.zig`**: Build codegen executable
3. **Implement `codegen.generateAllClasses()`**: Full parser + generator
4. **Add `addZoopCodegen()` helper**: Convenience function for consumers
5. **Write tests**: Ensure it works as dependency
6. **Document**: Clear examples for consumers

This makes Zoop usable as a normal Zig dependency while maintaining the automatic code generation you want.
