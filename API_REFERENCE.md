# Zoop API Reference

## Build System API

### `zoop.build()`

Main function to integrate Zoop into your build.

**Signature:**
```zig
pub fn build(
    b: *std.Build,
    artifact: *std.Build.Step.Compile,
    config: BuildConfig,
) void
```

**Usage:**
```zig
const zoop = @import("zoop");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add Zoop
    zoop.build(b, exe, .{
        .source_dir = "src",
        .output_dir = "zig-cache/zoop-generated",
        .method_prefix = "call_",
        .getter_prefix = "get_",
        .setter_prefix = "set_",
    });

    b.installArtifact(exe);
}
```

**Parameters:**
- `b: *std.Build` - The build context
- `artifact: *std.Build.Step.Compile` - The executable or library to add Zoop to
- `config: BuildConfig` - Configuration options

**What it does:**
1. Adds zoop module to your artifact imports
2. Finds `zoop-codegen` executable (or errors with helpful instructions)
3. Sets up automatic code generation before compilation
4. Configures method name prefixes

**Errors:**
- Panics with helpful message if zoop dependency not found
- Panics with instructions if `zoop-codegen` not built yet

---

### `zoop.BuildConfig`

Configuration struct for code generation.

**Type:**
```zig
pub const BuildConfig = struct {
    source_dir: []const u8 = "src",
    output_dir: []const u8 = "zig-cache/zoop-generated",
    method_prefix: []const u8 = "call_",
    getter_prefix: []const u8 = "get_",
    setter_prefix: []const u8 = "set_",
};
```

**Fields:**
- `source_dir` - Directory to scan for class definitions (default: `"src"`)
- `output_dir` - Where to write generated code (default: `"zig-cache/zoop-generated"`)
- `method_prefix` - Prefix for inherited methods (default: `"call_"`)
- `getter_prefix` - Prefix for property getters (default: `"get_"`)
- `setter_prefix` - Prefix for property setters (default: `"set_"`)

**Examples:**
```zig
// Use all defaults
zoop.build(b, exe, .{});

// Custom source directory only
zoop.build(b, exe, .{
    .source_dir = "lib",
});

// No prefixes
zoop.build(b, exe, .{
    .method_prefix = "",
    .getter_prefix = "",
    .setter_prefix = "",
});

// Custom prefixes
zoop.build(b, exe, .{
    .method_prefix = "invoke_",
    .getter_prefix = "read_",
    .setter_prefix = "write_",
});
```

---

## Runtime API

### `zoop.class()`

Wrap a struct definition to create a class with inheritance support.

**Signature:**
```zig
pub fn class(comptime definition: type) type
```

**Usage:**
```zig
const zoop = @import("zoop");

const MyClass = zoop.class(struct {
    // Inheritance (optional)
    pub const extends = ParentClass;
    
    // Fields
    myField: u32,
    
    // Methods
    pub fn myMethod(self: *MyClass) void {
        // ...
    }
});
```

**Parameters:**
- `definition: type` - A struct type containing:
  - `extends` (optional) - Parent class to inherit from
  - Fields - Struct fields
  - Methods - Public functions

**Returns:**
- Enhanced struct type with merged parent fields and generated methods

**Generated Code:**
After `zoop-codegen` runs, the class is expanded to include:
- All parent fields (at start, never reordered)
- All child fields (sorted by alignment)
- Inherited methods with configured prefix (unless overridden)
- Your own methods (unchanged)

**Example:**
```zig
const Person = zoop.class(struct {
    name: []const u8,
    age: u32,
    
    pub fn greet(self: *Person) void {
        std.debug.print("Hello, I'm {s}\n", .{self.name});
    }
});

const Employee = zoop.class(struct {
    pub const extends = Person;
    
    employee_id: u32,
    
    pub fn work(self: *Employee) void {
        std.debug.print("Working...\n", .{});
    }
});

// After generation, Employee has:
// - All Person fields: name, age
// - All Employee fields: employee_id
// - Inherited method: call_greet() (with prefix from config)
// - Own method: work()

var emp = Employee{
    .name = "Alice",
    .age = 30,
    .employee_id = 1234,
};

emp.call_greet();  // Uses configured prefix
emp.work();        // No prefix (own method)
```

---

### Method Override

Child classes can override parent methods:

