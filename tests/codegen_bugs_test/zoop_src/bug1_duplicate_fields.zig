const std = @import("std");
const zoop = @import("zoop");

pub const SimpleClass = zoop.class(struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SimpleClass {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SimpleClass) void {
        _ = self;
    }
});
