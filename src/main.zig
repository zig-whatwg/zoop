const std = @import("std");

pub fn main() !void {
    std.debug.print("Zoop - Zero-cost OOP for Zig\n", .{});
    std.debug.print("Run 'zig build codegen' to build the code generator\n", .{});
}
