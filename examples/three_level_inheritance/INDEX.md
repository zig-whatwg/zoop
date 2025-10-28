# Three-Level Inheritance Example - File Guide

This directory contains a complete example of Zoop's `initFields` pattern with three levels of inheritance.

## Quick Start

```bash
# 1. View the input code
cat input.zig

# 2. Generate output
./zig-out/bin/zoop-codegen --source-dir examples/three_level_inheritance --output-dir examples/three_level_inheritance/output

# 3. See what was generated
cat output/input.zig

# 4. Run the demo
zig run examples/three_level_inheritance/usage_example.zig
```

## Files (Read in This Order)

### 1. **SUMMARY.txt** ⭐ START HERE
A visual side-by-side comparison showing:
- What you write (INPUT)
- What Zoop generates (OUTPUT)
- For all three inheritance levels

**Perfect for:** Quick understanding of the pattern

### 2. **input.zig**
The source code you write:
- Entity (base) with custom validation
- NamedEntity (adds name field)
- User (adds email property + active field)

**Shows:** Minimal code needed with inheritance

### 3. **output/input.zig**
The generated code from Zoop:
- Full implementations with inherited logic
- Extended initFields methods
- Auto-generated deinit, create, destroy

**Shows:** What Zoop creates for you

### 4. **usage_example.zig**
Working demo that uses all three levels:
- Creates instances of Entity, NamedEntity, User
- Demonstrates inherited validation
- Shows memory management

**Run:** `zig run examples/three_level_inheritance/usage_example.zig`

### 5. **README.md**
Complete documentation covering:
- Architecture diagram
- Key features
- Code comparison
- Benefits and use cases

**Perfect for:** Deep dive into the design

### 6. **HIGHLIGHTS.md**
Detailed explanation of:
- The problem this solves
- Two-method approach (init + initFields)
- How inheritance works
- Performance characteristics

**Perfect for:** Understanding the "why"

## Visual Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                        INHERITANCE FLOW                          │
└──────────────────────────────────────────────────────────────────┘

Level 1: Entity
┌─────────────────────────────────────────────────────────────────┐
│ Fields:  allocator, id                                          │
│ Init:    Custom validation + logging                            │
│ Pattern: init → initFields(.{ id })                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ extends
                              ▼
Level 2: NamedEntity
┌─────────────────────────────────────────────────────────────────┐
│ Fields:  allocator, id, name                                    │
│ Init:    INHERITED validation + logging                         │
│ Pattern: init → initFields(.{ id, name })                       │
│ New:     Auto-generated deinit() for string field              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ extends
                              ▼
Level 3: User
┌─────────────────────────────────────────────────────────────────┐
│ Fields:  allocator, id, name, email, active                     │
│ Init:    INHERITED validation + logging (2 levels up!)          │
│ Pattern: init → initFields(.{ id, name, email, active })        │
│ New:     deinit() for name + email strings                      │
│ New:     get_email() / set_email() property accessors           │
└─────────────────────────────────────────────────────────────────┘
```

## Key Concepts

### The initFields Pattern

```zig
// Separation of concerns:

init()        → Business logic (validation, logging)
initFields()  → Field initialization (memory allocation)

// Benefits:
- Init logic written ONCE in base class
- initFields varies per class (different fields)
- Children inherit init logic automatically
- Zero runtime overhead
```

### What Gets Generated

For each class with custom init:

1. **Inherited init** - Same validation logic from parent
2. **Extended initFields** - Includes parent + child fields  
3. **Auto deinit** - Frees all string fields
4. **Helper methods** - create(), destroy()
5. **Property accessors** - getters/setters

### Memory Management

```zig
// Strings automatically managed:

// Input:
name: []const u8,

// Generated initFields:
.name = try allocator.dupe(u8, fields.name),  // ✅ Allocated

// Generated deinit:
self.allocator.free(self.name);  // ✅ Freed
```

## Example Output

When you run `usage_example.zig`:

```
=== Three-Level Inheritance Demo ===

--- Level 1: Entity ---
[Entity.init] Creating entity with id=123
Entity ID: 123

--- Level 2: NamedEntity ---
[Entity.init] Creating entity with id=456
NamedEntity ID: 456, Name: Alice

--- Level 3: User ---
[Entity.init] Creating entity with id=789
User ID: 789, Name: Bob, Active: true, Email: bob@example.com

--- Validation Tests ---
✓ Entity validation: error.InvalidId
✓ NamedEntity inherited validation: error.InvalidId
✓ User inherited validation: error.InvalidId
✓ User inherited validation (too large): error.IdTooLarge

=== All validations passed! ===
```

## Performance

All methods are inlined - zero overhead!

```zig
// These have IDENTICAL performance:

// Hand-written
const user = User{
    .allocator = allocator,
    .id = 123,
    .name = try allocator.dupe(u8, "Alice"),
    .active = true,
    .email = try allocator.dupe(u8, "alice@example.com"),
};

// Generated by Zoop
const user = try User.init(allocator, 123, "Alice", true, "alice@example.com");
```

## Comparison to Other Approaches

| Feature | Traditional OOP | Manual Code Gen | Zoop initFields |
|---------|----------------|-----------------|-----------------|
| Write logic once | ❌ | ❌ | ✅ |
| Auto inherit | ⚠️ Runtime | ❌ | ✅ Compile-time |
| Memory safety | Manual | Manual | ✅ Auto |
| Type safety | ⚠️ Runtime | ✅ | ✅ |
| Performance | ⚠️ Indirection | ✅ | ✅ Zero overhead |
| Maintainability | ⚠️ Complex | ⚠️ Brittle | ✅ Robust |

## When to Use This Pattern

✅ **Use when:**
- You have validation or initialization logic to share
- You need type-safe inheritance
- You want zero runtime overhead
- You prefer compile-time safety

❌ **Skip when:**
- Single class with no inheritance
- Trivial init with no custom logic
- Need runtime polymorphism (use interfaces)

## Learn More

- See `README.md` for full documentation
- See `HIGHLIGHTS.md` for design rationale
- See Zoop main docs for more patterns

## Questions?

This pattern demonstrates **compile-time code generation done right**:
- DRY: Logic written once
- Safe: Type-checked at compile time
- Fast: Zero runtime overhead
- Clean: Minimal boilerplate

Enjoy building with Zoop! 🎉
