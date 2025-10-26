# Advanced Zig Patterns

## IMPORTANT: `usingnamespace` Removed in Zig 0.15

The `usingnamespace` keyword has been removed from Zig. This section documents alternatives.

### Why `usingnamespace` Was Removed

1. **Harms readability**: Makes it unclear where declarations are defined
2. **Poor namespacing**: Encourages flat namespaces instead of proper organization
3. **Complicates incremental compilation**: Difficult to model dependencies

### Alternative: Conditional Inclusion

```zig
// ❌ OLD: usingnamespace for conditional inclusion
pub usingnamespace if (have_foo) struct {
    pub const foo = 123;
} else struct {};

// ✅ NEW: Include unconditionally (lazy compilation won't analyze unless used)
pub const foo = 123;

// ✅ NEW: Or use @compileError for safety
pub const foo = if (have_foo)
    123
else
    @compileError("foo not supported on this target");
```

### Alternative: Implementation Switching

```zig
// ❌ OLD: usingnamespace with switch
pub usingnamespace switch (target) {
    .windows => struct {
        pub const target_name = "windows";
        pub fn init() T { /* windows impl */ }
    },
    else => struct {
        pub const target_name = "posix";
        pub fn init() T { /* posix impl */ }
    },
};

// ✅ NEW: Switch on individual declarations
pub const target_name = switch (target) {
    .windows => "windows",
    else => "posix",
};

pub const init = switch (target) {
    .windows => initWindows,
    else => initPosix,
};

fn initWindows() T {
    // Windows implementation
}

fn initPosix() T {
    // POSIX implementation
}
```

### Alternative: Mixins with Zero-Bit Fields

The recommended approach for mixins uses zero-bit fields with `@fieldParentPtr` to provide proper namespacing.

```zig
// ❌ OLD: usingnamespace mixin (removed)
pub fn CounterMixin(comptime T: type) type {
    return struct {
        pub fn incrementCounter(x: *T) void {
            x._counter += 1;
        }
        pub fn resetCounter(x: *T) void {
            x._counter = 0;
        }
    };
}

pub const Foo = struct {
    _counter: u32 = 0,
    pub usingnamespace CounterMixin(Foo);
};

// Usage: foo.incrementCounter()

// ✅ NEW: Zero-bit field mixin with proper namespacing
pub fn CounterMixin(comptime T: type) type {
    return struct {
        pub fn increment(m: *@This()) void {
            const x: *T = @alignCast(@fieldParentPtr("counter", m));
            x._counter += 1;
        }
        
        pub fn reset(m: *@This()) void {
            const x: *T = @alignCast(@fieldParentPtr("counter", m));
            x._counter = 0;
        }
        
        pub fn get(m: *const @This()) u32 {
            const x: *const T = @alignCast(@fieldParentPtr("counter", m));
            return x._counter;
        }
    };
}

pub const Foo = struct {
    _counter: u32 = 0,
    counter: CounterMixin(Foo) = .{}, // Zero-bit field
};

// Usage: foo.counter.increment()
```

**Benefits of zero-bit field mixins:**
- Proper namespacing: `foo.counter.increment()` vs `foo.incrementCounter()`
- Can include both fields and methods in the mixin
- Zero runtime cost (field is zero-sized)
- More explicit and discoverable API

### Alternative: Manual Re-exports

For merging namespaces, manually re-export declarations:

```zig
// ❌ OLD: usingnamespace to merge namespaces
pub usingnamespace @import("module_a.zig");
pub usingnamespace @import("module_b.zig");

// ✅ NEW: Import separately or manually re-export
const a = @import("module_a.zig");
const b = @import("module_b.zig");

// Re-export specific items
pub const functionA = a.functionA;
pub const functionB = b.functionB;

// Or use separate namespaces
pub const module_a = @import("module_a.zig");
pub const module_b = @import("module_b.zig");
```

### Mixin Pattern Example: Multiple Capabilities

```zig
pub fn LoggableMixin(comptime T: type) type {
    return struct {
        pub fn log(m: *const @This(), message: []const u8) void {
            const self: *const T = @alignCast(@fieldParentPtr("logger", m));
            std.debug.print("[{s}] {s}\n", .{ self.name, message });
        }
    };
}

pub fn SerializableMixin(comptime T: type) type {
    return struct {
        pub fn toJson(m: *const @This(), allocator: Allocator) ![]u8 {
            const self: *const T = @alignCast(@fieldParentPtr("serializer", m));
            return std.json.stringifyAlloc(allocator, self, .{});
        }
    };
}

pub const Widget = struct {
    name: []const u8,
    value: i32,
    
    // Multiple zero-bit field mixins
    logger: LoggableMixin(Widget) = .{},
    serializer: SerializableMixin(Widget) = .{},
};

// Usage:
// widget.logger.log("Widget created");
// const json = try widget.serializer.toJson(allocator);
```

