const std = @import("std");
const zoop = @import("zoop");
const parent = @import("parent.zig");

pub const Child = zoop.class(struct {
    pub const extends = parent.Parent;

    value: i32,

    // Child inherits init from Parent and adds value parameter
    // Generated init will be: init(allocator, name_val, value) !Child
    // No need to manually define init - codegen creates it automatically
});
