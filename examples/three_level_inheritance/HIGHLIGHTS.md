# Three-Level Inheritance: Key Highlights

## The Problem This Solves

When using traditional code generation with inheritance, child classes either:
1. **Duplicate parent logic** - Violates DRY principle, hard to maintain
2. **Lose custom logic** - Only field initialization is inherited

Zoop's `initFields` pattern solves this by **separating concerns**.

## The Solution: initFields Pattern

### Two-Method Approach

Every class with custom initialization has TWO methods:

```zig
// 1. init - Contains custom logic (validation, logging, business rules)
pub fn init(allocator: Allocator, params...) !Type {
    // Your custom logic here
    if (invalid_condition) return error.ValidationFailed;
    
    // Delegate to initFields
    return try Type.initFields(allocator, .{ ...fields... });
}

// 2. initFields - Pure field initialization (generated per-class)
fn initFields(allocator: Allocator, fields: struct { ...all_fields... }) !Type {
    return .{
        .allocator = allocator,
        .field1 = fields.field1,
        .field2 = try allocator.dupe(u8, fields.field2), // Auto-allocated
        // ... etc
    };
}
```

## Three-Level Example

### Input Code (What You Write)

```zig
// Level 1: Entity (base class)
pub const Entity = zoop.class(struct {
    pub const properties = .{
        .id = .{ .type = u64, .access = .read_only },
    };
    
    pub fn init(allocator: Allocator, id: u64) !Entity {
        if (id == 0) return error.InvalidId;           // ← Custom validation
        if (id > 999999) return error.IdTooLarge;      // ← Custom validation
        std.debug.print("Creating entity {}\n", .{id}); // ← Custom logging
        
        return try Entity.initFields(allocator, .{ .id = id });
    }
    
    fn initFields(allocator: Allocator, fields: struct { id: u64 }) !Entity {
        return .{ .allocator = allocator, .id = fields.id };
    }
});

// Level 2: NamedEntity (adds name field)
pub const NamedEntity = zoop.class(struct {
    pub const extends = Entity;
    name: []const u8,  // ← Just declare new field
});

// Level 3: User (adds email property and active field)
pub const User = zoop.class(struct {
    pub const extends = NamedEntity;
    pub const properties = .{
        .email = .{ .type = []const u8, .access = .read_write },
    };
    active: bool,  // ← Just declare new fields
});
```

### Generated Code (What Zoop Creates)

**NamedEntity automatically gets:**
```zig
pub fn init(allocator: Allocator, id: u64, name: []const u8) !NamedEntity {
    // ✅ Entity's validation copied verbatim!
    if (id == 0) return error.InvalidId;
    if (id > 999999) return error.IdTooLarge;
    std.debug.print("Creating entity {}\n", .{id});
    
    // ✅ Call updated to use NamedEntity.initFields
    return try NamedEntity.initFields(allocator, .{
        .id = id,
        .name = name,  // ✅ Child's field added
    });
}

// ✅ New initFields with name included
fn initFields(allocator: Allocator, fields: struct { id: u64, name: []const u8 }) !NamedEntity {
    return .{
        .allocator = allocator,
        .id = fields.id,
        .name = try allocator.dupe(u8, fields.name),  // ✅ Auto-allocated!
    };
}

// ✅ Auto-generated deinit
pub fn deinit(self: *NamedEntity) void {
    self.allocator.free(self.name);  // ✅ Auto-freed!
}
```

