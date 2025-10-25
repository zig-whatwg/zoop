const std = @import("std");
const zoop = @import("zoop");

pub const BadLayout = zoop.class(struct {
    flag: bool,
    count: u64,
    tiny: u8,
    data: []const u8,
    small: u16,
    big: u64,
});

pub const Child = zoop.class(struct {
    pub const extends = BadLayout;

    a: bool,
    b: u64,
    c: u8,
    d: []const u8,
});