## anytype and Duck Typing

```zig
fn printAnything(writer: anytype, value: anytype) !void {
    try writer.print("{any}\n", .{value});
}

fn add(comptime T: type, a: T, b: T) T {
    comptime {
        const info = @typeInfo(T);
        if (info != .Int and info != .Float) {
            @compileError("add requires numeric type");
        }
    }
    return a + b;
}

fn processItems(items: anytype) void {
    for (items) |item| {
        process(item);
    }
}
```

## @This() Pattern

```zig
fn List(comptime T: type) type {
    return struct {
        const Self = @This();
        
        items: []T,
        allocator: Allocator,
        
        pub fn init(allocator: Allocator) Self {
            return .{
                .items = &.{},
                .allocator = allocator,
            };
        }
        
        pub fn clone(self: *const Self) !Self {
            const new_items = try self.allocator.dupe(T, self.items);
            return .{
                .items = new_items,
                .allocator = self.allocator,
            };
        }
    };
}
```

## Tagged Unions

```zig
const Value = union(enum) {
    int: i32,
    float: f64,
    string: []const u8,
    boolean: bool,
    
    pub fn format(
        self: Value,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .int => |i| try writer.print("{}", .{i}),
            .float => |f| try writer.print("{d}", .{f}),
            .string => |s| try writer.print("{s}", .{s}),
            .boolean => |b| try writer.print("{}", .{b}),
        }
    }
    
    pub fn isNumeric(self: Value) bool {
        return switch (self) {
            .int, .float => true,
            else => false,
        };
    }
};
```

## Packed Structs

```zig
const Flags = packed struct {
    read: bool,
    write: bool,
    execute: bool,
    _padding: u5 = 0,
    
    pub fn toInt(self: Flags) u8 {
        return @bitCast(self);
    }
};
```

## Result Location Semantics

```zig
fn createLargeStruct() LargeStruct {
    return .{
        .field1 = 100,
        .field2 = 200,
        .data = [_]u8{0} ** 1000,
        // Written directly to caller's location - no copy!
    };
}

fn fillBuffer(allocator: Allocator) ![]u8 {
    return try allocator.alloc(u8, 1024);
    // Allocator writes directly to return location
}
```

## Volatile and Atomics

```zig
const std = @import("std");

// Volatile for memory-mapped I/O
const reg: *volatile u32 = @ptrFromInt(0x4000_0000);
reg.* = 0xFF; // Won't be optimized away

// Atomic operations
var counter = std.atomic.Value(u32).init(0);

counter.store(10, .seq_cst);
const value = counter.load(.seq_cst);
const old = counter.fetchAdd(1, .seq_cst);
const swapped = counter.cmpxchgWeak(10, 20, .seq_cst, .seq_cst);

// Memory ordering options:
// .unordered, .monotonic, .acquire, .release, .acq_rel, .seq_cst
```

## Cross-Platform Code

```zig
const builtin = @import("builtin");

// OS detection
const is_windows = builtin.os.tag == .windows;
const is_linux = builtin.os.tag == .linux;
const is_macos = builtin.os.tag == .macos;

if (builtin.os.tag == .windows) {
    // Windows-specific code
} else {
    // Unix-like systems
}

// CPU architecture
if (builtin.cpu.arch == .x86_64) {
    // x86_64 specific
} else if (builtin.cpu.arch == .aarch64) {
    // ARM64 specific
}

// Build mode
if (builtin.mode == .Debug) {
    std.debug.print("Debug mode enabled\n", .{});
}

// Target information
const is_64bit = @sizeOf(usize) == 8;
const is_big_endian = builtin.cpu.arch.endian() == .big;
```

## Comptime Validation

```zig
pub fn setValue(comptime T: type, object: *Object, value: T) void {
    comptime {
        if (@sizeOf(T) > 64) {
            @compileError("Value too large - max 64 bytes");
        }
        if (!@hasField(T, "ref_count")) {
            @compileError("Type must have ref_count field");
        }
    }
    // Implementation
}

pub fn validateName(comptime name: []const u8) void {
    comptime {
        if (name.len == 0) {
            @compileError("Name cannot be empty");
        }
        if (name[0] >= '0' and name[0] <= '9') {
            @compileError("Name cannot start with digit");
        }
    }
}
```