**User automatically gets (2 levels deep!):**
```zig
pub fn init(allocator: Allocator, id: u64, name: []const u8, active: bool, email: []const u8) !User {
    // ✅ STILL has Entity's validation from 2 levels up!
    if (id == 0) return error.InvalidId;
    if (id > 999999) return error.IdTooLarge;
    std.debug.print("Creating entity {}\n", .{id});
    
    return try User.initFields(allocator, .{
        .id = id,        // From Entity
        .name = name,    // From NamedEntity
        .active = active,  // From User
        .email = email,    // From User (property)
    });
}

fn initFields(allocator: Allocator, fields: struct {
    id: u64,
    name: []const u8,
    active: bool,
    email: []const u8,
}) !User {
    return .{
        .allocator = allocator,
        .id = fields.id,
        .name = try allocator.dupe(u8, fields.name),
        .active = fields.active,
        .email = try allocator.dupe(u8, fields.email),
    };
}

pub fn deinit(self: *User) void {
    self.allocator.free(self.name);
    self.allocator.free(self.email);
}
```

## What You Get Automatically

### ✅ 1. Inherited Custom Logic
- Validation rules from base class
- Logging statements
- Error handling
- Any custom business logic

### ✅ 2. Extended initFields
- Struct parameter contains ALL fields (parent + child)
- Automatic string allocation with `allocator.dupe()`
- Clean, typed interface

### ✅ 3. Memory Management
- `deinit()` frees all string fields (including inherited ones)
- `create()` and `destroy()` for heap allocation
- Zero memory leaks

### ✅ 4. Property Accessors
```zig
// Properties generate getters/setters
pub inline fn get_id(self: *const @This()) u64
pub inline fn get_email(self: *const @This()) []const u8
pub inline fn set_email(self: *@This(), value: []const u8) void
```

### ✅ 5. Zero Runtime Overhead
- All methods inlined
- No vtables or function pointers
- Compile-time polymorphism
- Same performance as hand-written code

## Real-World Usage

```zig
var user = try User.init(allocator, 123, "Alice", true, "alice@example.com");
defer user.deinit();

// All validation from Entity applies automatically!
// If id was 0 or > 999999, init would return an error

std.debug.print("User: {s} ({})\n", .{user.name, user.get_id()});
user.set_email("newemail@example.com");
```

## Benefits

| Feature | Traditional OOP | Zoop initFields Pattern |
|---------|----------------|------------------------|
| Inheritance depth | Limited | Unlimited |
| Custom logic inheritance | ❌ Manual duplication | ✅ Automatic |
| Memory safety | ❌ Manual management | ✅ Auto-generated |
| Runtime cost | ⚠️ Vtables, indirection | ✅ Zero overhead |
| Type safety | ⚠️ Runtime errors | ✅ Compile-time |
| Extensibility | ⚠️ Breaks parent logic | ✅ Preserves parent logic |

## Design Patterns Applied

1. **Template Method Pattern** - `init` is the template, `initFields` is customizable
2. **Factory Pattern** - `create()` for heap allocation
3. **RAII** - `init/deinit` for resource management
4. **Composition over Inheritance** - Flat field layout, no `super` pointer

## Performance

```zig
// These are IDENTICAL in performance:

// Hand-written
const user = User{
    .allocator = allocator,
    .id = 123,
    .name = try allocator.dupe(u8, "Alice"),
    .active = true,
    .email = try allocator.dupe(u8, "alice@example.com"),
};

// Generated via Zoop
const user = try User.init(allocator, 123, "Alice", true, "alice@example.com");
```

Both compile to the same assembly code!

## When to Use This Pattern

✅ **Use initFields pattern when:**
- You have custom validation logic in parent class
- You need consistent initialization behavior across hierarchy
- You want automatic memory management for strings
- You prefer compile-time safety over runtime flexibility

❌ **Don't use when:**
- You don't have inheritance (single class is fine without it)
- Parent init is trivial (just field assignment)
- You need runtime polymorphism (use interfaces instead)

## Summary

The `initFields` pattern gives you:
- **Write once** - Define init logic in base class
- **Inherit forever** - All children get the logic automatically  
- **Extend easily** - Just add fields, logic is preserved
- **Zero cost** - Same performance as hand-written code
- **Type safe** - Compiler catches all errors

This is the power of **compile-time code generation** done right!
