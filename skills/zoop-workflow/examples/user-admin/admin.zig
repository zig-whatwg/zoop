const std = @import("std");
const zoop = @import("zoop");
const User = @import("user.zig").User;

pub const Admin = zoop.class(struct {
    pub const extends = User;

    role: []const u8,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, email: []const u8, role: []const u8) !Admin {
        return Admin.initFields(allocator, &.{
            .name = name,
            .email = email,
            .role = role,
        });
    }

    pub fn deinit(self: *Admin) void {
        self.allocator.free(self.name);
        self.allocator.free(self.email);
        self.allocator.free(self.role);
    }

    pub fn manageUsers(self: *Admin) void {
        std.debug.print("Admin {s} managing users\n", .{self.name});
    }
});
