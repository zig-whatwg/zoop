const std = @import("std");

// Performance and benchmark tests

pub const SimpleParent = struct {
    value: u32,

    pub inline fn get_value(self: *const @This()) u32 {
        return self.value;
    }

    pub inline fn set_value(self: *@This(), val: u32) void {
        self.value = val;
    }

    pub inline fn compute(self: *const SimpleParent) u64 {
        return @as(u64, self.value) * 2;
    }
};

pub const SimpleChild = struct {
    super: SimpleParent,
    value: u32,
    child_value: u32,

    pub inline fn get_value(self: *const @This()) u32 {
        return self.value;
    }

    pub inline fn set_value(self: *@This(), val: u32) void {
        self.value = val;
    }

    pub inline fn call_compute(self: *const SimpleChild) u64 {
        return self.super.compute();
    }
};

test "performance - property access overhead" {
    var obj = SimpleChild{
        .super = SimpleParent{ .value = 100 },
        .value = 100,
        .child_value = 200,
    };

    const iterations = 1_000_000;
    var sum: u64 = 0;

    var timer = try std.time.Timer.start();

    // Test getter performance
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        sum += obj.get_value();
    }

    const elapsed = timer.read();

    // Verify computation happened
    try std.testing.expectEqual(@as(u64, 100 * iterations), sum);

    // Just verify it completed (don't fail on timing)
    std.debug.print("\nProperty getter: {} ns for {} iterations ({} ns/op)\n", .{
        elapsed,
        iterations,
        elapsed / iterations,
    });
}

test "performance - method call overhead" {
    const obj = SimpleChild{
        .super = SimpleParent{ .value = 100 },
        .value = 100,
        .child_value = 200,
    };

    const iterations = 1_000_000;
    var sum: u64 = 0;

    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        sum += obj.call_compute();
    }

    const elapsed = timer.read();

    try std.testing.expectEqual(@as(u64, 200 * iterations), sum);

    std.debug.print("Method call: {} ns for {} iterations ({} ns/op)\n", .{
        elapsed,
        iterations,
        elapsed / iterations,
    });
}

test "performance - direct field access vs getter" {
    var obj = SimpleChild{
        .super = SimpleParent{ .value = 100 },
        .value = 100,
        .child_value = 200,
    };

    const iterations = 1_000_000;
    var timer = try std.time.Timer.start();

    // Direct access
    var sum_direct: u64 = 0;
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        sum_direct += obj.value;
    }
    const elapsed_direct = timer.lap();

    // Getter access
    var sum_getter: u64 = 0;
    i = 0;
    while (i < iterations) : (i += 1) {
        sum_getter += obj.get_value();
    }
    const elapsed_getter = timer.lap();

    try std.testing.expectEqual(sum_direct, sum_getter);

    std.debug.print("Direct access: {} ns ({} ns/op)\n", .{ elapsed_direct, elapsed_direct / iterations });
    std.debug.print("Getter access: {} ns ({} ns/op)\n", .{ elapsed_getter, elapsed_getter / iterations });
    std.debug.print("Overhead: {} ns/op\n", .{@as(i64, @intCast(elapsed_getter / iterations)) - @as(i64, @intCast(elapsed_direct / iterations))});
}

test "performance - deep inheritance chain access" {
    const Level1 = struct {
        value: u32,
        pub inline fn get_value(self: *const @This()) u32 {
            return self.value;
        }
    };

    const Level2 = struct {
        super: Level1,
        value: u32,
        pub inline fn get_value(self: *const @This()) u32 {
            return self.value;
        }
    };

    const Level3 = struct {
        super: Level2,
        value: u32,
        pub inline fn get_value(self: *const @This()) u32 {
            return self.value;
        }
    };

    const Level4 = struct {
        super: Level3,
        value: u32,
        pub inline fn get_value(self: *const @This()) u32 {
            return self.value;
        }
    };

    const Level5 = struct {
        super: Level4,
        value: u32,
        pub inline fn get_value(self: *const @This()) u32 {
            return self.value;
        }
    };

    const obj = Level5{
        .super = Level4{
            .super = Level3{
                .super = Level2{
                    .super = Level1{ .value = 42 },
                    .value = 42,
                },
                .value = 42,
            },
            .value = 42,
        },
        .value = 42,
    };

    const iterations = 1_000_000;
    var sum: u64 = 0;

    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        sum += obj.get_value();
    }

    const elapsed = timer.read();

    try std.testing.expectEqual(@as(u64, 42 * iterations), sum);

    std.debug.print("Deep chain access (5 levels): {} ns for {} iterations ({} ns/op)\n", .{
        elapsed,
        iterations,
        elapsed / iterations,
    });
}

test "performance - object creation" {
    const iterations = 100_000;

    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const obj = SimpleChild{
            .super = SimpleParent{ .value = @intCast(i) },
            .value = @intCast(i),
            .child_value = @intCast(i * 2),
        };
        std.mem.doNotOptimizeAway(&obj);
    }

    const elapsed = timer.read();

    std.debug.print("Object creation: {} ns for {} iterations ({} ns/op)\n", .{
        elapsed,
        iterations,
        elapsed / iterations,
    });
}

test "performance - setter operations" {
    var obj = SimpleChild{
        .super = SimpleParent{ .value = 0 },
        .value = 0,
        .child_value = 0,
    };

    const iterations = 1_000_000;

    var timer = try std.time.Timer.start();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        obj.set_value(i);
    }

    const elapsed = timer.read();

    try std.testing.expectEqual(@as(u32, iterations - 1), obj.get_value());

    std.debug.print("Setter operations: {} ns for {} iterations ({} ns/op)\n", .{
        elapsed,
        iterations,
        elapsed / iterations,
    });
}

test "performance - array of objects access pattern" {
    var objects: [1000]SimpleChild = undefined;

    for (&objects, 0..) |*obj, i| {
        obj.* = SimpleChild{
            .super = SimpleParent{ .value = @intCast(i) },
            .value = @intCast(i),
            .child_value = @intCast(i * 2),
        };
    }

    const iterations = 10_000;
    var sum: u64 = 0;

    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        for (objects) |obj| {
            sum += obj.get_value();
        }
    }

    const elapsed = timer.read();

    const expected_sum_per_iter = (0 + 999) * 1000 / 2; // Sum of 0..999
    try std.testing.expectEqual(@as(u64, expected_sum_per_iter * iterations), sum);

    std.debug.print("Array access: {} ns for {} iterations ({} ns/op)\n", .{
        elapsed,
        iterations,
        elapsed / iterations,
    });
}

test "zero-cost abstraction verification" {
    // Verify that property getters compile to same code as direct access
    // This is a compile-time guarantee, but we can verify runtime behavior

    var obj = SimpleChild{
        .super = SimpleParent{ .value = 42 },
        .value = 42,
        .child_value = 84,
    };

    // These should be identical in performance
    const direct = obj.value;
    const via_getter = obj.get_value();

    try std.testing.expectEqual(direct, via_getter);

    // Inline functions should be completely optimized away
    // The getter should compile to exactly the same assembly as direct access
}
