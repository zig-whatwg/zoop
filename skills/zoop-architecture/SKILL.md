# Zoop Architecture Skill

## When to use this skill

Load this skill automatically when:
- Explaining Zoop's design to users
- Making architectural decisions
- Understanding how generated code works
- Answering "why" questions about implementation choices
- Modifying core inheritance behavior
- Working on flattened field or method copying logic

## What this skill provides

This skill ensures Claude understands Zoop's unique architecture by:
- Explaining flattened field inheritance (not embedded)
- Demonstrating method copying with type rewriting (not delegation)
- Clarifying mixin implementation (identical to parent inheritance)
- Avoiding outdated patterns (no `.super`, no `@ptrCast`)
- Understanding design evolution (v0.1.0 → v0.2.0)

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

**Define mixins with `zoop.mixin()`:**

```zig
const Timestamped = zoop.mixin(struct {
    created_at: i64,
    updated_at: i64,
    
    pub fn updateTimestamp(self: *Timestamped) void {
        self.updated_at = std.time.timestamp();
    }
});

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

## Common Anti-Patterns to Avoid

### ❌ Using `.super` for Field Access

**The `.super` field was removed in v0.2.0.** All fields are flattened.

```zig
// ❌ WRONG (v0.1.0 style)
const dog = Dog{
    .super = Animal{ .name = "Max", .age = 3 },
    .breed = "Lab",
};
dog.super.name;

// ✅ CORRECT (v0.2.0 style)
const dog = Dog{
    .name = "Max",      // Flattened
    .age = 3,           // Flattened
    .breed = "Lab",
};
dog.name;  // Direct access
```

### ❌ Expecting Method Delegation

Methods are **copied**, not delegated. No function call overhead.

```zig
// ❌ WRONG assumption
// "Generated code calls parent method via @ptrCast"

// ✅ CORRECT reality
// Parent method source is copied with types rewritten:
pub fn eat(self: *Dog) void {  // Was *Animal, now *Dog
    std.debug.print("{s} eating\n", .{self.name});
}
```

### ❌ Treating Mixins Differently Than Parents

Both use identical mechanisms.

```zig
// ✅ CORRECT: Both flattened
const User = struct {
    id: u64,            // From Entity (parent)
    created_at: i64,    // From Timestamped (mixin)
    name: []const u8,   // Own field
};
```

## Quick Reference

**Field Inheritance**: Flattened (grandparent → parent → mixins → child)

**Method Inheritance**: Copied with type rewriting (*Parent → *Child)

**Mixins**: Identical to parents (fields flattened, methods copied)

**Overhead**: Zero (pure code duplication, no delegation)

**Access Pattern**: Direct field access (no `.super`)

**Key Files**: 
- `src/codegen.zig:1260-1295` (field flattening)
- `src/codegen.zig:1390-1395` (method copying)
- `src/codegen.zig:1665-1689` (type rewriting)

## References

- `IMPLEMENTATION.md` - Complete architecture documentation
- `README.md` - User-facing explanation
- Commit `1ca8e4c` - Flattened fields implementation
- Commit `0dab9fc` - Method copying (removed `@ptrCast`)
