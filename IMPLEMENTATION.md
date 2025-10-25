# Zoop Implementation Architecture

## Overview

Zoop uses **build-time code generation** to implement inheritance in Zig via embedded parent structs and method forwarding.

---

## Core Architecture

### Build-Time Generation (Not Comptime)

```
User Source Code → zoop-codegen (parse & generate) → Generated Code → Zig Compiler
```

**Why not comptime?**
- `usingnamespace` removed in Zig 0.15
- `@Type()` cannot create methods/declarations
- Build-time gives more control and better error messages

---

## Inheritance via Embedded Structs

### The Pattern

Instead of flattening fields (unsafe), we **embed the parent struct**:

```zig
// User writes:
const Child = zoop.class(struct {
    extends: Parent,
    child_field: u32,
});

// We generate:
const Child = struct {
    super: Parent,      // ✅ Embedded parent
    child_field: u32,
    
    // ✅ Generated wrappers
    pub inline fn call_parent_method(self: *Child) void {
        self.super.parent_method();
    }
};
```

### Why This Works

1. **Type-safe**: No memory layout assumptions
2. **Idiomatic**: Composition over inheritance
3. **Clear**: `self.super` explicitly shows relationship
4. **Safe**: Zig's type system validates everything

---

## Method Forwarding

### Direct Parent Access

For methods that exist in immediate parent:

```zig
pub inline fn call_method(self: *Child) ReturnType {
    return self.super.method();
}
```

### Chained Access

For methods from grandparent:

```zig
pub inline fn call_grandparent_method(self: *Child) ReturnType {
    return self.super.call_grandparent_method();  // Chains through parent
}
```

### Override Detection

```zig
// Parent has: method1(), method2()
// Child has: method2()

// Generated wrappers:
pub inline fn call_method1(...) { ... }  // ✅ Generated
// call_method2 NOT generated - child overrides it
```

---

## Multi-Level Inheritance

### 3-Level Example

```zig
const Vehicle = zoop.class(struct {
    brand: []const u8,
    pub fn start(self: *Vehicle) void { ... }
});

const Car = zoop.class(struct {
    extends: Vehicle,
    num_doors: u8,
    pub fn honk(self: *Car) void { ... }
});

const ElectricCar = zoop.class(struct {
    extends: Car,
    battery: f32,
});
```

### Generated Structure

```zig
// Vehicle: no changes
const Vehicle = struct { brand: []const u8, ... };

// Car: embeds Vehicle
const Car = struct {
    super: Vehicle,
    num_doors: u8,
    
    pub inline fn call_start(self: *Car) void {
        self.super.start();
    }
};

// ElectricCar: embeds Car
const ElectricCar = struct {
    super: Car,
    battery: f32,
    
    pub inline fn call_start(self: *ElectricCar) void {
        self.super.call_start();  // ✅ Chains through Car to Vehicle
    }
    
    pub inline fn call_honk(self: *ElectricCar) void {
        self.super.honk();  // ✅ Direct to Car
    }
};
```

### Access Patterns

```zig
var tesla = ElectricCar{
    .super = Car{
        .super = Vehicle{
            .brand = "Tesla",
        },
        .num_doors = 4,
    },
    .battery = 100.0,
};

// Field access:
tesla.super.super.brand         // ✅ "Tesla"
tesla.super.num_doors           // ✅ 4
tesla.battery                   // ✅ 100.0

// Method access:
tesla.call_start()              // ✅ Chains to Vehicle.start()
tesla.call_honk()               // ✅ Calls Car.honk()
```

---

## Parser Implementation

### AST Parsing Steps

1. **Find class definitions**: Scan for `zoop.class(struct {`
2. **Extract metadata**:
   - Class name from: `const ClassName = zoop.class(`
   - Parent from: `extends: ParentName,`
3. **Parse struct body**:
   - Fields: `name: type,`
   - Methods: `pub fn name(...) {...}`
4. **Build class registry**: Map class name → ClassInfo
5. **Detect circular inheritance**: Validate no cycles

### Method Signature Parsing

