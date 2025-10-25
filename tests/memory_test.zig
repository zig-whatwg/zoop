const std = @import("std");

// Memory leak and allocation tests

pub const AllocatedParent = struct {
    data: []u8,
    count: usize,

    pub inline fn get_count(self: *const @This()) usize {
        return self.count;
    }

    pub fn init(allocator: std.mem.Allocator, size: usize) !AllocatedParent {
        return .{
            .data = try allocator.alloc(u8, size),
            .count = size,
        };
    }

    pub fn deinit(self: *AllocatedParent, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

pub const AllocatedChild = struct {
    super: AllocatedParent,

    count: usize,
    child_data: []u8,

    pub inline fn get_count(self: *const @This()) usize {
        return self.count;
    }

    pub fn init(allocator: std.mem.Allocator, parent_size: usize, child_size: usize) !AllocatedChild {
        return .{
            .super = try AllocatedParent.init(allocator, parent_size),
            .count = parent_size,
            .child_data = try allocator.alloc(u8, child_size),
        };
    }

    pub fn deinit(self: *AllocatedChild, allocator: std.mem.Allocator) void {
        self.super.deinit(allocator);
        allocator.free(self.child_data);
    }
};

test "no memory leaks - simple allocation" {
    const allocator = std.testing.allocator;

    var parent = try AllocatedParent.init(allocator, 100);
    defer parent.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 100), parent.get_count());
    try std.testing.expectEqual(@as(usize, 100), parent.data.len);
}

test "no memory leaks - inherited allocation" {
    const allocator = std.testing.allocator;

    var child = try AllocatedChild.init(allocator, 100, 200);
    defer child.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 100), child.get_count());
    try std.testing.expectEqual(@as(usize, 100), child.super.data.len);
    try std.testing.expectEqual(@as(usize, 200), child.child_data.len);
}

test "no memory leaks - multiple allocations" {
    const allocator = std.testing.allocator;

    var objects: [10]AllocatedChild = undefined;

    for (&objects, 0..) |*obj, i| {
        obj.* = try AllocatedChild.init(allocator, i * 10, i * 20);
    }

    defer {
        for (&objects) |*obj| {
            obj.deinit(allocator);
        }
    }

    for (objects, 0..) |obj, i| {
        try std.testing.expectEqual(i * 10, obj.super.data.len);
        try std.testing.expectEqual(i * 20, obj.child_data.len);
    }
}

test "no memory leaks - array list of inherited objects" {
    const allocator = std.testing.allocator;

    var list: std.ArrayList(AllocatedChild) = .empty;
    defer {
        for (list.items) |*item| {
            item.deinit(allocator);
        }
        list.deinit(allocator);
    }

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const child = try AllocatedChild.init(allocator, 10, 20);
        try list.append(allocator, child);
    }

    try std.testing.expectEqual(@as(usize, 100), list.items.len);

    for (list.items) |item| {
        try std.testing.expectEqual(@as(usize, 10), item.super.data.len);
        try std.testing.expectEqual(@as(usize, 20), item.child_data.len);
    }
}

test "stack allocation - no heap usage" {
    // These objects are stack-allocated, no heap usage
    const Simple = struct {
        value: u32,

        pub inline fn get_value(self: *const @This()) u32 {
            return self.value;
        }
    };

    const SimpleChild = struct {
        super: Simple,
        value: u32,
        child_value: u32,

        pub inline fn get_value(self: *const @This()) u32 {
            return self.value;
        }
    };

    const obj = SimpleChild{
        .super = Simple{ .value = 10 },
        .value = 10,
        .child_value = 20,
    };

    try std.testing.expectEqual(@as(u32, 10), obj.get_value());
    try std.testing.expectEqual(@as(u32, 20), obj.child_value);
}

test "large stack allocation" {
    // Test large structs on stack
    const LargeParent = struct {
        data: [1000]u8 = undefined,
        count: usize,

        pub inline fn get_count(self: *const @This()) usize {
            return self.count;
        }
    };

    const LargeChild = struct {
        super: LargeParent,
        count: usize,
        child_data: [2000]u8 = undefined,

        pub inline fn get_count(self: *const @This()) usize {
            return self.count;
        }
    };

    var obj = LargeChild{
        .super = LargeParent{ .count = 1000 },
        .count = 1000,
    };

    // Fill with data
    for (&obj.super.data, 0..) |*byte, i| {
        byte.* = @intCast(i % 256);
    }

    for (&obj.child_data, 0..) |*byte, i| {
        byte.* = @intCast(i % 256);
    }

    try std.testing.expectEqual(@as(usize, 1000), obj.get_count());
    try std.testing.expectEqual(@as(u8, 0), obj.super.data[0]);
    try std.testing.expectEqual(@as(u8, 255), obj.super.data[255]);
    try std.testing.expectEqual(@as(u8, 0), obj.child_data[0]);
}
