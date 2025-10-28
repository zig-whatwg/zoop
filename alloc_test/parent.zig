const std = @import("std");
const zoop = @import("zoop");

pub const Parent = zoop.class(struct {
    parentField: []const u8,
});