## Optional Chaining

```zig
pub fn getParentContainer(object: *Object) ?*Container {
    if (object.parent) |parent| {
        if (parent.object_type == .container) {
            return @fieldParentPtr(Container, "base", parent);
        }
    }
    return null;
}

pub fn findAncestor(object: *Object, name: []const u8) ?*Container {
    var current = object.parent;
    while (current) |obj| {
        if (obj.object_type == .container) {
            const container = @fieldParentPtr(Container, "base", obj);
            if (std.mem.eql(u8, container.name, name)) {
                return container;
            }
        }
        current = obj.parent;
    }
    return null;
}

// Payload capture in switch
fn handleValue(val: Value) void {
    switch (val) {
        .int => |i| std.debug.print("Integer: {}\n", .{i}),
        .string => |s| std.debug.print("String: {s}\n", .{s}),
        .float => |f| std.debug.print("Float: {d}\n", .{f}),
    }
}

// While with continue expression
var i: usize = 0;
while (i < 10) : (i += 1) {
    processItem(i);
}
```

## Error Return Traces

```zig
// Error return traces track the path an error took through 'try' statements
// They do NOT unwind the stack (zero overhead)

pub fn main() !void {
    try operation(); // Error bubbles up with trace
}

fn operation() !void {
    try failableFunction(); // Trace records this
}

fn failableFunction() !void {
    try deeperFunction(); // Trace records this
}

fn deeperFunction() !void {
    return error.SomethingWentWrong; // Error originates here
}

// Output shows path through 'try' statements, not full call stack
// Zero runtime cost - traces built during error propagation
```

## Error Set Merging and Inference

```zig
// Merge error sets
const FileError = error{ NotFound, PermissionDenied };
const NetworkError = error{ ConnectionRefused, Timeout };

fn operation() (FileError || NetworkError || Allocator.Error)!void {
    // Can return any error from these sets
}

// Error set inference
fn autoError() !void {
    if (condition) return error.SomeError;
    if (other) return error.OtherError;
    // Inferred: error{SomeError, OtherError}!void
}

// anyerror catches all (avoid in libraries)
fn catchAll() anyerror!void {
    // Can return any error - loses type information
}

// Error payload capture
if (operation()) |result| {
    // Success - use result
} else |err| {
    std.debug.print("Error: {}\n", .{err});
}
```

## Build System Patterns

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Executable
    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    b.installArtifact(exe);
    
    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);
    
    // Unit tests
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
    
    // Static library
    const lib = b.addStaticLibrary(.{
        .name = "mylib",
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);
    
    // Add module dependency
    const utils = b.addModule("utils", .{
        .root_source_file = b.path("src/utils.zig"),
    });
    exe.root_module.addImport("utils", utils);
    
    // Link system libraries
    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("sqlite3");
}
```

## Module System

```zig
// In build.zig - declare modules
const utils = b.addModule("utils", .{
    .root_source_file = b.path("src/utils.zig"),
});

const network = b.addModule("network", .{
    .root_source_file = b.path("src/network.zig"),
});

// Add imports to executable
exe.root_module.addImport("utils", utils);
exe.root_module.addImport("network", network);

// In source - use modules
const utils = @import("utils");
const network = @import("network");

pub fn main() void {
    const result = utils.helper();
    network.connect();
}

// Module dependencies
network.addImport("utils", utils);
```

## Undefined Behavior

```zig
// Common undefined behavior Zig catches in safe modes:
// 1. Integer overflow (without wrapping operators)
// 2. Index out of bounds
// 3. Dereferencing null
// 4. Use after free
// 5. Data races

// Use 'undefined' to skip initialization
var x: i32 = undefined;
x = 42; // OK - now it has a value

// 'unreachable' for impossible code paths
fn getColor(value: u8) Color {
    return switch (value) {
        0 => .red,
        1 => .green,
        2 => .blue,
        else => unreachable, // Asserts impossible
    };
}

// In ReleaseFast: optimizer hint
// In Debug/ReleaseSafe: panic if reached

// Safety checks control
pub fn unsafeOperation() void {
    @setRuntimeSafety(false);
    // No bounds checking, overflow checks, etc.
}
```
