const std = @import("std");
const zoop = @import("zoop");

pub const User = zoop.class(struct {
    pub const properties = .{
        .email = .{
            .type = []const u8,
            .access = .read_write,
        },
    };

    name: []const u8,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, email: []const u8) !User {
        return User.initFields(allocator, &.{
            .name = name,
            .email = email,
        });
    }

    pub fn deinit(self: *User) void {
        self.allocator.free(self.name);
        self.allocator.free(self.email);
    }

    pub fn authenticate(self: *User, password: []const u8) bool {
        _ = self;
        _ = password;
        // Implementation
        return true;
    }
});
