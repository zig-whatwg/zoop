# Zoop Architecture Skill

## Purpose

Understand how Zoop implements inheritance in Zig using flattened fields and method copying.

## When to Use

- Explaining Zoop's design to users
- Making architectural decisions
- Understanding how generated code works
- Answering "why" questions about implementation choices

## Core Concepts

### 1. Flattened Field Inheritance

**Parent and mixin fields are copied directly into child struct** - no embedding, no `super` field.

```zig
// Source
const Dog = zoop.class(struct {
    pub const extends = Animal;
    breed: []const u8,
});

// Generated
const Dog = struct {
    name: []const u8,   // From Animal (flattened)
    age: u8,            // From Animal (flattened)
    breed: []const u8,  // Own field
};
```

### 2. Method Copying with Type Rewriting

**Parent and mixin methods are copied** with type names rewritten - no delegation, no `@ptrCast`.

```zig
// Animal method
pub fn speak(self: *Animal) void {
    std.debug.print("{s}\n", .{self.name});
}

// Copied to Dog with type rewritten
pub fn speak(self: *Dog) void {
    std.debug.print("{s}\n", .{self.name});
}
```

### 3. Mixins Work Identically

Mixins use the exact same mechanism as parent inheritance:
- Fields: Flattened
- Methods: Copied with type rewriting

```zig
const User = zoop.class(struct {
    pub const extends = Entity;
    pub const mixins = .{ Timestamped, Serializable };
    name: []const u8,
});

// All fields flattened: Entity + Timestamped + Serializable + User
// All methods copied with type rewriting
```

## Key Design Decisions

### Why Flattened (Not Embedded)?

**Before (v0.1.0):**
```zig
const Dog = struct {
    super: Animal,  // Embedded
    breed: []const u8,
};
dog.super.name;  // Awkward access
```

**After (v0.2.0):**
```zig
const Dog = struct {
    name: []const u8,  // Flattened
    age: u8,
    breed: []const u8,
};
dog.name;  // Natural access
```

**Benefits:**
- Natural field access (like traditional OOP)
- No `.super =` required in initialization
- Consistent with mixins
- Cleaner API

### Why Method Copying (Not Delegation)?

**Alternatives considered:**
1. **Delegation via `@ptrCast`**: Has runtime overhead
2. **Inline wrappers**: Still has function call overhead
3. **Method copying**: Zero overhead ✅

**Result:** True zero-overhead inheritance

## Implementation Files

| File | Purpose |
|------|---------|
| `src/codegen.zig:1260-1295` | Field flattening logic |
| `src/codegen.zig:1390-1395` | Method copying logic |
| `src/codegen.zig:1665-1689` | Type rewriting (`rewriteMixinMethod`) |
| `src/class.zig:267-336` | Comptime stub field merging |

## Common Questions

**Q: Why not use `@ptrCast` to treat child as parent?**
A: While technically safe when fields are flattened, method copying has zero overhead. No casting needed.

**Q: How does multi-level inheritance work?**
A: Walk up the hierarchy, collect all ancestor fields, flatten them in order (grandparent → parent → child).

**Q: What about field ordering?**
A: Parent fields first (in inheritance order), then child fields. Consistent and predictable.

**Q: Can I access parent methods?**
A: Yes, but you don't need to! They're copied into the child with the same name (unless overridden).

## Evolution History

| Version | Approach | Access Pattern |
|---------|----------|----------------|
| v0.1.0 | Embedded `super` field | `dog.super.name` |
| v0.2.0 | Flattened fields | `dog.name` ✅ |

The v0.2.0 architecture achieves true zero overhead with natural OOP semantics.

## References

- `IMPLEMENTATION.md` - Complete architecture documentation
- `README.md` - User-facing explanation
- Commit `1ca8e4c` - Flattened fields implementation
- Commit `0dab9fc` - Method copying (removed `@ptrCast`)
