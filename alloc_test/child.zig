const std = @import("std");
const zoop = @import("zoop");
const Parent = @import("parent.zig").Parent;

pub const Child = zoop.class(struct {
    pub const extends = Parent;
    childField: u32,
});
