const std = @import("std");
const zoop = @import("zoop");

pub const InlineFnClass = zoop.class(struct {
    value: u32,

    pub fn init(value: u32) InlineFnClass {
        return .{ .value = value };
    }

    pub inline fn getValue(self: *const InlineFnClass) u32 {
        return self.value;
    }

    pub inline fn get_encoding(_: *const InlineFnClass) []const u8 {
        return "utf-8";
    }
});
