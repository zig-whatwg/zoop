const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Object = struct {
    ref_count: usize = 1,
    allocator: Allocator,
    name: []const u8,
    data: []const u8,

    pub fn create(allocator: Allocator, name: []const u8) !*Object {
        const obj = try allocator.create(Object);
        errdefer allocator.destroy(obj);

        const name_copy = try allocator.dupe(u8, name);
        errdefer allocator.free(name_copy);

        obj.* = .{
            .ref_count = 1,
            .allocator = allocator,
            .name = name_copy,
            .data = &[_]u8{},
        };

        return obj;
    }

    pub fn acquire(self: *Object) void {
        self.ref_count += 1;
    }

    pub fn release(self: *Object) void {
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            self.deinit();
        }
    }

    fn deinit(self: *Object) void {
        self.allocator.free(self.name);
        if (self.data.len > 0) {
            self.allocator.free(self.data);
        }
        self.allocator.destroy(self);
    }

    pub fn setData(self: *Object, data: []const u8) !void {
        if (self.data.len > 0) {
            self.allocator.free(self.data);
        }
        self.data = try self.allocator.dupe(u8, data);
    }
};

test "refcounted object" {
    const allocator = std.testing.allocator;

    const obj = try Object.create(allocator, "test");
    defer obj.release();

    try std.testing.expectEqual(@as(usize, 1), obj.ref_count);
    try std.testing.expectEqualStrings("test", obj.name);

    obj.acquire();
    try std.testing.expectEqual(@as(usize, 2), obj.ref_count);

    obj.release();
    try std.testing.expectEqual(@as(usize, 1), obj.ref_count);
}