```zig
pub fn methodName(self: *Type, param: u32) !bool
                  ^^^^^^^^^^^^^^^^^^^^^^^^^  ^^^^
                  Signature                   Return type
```

Extract:
- Parameter names (not types) for forwarding
- Return type for wrapper signature
- Error union handling

---

## Code Generation

### Field Generation

```zig
// Parent exists → add super field first
if (parsed.parent_name) |parent| {
    try writer.print("    super: {s},\n", .{parent});
}

// Then child's own fields
for (parsed.fields) |field| {
    try writer.print("    {s}: {s},\n", .{field.name, field.type_name});
}
```

### Method Wrapper Generation

```zig
// For each parent method not overridden by child:
pub inline fn {prefix}{method_name}{signature} {return_type} {
    {return_prefix}self.super.{actual_method_name}({params});
}
```

Where:
- `prefix` = configured (e.g., `call_`)
- `signature` = full param list with types
- `return_prefix` = `"return "` if non-void, else `""`
- `actual_method_name` = direct if in parent, else `call_` version for chaining
- `params` = comma-separated parameter names only

---

## Circular Inheritance Detection

### Algorithm

```zig
fn detectCircular(class_name, parent_name, registry, visited) {
    visited.add(class_name);
    
    current = parent_name;
    while (current) {
        if (visited.contains(current)) {
            ERROR: "Circular inheritance: {class_name} -> {current}"
        }
        visited.add(current);
        current = registry[current].parent_name;
    }
}
```

### Example Detection

```zig
A extends C
B extends A
C extends B  // ❌ Error: Circular inheritance detected: C -> C
```

---

## Performance Characteristics

### Zero Runtime Cost

- All wrappers are `inline` → no function call overhead
- `super` field is embedded → no pointer indirection
- Everything resolved at compile time

### Memory Layout

```zig
const Child = struct {
    super: Parent,    // Parent's full size (inline)
    child_field: u32,
};

// sizeof(Child) = sizeof(Parent) + sizeof(child_field) + padding
```

No extra pointers, no vtables, no runtime dispatch.

---

## Limitations

### Current Implementation Gaps

1. **Properties**: Infrastructure exists but parsing not implemented
2. **Mixins**: Not implemented at all
3. **Cross-file**: Parent and child must be in same file
4. **Init chains**: Must be written manually
5. **Field optimization**: Fields not sorted by alignment

### Architectural Limitations

1. **No polymorphism**: Each type is distinct, no runtime type info
2. **No dynamic dispatch**: All calls resolved statically
3. **Explicit nesting**: Must initialize `super` field explicitly
4. **Single file**: No cross-file inheritance (yet)

---

## Comparison to Original Plan

| Aspect | Original Plan | Actual Implementation |
|--------|---------------|----------------------|
| Approach | Comptime with @Type() | Build-time codegen |
| Fields | Flattened with @ptrCast | Embedded super struct |
| Method access | self.super.method() | self.super.method() ✅ |
| Code generation | Impossible (usingnamespace) | Works ✅ |
| Type safety | Unsafe (@ptrCast) | Safe (embedded) ✅ |
| Zig compatibility | Fails on 0.15+ | Works on 0.15+ ✅ |

**Result**: Implementation is more correct and safer than original plan.

---

## Future Enhancements

### Priority 1 (Next Month)
- Implement property parsing
- Implement mixin system
- Better error messages

### Priority 2 (Next Quarter)
- Cross-file inheritance support
- Init/deinit chain generation
- Field alignment optimization
- Static method detection

### Priority 3 (Future)
- Polymorphism via interfaces
- Generic class support
- Reflection/introspection helpers

---

## Contributing

When adding features, maintain these principles:

1. **Type safety first**: No unsafe casts or assumptions
2. **Explicit over implicit**: Clear what's happening
3. **Build-time generation**: Don't try to be too clever with comptime
4. **Test thoroughly**: Especially multi-level scenarios
5. **Document clearly**: Update this file when architecture changes

See [CRITICAL_ISSUES.md](CRITICAL_ISSUES.md) for current task list.
