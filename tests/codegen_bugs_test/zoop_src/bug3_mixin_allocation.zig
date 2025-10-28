const std = @import("std");
const zoop = @import("zoop");

pub const StringMixin = zoop.mixin(struct {
    pub const properties = .{
        .encoding = .{
            .type = []const u8,
            .access = .read_only,
        },
    };
});

pub const TextEncoder = zoop.class(struct {
    pub const mixins = .{StringMixin};

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TextEncoder {
        return .{
            .allocator = allocator,
            .encoding = "utf-8",
        };
    }
});