```zig
const Manager = zoop.class(struct {
    pub const extends = Employee;
    
    department: []const u8,
    
    // Override parent method
    pub fn greet(self: *Manager) void {
        std.debug.print("Hello, I'm {s}, manager of {s}\n", 
            .{self.name, self.department});
    }
});

var mgr = Manager{
    .name = "Bob",
    .age = 40,
    .employee_id = 5678,
    .department = "Engineering",
};

mgr.greet();       // Uses Manager's override (no prefix)
mgr.call_work();   // Inherited from Employee (with prefix)
```

**Override Detection:**
- If child defines a method with same name as parent, child's version is used
- No `call_` prefix is added to overridden methods
- Overridden methods are called directly without prefix

---

### Mixins

Compose multiple behaviors without deep inheritance hierarchies:

```zig
// Define reusable mixins
const Timestamped = zoop.class(struct {
    created_at: i64,
    updated_at: i64,
    
    pub fn updateTimestamp(self: *Timestamped) void {
        self.updated_at = std.time.timestamp();
    }
});

const Serializable = zoop.class(struct {
    pub fn toJson(self: *const Serializable, allocator: std.mem.Allocator) ![]const u8 {
        // Implementation...
        return try allocator.dupe(u8, "{}");
    }
});

// Use mixins
const User = zoop.class(struct {
    pub const extends = Entity;  // Optional parent
    pub const mixins = .{ Timestamped, Serializable };  // Multiple mixins
    
    name: []const u8,
    email: []const u8,
});

// Generated:
const User = struct {
    super: Entity,         // Parent embedded
    created_at: i64,       // From Timestamped (flattened)
    updated_at: i64,       // From Timestamped (flattened)
    name: []const u8,
    email: []const u8,
    
    pub inline fn call_save(self: *User) void { ... }  // From parent
    pub fn updateTimestamp(self: *User) void { ... }    // From mixin (type rewritten)
    pub fn toJson(self: *const User, ...) ![]const u8 { ... }  // From mixin
};
```

**Mixin Rules:**
- Fields are **flattened** directly into child (not embedded)
- Methods are **copied** with type names rewritten
- Child methods override mixin methods (no duplication)
- Multiple mixins can be applied: `pub const mixins = .{ A, B, C };`
- Works with or without `extends` (can use mixins alone)

**Syntax:**
```zig
// Mixins only
pub const mixins = .{ MixinA, MixinB };

// Parent + mixins
pub const extends = Parent;
pub const mixins = .{ MixinA, MixinB };
```

---

### Properties (Planned)

Properties with auto-generated getters and setters:

```zig
const User = zoop.class(struct {
    pub const properties = .{
        .email = .{
            .type = []const u8,
            .access = .read_write,
            .default = "",
        },
        .created_at = .{
            .type = i64,
            .access = .read_only,
            .default = 0,
        },
    };
    
    name: []const u8,
});

var user = User{ .name = "Alice" };

// Generated with configured prefix
user.set_email("alice@example.com");
const email = user.get_email();

// Read-only property
const timestamp = user.get_created_at();
// No set_created_at() generated
```

---

## Command Line Tool

### `zoop-codegen`

Standalone executable for code generation.

**Usage:**
```bash
zoop-codegen --source-dir <dir> --output-dir <dir> [OPTIONS]
```

**Required Arguments:**
- `--source-dir <dir>` - Directory to scan for class definitions
- `--output-dir <dir>` - Directory to write generated code

**Optional Arguments:**
- `--method-prefix <str>` - Prefix for inherited methods (default: `"call_"`)
- `--getter-prefix <str>` - Prefix for property getters (default: `"get_"`)
- `--setter-prefix <str>` - Prefix for property setters (default: `"set_"`)
- `-h, --help` - Show help message

**Examples:**
```bash
# Default prefixes
zoop-codegen --source-dir src --output-dir zig-cache/zoop-generated

# No prefixes
zoop-codegen --source-dir src --output-dir generated \
    --method-prefix "" --getter-prefix "" --setter-prefix ""

# Custom prefixes
zoop-codegen --source-dir lib --output-dir gen \
    --method-prefix "invoke_" --getter-prefix "read_" --setter-prefix "write_"
```

**Build:**
```bash
zig build codegen
```

**Location:**
After building, the executable is at:
```
zig-out/bin/zoop-codegen
```

