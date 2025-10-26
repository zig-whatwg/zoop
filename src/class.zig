//! Core class marker and configuration types for Zoop.
//!
//! This module provides the runtime components that work alongside the
//! build-time code generator. The `class()` function serves as both a
//! marker for codegen and a type validator during source parsing.

const std = @import("std");

/// Configuration for generated method and property naming.
///
/// This struct defines the prefixes used when generating wrapper methods
/// for inherited methods and property accessors. These settings are passed
/// to `zoop-codegen` via command-line arguments in your build.zig.
///
/// ## Fields
///
/// - `method_prefix` - Prefix for inherited method wrappers (default: "call_")
/// - `getter_prefix` - Prefix for property getters (default: "get_")
/// - `setter_prefix` - Prefix for property setters (default: "set_")
///
/// ## Default Behavior
///
/// With default prefixes, generated code looks like:
///
/// ```zig
/// const Employee = struct {
///     super: Person,
///
///     // Inherited method wrapper
///     pub inline fn call_greet(self: *Employee) void {
///         self.super.greet();
///     }
/// };
///
/// const User = struct {
///     email: []const u8,
///
///     // Property accessors
///     pub inline fn get_email(self: *const User) []const u8 { return self.email; }
///     pub inline fn set_email(self: *User, value: []const u8) void { self.email = value; }
/// };
/// ```
///
/// ## Customization
///
/// Set custom prefixes in build.zig:
///
/// ```zig
/// gen_cmd.addArgs(&.{
///     "--method-prefix", "invoke_",  // employee.invoke_greet()
///     "--getter-prefix", "read_",    // user.read_email()
///     "--setter-prefix", "write_",   // user.write_email(...)
/// });
/// ```
///
/// Or use empty prefixes for no prefix:
///
/// ```zig
/// gen_cmd.addArgs(&.{
///     "--method-prefix", "",  // employee.greet()
///     "--getter-prefix", "",  // user.email()
///     "--setter-prefix", "",  // user.email(...)
/// });
/// ```
///
/// ## Notes
///
/// - Prefixes help avoid naming conflicts between your methods and generated ones
/// - Empty prefixes are valid but can cause collisions if you have methods
///   with the same names as parent methods
/// - This struct is for documentation only; actual configuration happens
///   via command-line arguments to `zoop-codegen`
pub const ClassConfig = struct {
    method_prefix: []const u8 = "call_",
    getter_prefix: []const u8 = "get_",
    setter_prefix: []const u8 = "set_",
};

/// Mark a struct for code generation with OOP features.
///
/// This is the primary API for Zoop. It serves two purposes:
///
/// 1. **Build-time marker** - The `zoop-codegen` tool scans source files
///    for `zoop.class(...)` calls to identify classes that need generation
///
/// 2. **Parse-time type stub** - Returns a minimal valid type so your source
///    files can be parsed and type-checked during the codegen scan phase
///
/// ## Usage
///
/// ### Basic Class
///
/// ```zig
/// const Person = zoop.class(struct {
///     name: []const u8,
///     age: u32,
///
///     pub fn greet(self: *Person) void {
///         std.debug.print("Hello, I'm {s}\n", .{self.name});
///     }
/// });
/// ```
///
/// ### With Inheritance
///
/// Use `pub const extends = ParentClass` to declare a parent:
///
/// ```zig
/// const Employee = zoop.class(struct {
///     pub const extends = Person,  // Inheritance declaration
///
///     employee_id: u32,
///
///     pub fn work(self: *Employee) void {
///         // Access parent fields via super
///         std.debug.print("{s} is working\n", .{self.super.name});
///     }
/// });
/// ```
///
/// ### With Properties
///
/// Declare properties for automatic getter/setter generation:
///
/// ```zig
/// const User = zoop.class(struct {
///     pub const properties = .{
///         .email = .{
///             .type = []const u8,
///             .access = .read_write,  // Generates get_ and set_
///         },
///         .id = .{
///             .type = u64,
///             .access = .read_only,   // Generates get_ only
///         },
///     };
///
///     name: []const u8,  // Regular field
/// });
/// ```
///
/// ## What Gets Generated
///
/// For classes with parents, `zoop-codegen` generates:
///
/// 1. **Embedded parent field:**
///    ```zig
///    super: ParentType,
///    ```
///
/// 2. **Wrapper methods** for inherited methods (unless overridden):
///    ```zig
///    pub inline fn call_parentMethod(self: *ChildType, args...) ReturnType {
///        return self.super.parentMethod(args);
///    }
///    ```
///
/// 3. **Property accessors** based on the `properties` declaration:
///    ```zig
///    pub inline fn get_propertyName(self: *const Type) PropertyType {
///        return self.propertyName;
///    }
///    pub inline fn set_propertyName(self: *Type, value: PropertyType) void {
///        self.propertyName = value;
///    }
///    ```
///
/// All generated methods are `inline`, resulting in zero runtime overhead.
///
/// ## Important Notes
///
/// - This function returns a **temporary type stub** for parsing only
/// - The **real** enhanced struct is generated by `zoop-codegen` at build time
/// - Your build must compile from the generated code, not the source
/// - See CONSUMER_USAGE.md for complete integration instructions
///
/// ## Return Value
///
/// Returns a type that:
/// - If `extends` is declared: merges parent and child fields for valid parsing
/// - If no parent: returns the definition as-is
///
/// This allows source files to be parsed and analyzed without compilation errors,
/// even though the final enhanced struct will be different.
///
/// ## Examples
///
/// See:
/// - README.md for quick examples
/// - CONSUMER_USAGE.md for integration patterns
/// - test_consumer/ for a complete working project
/// - tests/ for comprehensive usage examples
pub fn class(comptime definition: type) type {
    // Check if class has custom configuration (currently unused, but reserved for future features)
    const config = if (@hasDecl(definition, "config"))
        definition.config
    else
        ClassConfig{};

    _ = config; // Reserved for future use

    // Check for inheritance or mixins and merge fields if needed
    if (@hasDecl(definition, "extends") or @hasDecl(definition, "mixins")) {
        const Parent = if (@hasDecl(definition, "extends")) definition.extends else null;
        const mixins = if (@hasDecl(definition, "mixins")) definition.mixins else .{};
        return mergeFields(Parent, mixins, definition);
    } else {
        // No inheritance or mixins - return definition as-is
        return definition;
    }
}

