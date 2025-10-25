const std = @import("std");
const zoop = @import("zoop");
const parent = @import("parent.zig");

pub const Child = zoop.class(struct {
    pub const extends = parent.Parent;
    
    value: i32,

    pub fn init(allocator: std.mem.Allocator, name_val: []const u8, val: i32) !Child {
        return Child{
            .super = try parent.Parent.init(allocator, name_val),
            .value = val,
        };
    }
});
