const std = @import("std");
const zoop = @import("zoop");

pub const Test = zoop.class(struct {
    name: []const u8,
    value: u32,
    
    pub fn greet(self: *Test) void {
        _ = self;
    }
});