---

## Type Reference

### Class Definition Structure

```zig
const MyClass = zoop.class(struct {
    // OPTIONAL: Inheritance
    pub const extends = ParentClass;
    
    // OPTIONAL: Properties (planned feature)
    pub const properties = .{
        .propName = .{
            .type = T,
            .access = .read_write,  // or .read_only
            .default = value,
        },
    };
    
    // Fields
    field1: Type1,
    field2: Type2,
    
    // Methods
    pub fn method(self: *MyClass) ReturnType {
        // Implementation
    }
    
    // Static methods (no self parameter)
    pub fn staticMethod() ReturnType {
        // Implementation
    }
    
    // Constants
    pub const CONSTANT = value;
});
```

### Memory Layout

After code generation, a child class has this layout:

```
┌─────────────────────────────────┐
│ Parent Fields                    │  ← At offset 0 (never reordered)
│ (in declaration order)           │
├─────────────────────────────────┤
│ Child Fields                     │  ← Sorted by alignment
│ (sorted for efficiency)          │
└─────────────────────────────────┘
```

This ensures:
- `@ptrCast` from child to parent is always safe
- Parent fields have stable offsets
- Child fields are optimized for minimal padding

---

## Error Messages

### Dependency Not Found

```
═══════════════════════════════════════════════════════════════════════
  ERROR: Zoop dependency not found!
═══════════════════════════════════════════════════════════════════════

  Make sure zoop is listed in your build.zig.zon:

    .dependencies = {
        .zoop = .{
            .url = "https://github.com/user/zoop/archive/main.tar.gz",
            .hash = "...",
        },
    }

═══════════════════════════════════════════════════════════════════════
```

### Code Generator Not Built

```
═══════════════════════════════════════════════════════════════════════
  ERROR: zoop-codegen executable not found!
═══════════════════════════════════════════════════════════════════════

  Zoop requires the 'zoop-codegen' tool to generate class code.

  To fix this, you need to build zoop-codegen first:

    1. Navigate to your zoop dependency directory:
       cd .zig-cache/*/zoop-*/

    2. Build the code generator:
       zig build codegen

    3. Return to your project and build again:
       zig build

═══════════════════════════════════════════════════════════════════════
```

---

## Best Practices

### Naming Conventions

```zig
// Classes: PascalCase
const MyClass = zoop.class(struct { ... });

// Methods: camelCase
pub fn myMethod(self: *MyClass) void { }

// Fields: snake_case or camelCase (your choice)
my_field: u32,
// or
myField: u32,
```

### Prefix Configuration

**For maximum clarity**, use descriptive prefixes:
```zig
zoop.build(b, exe, .{
    .method_prefix = "call_",
    .getter_prefix = "get_",
    .setter_prefix = "set_",
});
```

**For minimal syntax**, use no prefixes:
```zig
zoop.build(b, exe, .{
    .method_prefix = "",
    .getter_prefix = "",
    .setter_prefix = "",
});
```

**For domain-specific naming**, use custom prefixes:
```zig
zoop.build(b, exe, .{
    .method_prefix = "invoke_",
    .getter_prefix = "read_",
    .setter_prefix = "write_",
});
```

### Error Handling

Always use Zig's error handling:
```zig
pub fn myMethod(self: *MyClass) !void {
    // Can fail
}

// Usage:
try obj.call_myMethod();
```

---

## Migration Guide

### From Manual Composition

**Before:**
```zig
const Child = struct {
    parent: Parent,
    child_field: u32,
    
    pub fn parentMethod(self: *Child) void {
        self.parent.parentMethod();
    }
};
```

**After:**
```zig
const Child = zoop.class(struct {
    pub const extends = Parent;
    child_field: u32,
});

// Usage:
child.call_parentMethod();  // Automatic!
```

### From Manual Getters/Setters

**Before:**
```zig
const MyClass = struct {
    _value: u32,
    
    pub fn getValue(self: *MyClass) u32 {
        return self._value;
    }
    
    pub fn setValue(self: *MyClass, v: u32) void {
        self._value = v;
    }
};
```

**After (planned):**
```zig
const MyClass = zoop.class(struct {
    pub const properties = .{
        .value = .{ .type = u32, .access = .read_write, .default = 0 },
    };
});

// get_value() and set_value() generated automatically!
```