/// Merge parent, mixin, and child struct fields to create a valid compile-time type.
///
/// This function is ONLY used during the codegen scan phase to ensure source
/// files parse correctly without errors. It creates a temporary struct type
/// that combines parent, mixin, and child fields.
///
/// **Important:** The actual runtime code generated by `zoop-codegen` does NOT
/// use this merged type. Instead, it creates a struct with a `super` field
/// that embeds the parent struct and flattened mixin fields.
///
/// ## Why This Exists
///
/// When scanning source files, `zoop-codegen` needs to parse and analyze Zig
/// code to extract class definitions. If child classes referenced parent or mixin
/// fields (e.g., `self.parent_field` or `self.mixin_field`) without this merge,
/// the Zig parser would reject the source files as invalid.
///
/// By returning a merged type here, we ensure source files are syntactically
/// valid during parsing, even though the final generated code uses a different
/// structure (`super` field for parent, flattened fields for mixins).
///
/// ## Parameters
///
/// - `ParentType` - The parent struct type (from `extends` declaration), or null
/// - `mixins` - Tuple of mixin types (from `mixins` declaration), or empty tuple
/// - `ChildDef` - The child struct definition passed to `zoop.class()`
///
/// ## Returns
///
/// A new struct type containing all fields from parent, mixins, and child, with
/// parent fields first, then mixin fields, then child fields.
///
/// ## Example
///
/// ```zig
/// // Parent
/// const Person = struct { name: []const u8, age: u32 };
///
/// // Mixins
/// const Timestamped = struct { created_at: i64, updated_at: i64 };
///
/// // Child definition
/// const Employee = struct { employee_id: u32 };
///
/// // mergeFields(Person, .{Timestamped}, Employee) returns:
/// struct {
///     name: []const u8,      // From parent
///     age: u32,              // From parent
///     created_at: i64,       // From mixin
///     updated_at: i64,       // From mixin
///     employee_id: u32,      // From child
/// }
/// ```
///
/// **But the actual generated code will have:**
/// ```zig
/// struct {
///     super: Person,         // Embedded parent
///     created_at: i64,       // Flattened mixin field
///     updated_at: i64,       // Flattened mixin field
///     employee_id: u32,
/// }
/// ```
fn mergeFields(comptime ParentType: ?type, comptime mixins: anytype, comptime ChildDef: type) type {
    const child_info = @typeInfo(ChildDef);
    const child_struct = child_info.@"struct";

    // Calculate total field count
    var total_fields: usize = child_struct.fields.len;

    // Add parent fields if present
    const parent_field_count = if (ParentType) |P| blk: {
        const parent_info = @typeInfo(P);
        break :blk parent_info.@"struct".fields.len;
    } else 0;
    total_fields += parent_field_count;

    // Add mixin fields
    const mixins_info = @typeInfo(@TypeOf(mixins));
    const mixin_field_count = if (mixins_info == .@"struct" and mixins_info.@"struct".is_tuple) blk: {
        var count: usize = 0;
        inline for (mixins) |MixinType| {
            const mixin_info = @typeInfo(MixinType);
            count += mixin_info.@"struct".fields.len;
        }
        break :blk count;
    } else 0;
    total_fields += mixin_field_count;

    // Build the field array
    var all_fields: [total_fields]std.builtin.Type.StructField = undefined;
    var idx: usize = 0;

    // Copy parent fields first
    if (ParentType) |P| {
        const parent_info = @typeInfo(P);
        const parent_struct = parent_info.@"struct";
        inline for (parent_struct.fields) |field| {
            all_fields[idx] = field;
            idx += 1;
        }
    }

    // Copy mixin fields
    if (mixins_info == .@"struct" and mixins_info.@"struct".is_tuple) {
        inline for (mixins) |MixinType| {
            const mixin_info = @typeInfo(MixinType);
            const mixin_struct = mixin_info.@"struct";
            inline for (mixin_struct.fields) |field| {
                all_fields[idx] = field;
                idx += 1;
            }
        }
    }

    // Append child fields
    inline for (child_struct.fields) |field| {
        all_fields[idx] = field;
        idx += 1;
    }

    // Construct merged struct type
    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &all_fields,
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });
}

test "ClassConfig defaults" {
    const config = ClassConfig{};
    try std.testing.expectEqualStrings("call_", config.method_prefix);
    try std.testing.expectEqualStrings("get_", config.getter_prefix);
    try std.testing.expectEqualStrings("set_", config.setter_prefix);
}

test "class returns definition for simple struct" {
    const Simple = class(struct {
        value: i32,
    });

    const instance = Simple{ .value = 42 };
    try std.testing.expectEqual(@as(i32, 42), instance.value);
}

test "class merges fields for inheritance" {
    const Parent = struct {
        parent_field: i32,
    };

    const Child = class(struct {
        pub const extends = Parent;
        child_field: i32,
    });

    // Merged type should have both fields
    const instance = Child{
        .parent_field = 10,
        .child_field = 20,
    };

    try std.testing.expectEqual(@as(i32, 10), instance.parent_field);
    try std.testing.expectEqual(@as(i32, 20), instance.child_field);
}
