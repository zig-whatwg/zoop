# Three-Level Inheritance Example

This example demonstrates Zoop's `initFields` pattern with three levels of inheritance, showing how custom initialization logic is preserved across all child classes.

## Architecture

```
Entity (Level 1)
  ├─ Has: id (property)
  ├─ Custom init: Validates id (must be > 0 and <= 999999)
  └─ Uses: initFields pattern
     
NamedEntity (Level 2) extends Entity
  ├─ Adds: name (string field)
  ├─ Inherits: Entity's validation logic
  └─ Extends: initFields with name parameter
     
User (Level 3) extends NamedEntity
  ├─ Adds: email (property), active (boolean field)
  ├─ Inherits: Entity's validation logic from 2 levels up!
  └─ Extends: initFields with email and active parameters
```

## Key Features Demonstrated

### 1. Custom Init Logic Preserved

The `Entity.init` contains validation:
```zig
if (id == 0) return error.InvalidId;
if (id > 999999) return error.IdTooLarge;
```

This **same validation** appears in:
- `Entity.init` (original)
- `NamedEntity.init` (inherited)
- `User.init` (inherited through 2 levels!)

### 2. initFields Pattern

Each class has two methods:

**`init`** - Contains business logic:
```zig
pub fn init(allocator: Allocator, id: u64) !Entity {
    // Validation, logging, business rules
    if (id == 0) return error.InvalidId;
    
    // Delegate to initFields
    return try Entity.initFields(allocator, .{ .id = id });
}
```

**`initFields`** - Handles field initialization:
```zig
fn initFields(allocator: Allocator, fields: struct { id: u64 }) !Entity {
    return .{
        .allocator = allocator,
        .id = fields.id,
    };
}
```

### 3. Fields Struct Parameter

Each `initFields` takes a struct containing ALL fields:

- **Entity**: `struct { id: u64 }`
- **NamedEntity**: `struct { id: u64, name: []const u8 }`
- **User**: `struct { id: u64, name: []const u8, email: []const u8, active: bool }`

This keeps the signature clean and extensible.

### 4. Automatic String Management

String fields are automatically duplicated:
```zig
.name = try allocator.dupe(u8, fields.name),
.email = try allocator.dupe(u8, fields.email),
```

And freed in `deinit`:
```zig
pub fn deinit(self: *User) void {
    self.allocator.free(self.name);
    self.allocator.free(self.email);
}
```

### 5. Property Getters/Setters

Properties generate accessor methods:
```zig
pub inline fn get_id(self: *const @This()) u64 {
    return self.id;
}

pub inline fn set_email(self: *@This(), value: []const u8) void {
    self.email = value;
}
```

## Files

- **`input.zig`** - Source code with `zoop.class()` declarations
- **`output/input.zig`** - Generated code with full implementation
- **`usage_example.zig`** - Demo showing inheritance in action
- **`README.md`** - This file

## Running the Example

```bash
# Generate the code
./zig-out/bin/zoop-codegen \
  --source-dir examples/three_level_inheritance \
  --output-dir examples/three_level_inheritance/output

# Run the usage example
zig run examples/three_level_inheritance/usage_example.zig
```

## Expected Output

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

## Code Comparison

### Before (input.zig)

```zig
// Level 1: Entity with custom validation
pub const Entity = zoop.class(struct {
    pub const properties = .{
        .id = .{ .type = u64, .access = .read_only },
    };
    
    pub fn init(allocator: Allocator, id: u64) !Entity {
        if (id == 0) return error.InvalidId;
        if (id > 999999) return error.IdTooLarge;
        return try Entity.initFields(allocator, .{ .id = id });
    }
    
    fn initFields(allocator: Allocator, fields: struct { id: u64 }) !Entity {
        return .{ .allocator = allocator, .id = fields.id };
    }
});

// Level 2: Just adds name field
pub const NamedEntity = zoop.class(struct {
    pub const extends = Entity;
    name: []const u8,
});

// Level 3: Adds email property and active field
pub const User = zoop.class(struct {
    pub const extends = NamedEntity;
    pub const properties = .{
        .email = .{ .type = []const u8, .access = .read_write },
    };
    active: bool,
});
```

### After (output/input.zig)

All three classes get:
- ✅ Flattened fields from ancestors
- ✅ Inherited validation logic
- ✅ Extended `initFields` with child fields
- ✅ Automatic memory management (`deinit`)
- ✅ Property getters/setters
- ✅ Helper methods (`create`, `destroy`)

**NamedEntity gets Entity's validation:**
```zig
pub fn init(allocator: Allocator, id: u64, name: []const u8) !NamedEntity {
    // This validation came from Entity!
    if (id == 0) return error.InvalidId;
    if (id > 999999) return error.IdTooLarge;
    
    return try NamedEntity.initFields(allocator, .{
        .id = id,
        .name = name,  // Child's field added here
    });
}
```

**User gets Entity's validation (2 levels up!):**
```zig
pub fn init(allocator: Allocator, id: u64, name: []const u8, active: bool, email: []const u8) !User {
    // Still has Entity's validation!
    if (id == 0) return error.InvalidId;
    if (id > 999999) return error.IdTooLarge;
    
    return try User.initFields(allocator, .{
        .id = id,
        .name = name,
        .active = active,
        .email = email,  // All fields in one struct
    });
}
```

## Benefits

1. **DRY (Don't Repeat Yourself)**: Validation logic written once in `Entity`
2. **Type Safety**: Compiler checks all field initializations
3. **Zero Overhead**: All methods inlined, no vtables or runtime dispatch
4. **Memory Safe**: Automatic string duplication and cleanup
5. **Clean API**: Struct parameter keeps signatures manageable
6. **Extensible**: Easy to add fields without breaking parent logic

## Design Pattern

This demonstrates the **Template Method Pattern** at compile-time:
- `init` is the template (contains shared algorithm)
- `initFields` is the customization point (varies per class)
- No runtime cost - everything is inlined and optimized

The `initFields` pattern separates:
- **What to do** (validation, logging) - stays in `init`
- **What to create** (field initialization) - varies in `initFields`
