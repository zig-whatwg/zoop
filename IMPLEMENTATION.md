# Zoop Implementation Architecture

## Overview

Zoop uses **build-time code generation** to implement inheritance in Zig via flattened fields and method copying.

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

## Inheritance via Flattened Fields

### The Pattern

Parent and mixin fields are **flattened** directly into child struct:

```zig
// User writes:
const Child = zoop.class(struct {
    pub const extends = Parent;
    child_field: u32,
});

// We generate:
const Child = struct {
    parent_field: []const u8,  // ✅ From Parent (flattened)
    child_field: u32,
    
    // ✅ Copied parent methods (type rewritten)
    pub fn parent_method(self: *Child) void {
        std.debug.print("{s}\n", .{self.parent_field});
    }
};
```

### Why This Works

1. **Type-safe**: Zig's type system validates everything
2. **Natural**: Direct field access like traditional OOP
3. **Zero overhead**: Methods copied, not delegated
4. **Consistent**: Parents and mixins work identically

---

## Method Copying

### Direct Method Copy

Parent methods are copied with type rewriting:

```zig
// Parent method:
pub fn method(self: *Parent) void { ... }

// Copied to child with type rewritten:
pub fn method(self: *Child) void { ... }
```

### Multi-Level Inheritance

Methods from all ancestors are copied:

```zig
// Grandparent, Parent, and Child methods all copied into Child
// Each with *Child type in signature
```

### Override Detection

```zig
// Parent has: method1(), method2()
// Child has: method2()

// Generated methods:
pub fn method1(self: *Child) { ... }  // ✅ Copied from parent
// method2 NOT copied - child has its own implementation
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
    pub const extends = Vehicle;
    num_doors: u8,
    pub fn honk(self: *Car) void { ... }
});

const ElectricCar = zoop.class(struct {
    pub const extends = Car;
    battery: f32,
});
```

### Generated Structure

```zig
// Vehicle: no changes
const Vehicle = struct { 
    brand: []const u8,
    pub fn start(self: *Vehicle) void { ... }
};

// Car: flattens Vehicle fields, copies methods
const Car = struct {
    brand: []const u8,  // From Vehicle (flattened)
    num_doors: u8,
    
    pub fn start(self: *Car) void { ... }  // Copied from Vehicle
    pub fn honk(self: *Car) void { ... }
};

// ElectricCar: flattens all ancestor fields, copies all methods
const ElectricCar = struct {
    brand: []const u8,  // From Vehicle (flattened)
    num_doors: u8,      // From Car (flattened)
    battery: f32,
    
    pub fn start(self: *ElectricCar) void { ... }  // Copied from Vehicle
    pub fn honk(self: *ElectricCar) void { ... }   // Copied from Car
};
```

### Access Patterns

```zig
var tesla = ElectricCar{
    .brand = "Tesla",     // Direct access
    .num_doors = 4,       // Direct access
    .battery = 100.0,
};

// Field access - all direct:
tesla.brand      // ✅ "Tesla"
tesla.num_doors  // ✅ 4
tesla.battery    // ✅ 100.0

// Method access - all copied:
tesla.start()    // ✅ Copied from Vehicle
tesla.honk()     // ✅ Copied from Car
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
// First, flatten all parent fields
for (parent_fields) |field| {
    try writer.print("    {s}: {s},\n", .{field.name, field.type_name});
}

// Then child's own fields
for (parsed.fields) |field| {
    try writer.print("    {s}: {s},\n", .{field.name, field.type_name});
}
```

### Method Copying

```zig
// For each parent method not overridden by child:
// Copy the method with type rewriting
const rewritten = rewriteMixinMethod(method.source, parent_type, child_type);
try writer.print("    {s}\n", .{rewritten});
```

Where:
- Method source code is copied verbatim
- All type references to parent are replaced with child type
- E.g., `self: *Parent` becomes `self: *Child`

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

## Comparison to Evolution

| Aspect | v0.1.0 (Embedded) | v0.2.0 (Flattened) |
|--------|-------------------|-------------------|
| Approach | Build-time codegen | Build-time codegen ✅ |
| Fields | Embedded super struct | Flattened parent fields ✅ |
| Field access | self.super.field | self.field ✅ |
| Method access | Delegated via super | Copied with rewriting ✅ |
| Mixins | Not supported | Fully supported ✅ |
| Overhead | Minimal (inline) | Zero (copied) ✅ |
| Initialization | .super = Parent{} | .field = value ✅ |

**Result**: v0.2.0 achieves true zero overhead with natural OOP semantics.

---

## Implemented Features

### Complete ✅
- Flattened field inheritance
- Method copying with type rewriting
- Mixin support (multiple inheritance)
- Cross-file inheritance
- Multi-level inheritance
- Override detection
- Init/deinit adaptation
- Property generation
- Circular dependency detection
- Path traversal protection

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
