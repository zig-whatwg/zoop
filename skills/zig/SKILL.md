
# Zig Programming Standards Skill

## When to use this skill

Load this skill automatically when:
- Working with `.zig` files
- A `build.zig` file is present in the workspace
- User explicitly mentions "Zig" or "Zig project"
- Writing or refactoring Zig code
- Designing struct layouts and type systems
- Managing memory with allocators

## What this skill provides

This skill ensures Claude writes idiomatic, safe, and performant Zig code by:
- Applying correct naming conventions and code style
- Using proper error handling patterns with error unions
- Implementing correct memory management (factory or direct creation patterns)
- Following type safety best practices
- Avoiding common pitfalls and anti-patterns
- Leveraging comptime programming for zero-cost abstractions

For detailed reference materials, see `resources/` directory.

## Core Patterns

### Naming Conventions

```zig
// Types: PascalCase
pub const Object = struct { ... };
pub const Type = enum { ... };
pub const Error = error { ... };

// Functions and variables: snake_case
pub fn addChild(parent: *Object, child: *Object) !void { ... }
const my_variable: i32 = 42;

// Constants: SCREAMING_SNAKE_CASE
pub const MAX_TREE_DEPTH: usize = 1000;

// Private members: prefix with underscore when needed
const _internal_state: State = .init;
```

### Memory Management - Two Valid Patterns

**Pattern 1: Direct Creation (Simple, No Interning)**

```zig
const obj = try Object.create(allocator, "name");
defer obj.release();
```

**Pattern 2: Factory Pattern (RECOMMENDED - With Interning)**

```zig
const factory = try Factory.init(allocator);
defer factory.release();

const obj = try factory.create("name");
defer obj.release();
// Strings automatically interned via factory.string_pool
```

### Error Handling

```zig
// Define domain-specific error sets
pub const ValidationError = error{
    IndexOutOfBounds,
    InvalidHierarchy,
    NotFound,
};

// Combine error sets
pub fn createObject(
    self: *Factory,
    name: []const u8,
) (Allocator.Error || ValidationError)!*Object {
    // Implementation
}

// Use defer for guaranteed cleanup
pub fn operation(allocator: Allocator) !void {
    const factory = try Factory.init(allocator);
    defer factory.release(); // Always runs
    
    try someOperationThatMightFail();
}
```

### Optionals and Null Safety

```zig
// Optional pointers can be null
const maybe_ptr: ?*i32 = null;

// Unwrapping with orelse
const value = maybe_value orelse default_value;

// Unwrapping with if (safe access)
if (maybe_value) |value| {
    // Use value here (not null)
}

// Combining with error unions
fn findUser(id: u32) !?User {
    if (id == 0) return error.InvalidId;
    if (!userExists(id)) return null;
    return getUser(id);
}
```

### Reference Counting Pattern

```zig
pub const Object = struct {
    ref_count: usize = 1,  // Start at 1
    allocator: Allocator,
    
    pub fn acquire(self: *Object) void {
        self.ref_count += 1;
    }
    
    pub fn release(self: *Object) void {
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            self.deinit();
        }
    }
    
    fn deinit(self: *Object) void {
        self.allocator.destroy(self);
    }
};

// Usage
const obj = try Object.create(allocator, "name");
defer obj.release();

// Acquire before sharing
object.acquire();
other.object = object;
```

### Interface Implementation ⚠️ CRITICAL

**❌ WRONG: Adding interface methods to base class**

```zig
pub const Base = struct {
    // ❌ WRONG: Interface methods on base class
    pub fn children(self: *Base) Collection {
        return Collection.init(self);
    }
};

// Problem: Now all subclasses inherit these methods!
const leaf = try Leaf.create(allocator, "data");
leaf.base.firstChild(); // ❌ Makes no sense for Leaf!
```

**✅ CORRECT: Implementing on specific types**

