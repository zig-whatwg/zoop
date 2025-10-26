const std = @import("std");
const zoop = @import("zoop");

// Define mixins using zoop.mixin()
pub const Timestamped = zoop.mixin(struct {
    created_at: i64,
    updated_at: i64,

    pub fn updateTimestamp(self: *Timestamped) void {
        self.updated_at = std.time.timestamp();
    }

    pub fn getAge(self: *const Timestamped) i64 {
        return std.time.timestamp() - self.created_at;
    }
});

pub const Serializable = zoop.mixin(struct {
    pub fn toJson(self: *const Serializable, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return try allocator.dupe(u8, "{}");
    }
});

// Base class
pub const Entity = zoop.class(struct {
    id: u64,

    pub fn save(self: *Entity) void {
        std.debug.print("Saving entity {}\n", .{self.id});
    }
});

// Class using parent and mixins
pub const User = zoop.class(struct {
    pub const extends = Entity;
    pub const mixins = .{ Timestamped, Serializable };

    name: []const u8,
    email: []const u8,

    pub fn greet(self: *const User) void {
        std.debug.print("Hello, I'm {s}\n", .{self.name});
    }
});
