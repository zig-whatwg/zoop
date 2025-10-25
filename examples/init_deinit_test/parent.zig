const std = @import("std");
const zoop = @import("zoop");

pub const Parent = zoop.class(struct {
    name: []const u8,

    pub fn init(allocator: std.mem.Allocator, name_val: []const u8) !Parent {
        const name_copy = try allocator.dupe(u8, name_val);
        return Parent{ .name = name_copy };
    }

    pub fn deinit(self: *Parent, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
});