```zig
// ✅ Base class has only base functionality
pub const Base = struct {
    pub fn addChild(self: *Base, child: *Base) !void { }
    pub fn removeChild(self: *Base, child: *Base) !*Base { }
};

// ✅ Container-specific methods on Container type
pub const Container = struct {
    base: Base,
    
    pub fn children(self: *Container) Collection {
        return Collection.init(&self.base);
    }
    
    pub fn firstChild(self: *const Container) ?*Item {
        // Implementation
    }
};

// ✅ Leaf does NOT have Container interface
pub const Leaf = struct {
    base: Base,
    data: []const u8,
    
    // Leaf-specific methods only
    pub fn getData(self: *Leaf) []const u8 { }
};
```

**Key principle**: Duplicate interface implementations across types for compile-time type safety. DO NOT add methods to base class for inheritance.

### Slices and Arrays

```zig
// Arrays have compile-time known size
const array = [5]u8{ 1, 2, 3, 4, 5 };
const inferred = [_]u8{ 1, 2, 3 }; // Size inferred

// Slices are fat pointers (pointer + length)
const slice: []const u8 = &array;
const slice2: []const u8 = array[0..3];

// String literals are []const u8
const string: []const u8 = "hello";

// Sentinel-terminated (for C interop)
const c_string: [:0]const u8 = "hello";
```

### Struct Initialization

```zig
// Designated initialization (preferred)
const point = Point{
    .x = 10,
    .y = 20,
};

// Anonymous struct literals
const options = .{
    .verbose = true,
    .timeout = 30,
};

// Struct with defaults
pub const Config = struct {
    timeout: u32 = 30,
    verbose: bool = false,
    
    pub fn init() Config {
        return .{}; // Use all defaults
    }
};
```

### Testing Patterns

```zig
const std = @import("std");
const testing = std.testing;

test "basic operation" {
    try testing.expect(2 + 2 == 4);
}

test "with allocations" {
    const allocator = testing.allocator; // Detects leaks
    
    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();
    
    try list.append(42);
    try testing.expectEqual(@as(u8, 42), list.items[0]);
}

test "error handling" {
    try testing.expectError(error.InvalidInput, failingFunction());
}
```

### Comptime for Zero-Cost Abstractions

```zig
fn ArrayList(comptime T: type) type {
    return struct {
        items: []T,
        allocator: Allocator,
        
        pub fn init(allocator: Allocator) @This() {
            return .{
                .items = &[_]T{},
                .allocator = allocator,
            };
        }
    };
}

// Usage - zero runtime cost
var object_list = ArrayList(*Object).init(allocator);
```

### C Interoperability Basics

```zig
// Import C headers
const c = @cImport({
    @cInclude("stdio.h");
    @cDefine("_GNU_SOURCE", "1");
});

// Use C functions
_ = c.printf("Hello from C!\n");

// Export Zig functions for C
export fn add(a: c_int, b: c_int) c_int {
    return a + b;
}

// extern struct for C compatibility
const CPoint = extern struct {
    x: c_int,
    y: c_int,
};

// Null-terminated strings for C
const c_str: [*:0]const u8 = "hello";
```

## Common Anti-Patterns to Avoid

### ❌ Using `usingnamespace` (REMOVED in Zig 0.15)

**The `usingnamespace` keyword has been removed from Zig.** Do not use it.

```zig
// ❌ REMOVED: usingnamespace
pub usingnamespace @import("other.zig");
```

**Alternatives:**

**For conditional inclusion:**
```zig
// ✅ GOOD: Include unconditionally (lazy compilation)
pub const foo = 123;

// ✅ GOOD: Or use @compileError for safety
pub const foo = if (have_foo)
    123
else
    @compileError("foo not supported on this target");
```

**For implementation switching:**
```zig
// ❌ BAD: usingnamespace with switch
pub usingnamespace switch (target) {
    .windows => struct { pub fn init() T { ... } },
    else => struct { pub fn init() T { ... } },
};

// ✅ GOOD: Switch on individual declarations
pub const init = switch (target) {
    .windows => initWindows,
    else => initOther,
};
fn initWindows() T { ... }
fn initOther() T { ... }
```

**For mixins (use zero-bit fields with @fieldParentPtr):**
```zig
// ❌ BAD: usingnamespace mixin
pub usingnamespace CounterMixin(Foo);

// ✅ GOOD: Namespaced mixin with zero-bit field
pub fn CounterMixin(comptime T: type) type {
    return struct {
        pub fn increment(m: *@This()) void {
            const x: *T = @alignCast(@fieldParentPtr("counter", m));
            x._counter += 1;
        }
    };
}

pub const Foo = struct {
    _counter: u32 = 0,
    counter: CounterMixin(Foo) = .{}, // Zero-bit field
};

// Usage: foo.counter.increment() instead of foo.increment()
```

### ❌ Unsafe Casts Without Validation

```zig
// ❌ BAD
fn getByte(index: usize) u8 {
    return @intCast(index); // May truncate!
}

// ✅ GOOD
fn getChild(parent: *Object, index: usize) !*Object {
    if (index >= parent.children.items.len) {
        return error.IndexOutOfBounds;
    }
    return parent.children.items[index];
}
```

### ❌ Using Sentinel Values Instead of Error Unions

```zig
// ❌ BAD
pub fn findObject(id: []const u8) ?*Object {
    return object; // Loses error information
}

// ✅ GOOD
pub fn findObject(id: []const u8) !*Object {
    return object orelse error.NotFound;
}
```

### ❌ Allocating in Loops

```zig
// ❌ BAD
for (objects) |object| {
    var buffer = ArrayList(u8).init(allocator);
    defer buffer.deinit();
    // Process...
}

// ✅ GOOD
var buffer = ArrayList(u8).init(allocator);
defer buffer.deinit();

for (objects) |object| {
    buffer.clearRetainingCapacity(); // Reuse allocation
    // Process...
}
```

## Build Mode Considerations

```zig
// Debug (default) - Full runtime safety, no optimization
// ReleaseSafe - Optimized with safety checks
// ReleaseFast - Optimized without safety checks
// ReleaseSmall - Optimized for binary size

// Control runtime safety per-scope
pub fn hotPath() void {
    @setRuntimeSafety(false);
    // Critical code here
}

// Use wrapping arithmetic when overflow is intentional
pub fn wrappingAdd(a: u8, b: u8) u8 {
    return a +% b; // Explicit wrapping
}
```

## Standard Library Essentials

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// Testing allocator (detects leaks)
const allocator = std.testing.allocator;

// GeneralPurposeAllocator (for debugging)
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();

// ArenaAllocator (batch free)
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit(); // Frees everything at once

// String operations
if (std.mem.eql(u8, str1, str2)) { }
const has_prefix = std.mem.startsWith(u8, string, "prefix");

// HashMap usage
var map = std.StringHashMap(i32).init(allocator);
defer map.deinit();
try map.put("key", 42);
```

## Performance Best Practices

### Cache-Friendly Layouts

```zig
// ✅ Hot fields first, cold fields last
pub const Object = struct {
    // Hot fields (accessed frequently)
    object_type: ObjectType,     // 2 bytes
    ref_count: usize,            // 8 bytes
    parent: ?*Object,            // 8 bytes
    
    // Cold fields (accessed rarely)
    extra_data: ?*ExtraData,
};
```

### Inline Hot Paths

```zig
// Use inline for small, frequently called functions
pub inline fn isContainer(object: *const Object) bool {
    return object.object_type == .container;
}

// Use noinline for cold paths
noinline fn handleError(object: *Object) noreturn {
    std.debug.panic("Unexpected type: {}", .{object.object_type});
}
```

## Resources

For detailed information, see:
- `resources/advanced-patterns.md` - Advanced Zig patterns and techniques
- `resources/c-interop-reference.md` - Complete C interoperability guide
- `resources/stdlib-reference.md` - Standard library patterns
- `resources/templates/` - Project templates and build.zig examples
- `scripts/format.zig` - Code formatter
- `scripts/new-project.sh` - Project initialization script

## Quick Reference

**Memory Management**: Use factory pattern with string interning for production, direct creation for tests.

**Error Handling**: Domain-specific error sets, combine with `||`, use `defer` for cleanup.

**Type Safety**: No null pointers without `?`, no inheritance of interface methods, explicit bounds checking.

**Performance**: Reuse allocations, inline hot paths, keep structs cache-friendly.

**C Interop**: Use `c_int` not `i32`, sentinel-terminated strings `[*:0]const u8`, `extern struct` for C layout.
