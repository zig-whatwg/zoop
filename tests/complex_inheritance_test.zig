const std = @import("std");

// Test complex inheritance scenarios

// Diamond-like inheritance (not true diamond since Zig doesn't support multiple inheritance)
// But we can test multiple children from same parent
pub const Base = struct {
    id: u32,
    name: []const u8,

    pub inline fn get_id(self: *const @This()) u32 {
        return self.id;
    }
    pub inline fn get_name(self: *const @This()) []const u8 {
        return self.name;
    }

    pub fn describe(self: *const Base) void {
        std.debug.print("Base: {s} ({})\n", .{ self.name, self.id });
    }
};

pub const BranchA = struct {
    super: Base,

    id: u32,
    name: []const u8,
    branch_a_data: u32,

    pub inline fn get_id(self: *const @This()) u32 {
        return self.id;
    }
    pub inline fn get_name(self: *const @This()) []const u8 {
        return self.name;
    }

    pub inline fn call_describe(self: *const BranchA) void {
        self.super.describe();
    }
};

pub const BranchB = struct {
    super: Base,

    id: u32,
    name: []const u8,
    branch_b_data: []const u8,

    pub inline fn get_id(self: *const @This()) u32 {
        return self.id;
    }
    pub inline fn get_name(self: *const @This()) []const u8 {
        return self.name;
    }

    pub inline fn call_describe(self: *const BranchB) void {
        self.super.describe();
    }
};

// Deep inheritance (5 levels)
pub const Level1 = struct {
    value1: u32,

    pub inline fn get_value1(self: *const @This()) u32 {
        return self.value1;
    }
};

pub const Level2 = struct {
    super: Level1,
    value1: u32,
    value2: u32,

    pub inline fn get_value1(self: *const @This()) u32 {
        return self.value1;
    }
    pub inline fn get_value2(self: *const @This()) u32 {
        return self.value2;
    }
};

pub const Level3 = struct {
    super: Level2,
    value1: u32,
    value2: u32,
    value3: u32,

    pub inline fn get_value1(self: *const @This()) u32 {
        return self.value1;
    }
    pub inline fn get_value2(self: *const @This()) u32 {
        return self.value2;
    }
    pub inline fn get_value3(self: *const @This()) u32 {
        return self.value3;
    }
};

pub const Level4 = struct {
    super: Level3,
    value1: u32,
    value2: u32,
    value3: u32,
    value4: u32,

    pub inline fn get_value1(self: *const @This()) u32 {
        return self.value1;
    }
    pub inline fn get_value2(self: *const @This()) u32 {
        return self.value2;
    }
    pub inline fn get_value3(self: *const @This()) u32 {
        return self.value3;
    }
    pub inline fn get_value4(self: *const @This()) u32 {
        return self.value4;
    }
};

pub const Level5 = struct {
    super: Level4,
    value1: u32,
    value2: u32,
    value3: u32,
    value4: u32,
    value5: u32,

    pub inline fn get_value1(self: *const @This()) u32 {
        return self.value1;
    }
    pub inline fn get_value2(self: *const @This()) u32 {
        return self.value2;
    }
    pub inline fn get_value3(self: *const @This()) u32 {
        return self.value3;
    }
    pub inline fn get_value4(self: *const @This()) u32 {
        return self.value4;
    }
    pub inline fn get_value5(self: *const @This()) u32 {
        return self.value5;
    }
};

test "multiple branches from same parent" {
    const branch_a = BranchA{
        .super = Base{
            .id = 1,
            .name = "Base-A",
        },
        .id = 1,
        .name = "Base-A",
        .branch_a_data = 100,
    };

    const branch_b = BranchB{
        .super = Base{
            .id = 2,
            .name = "Base-B",
        },
        .id = 2,
        .name = "Base-B",
        .branch_b_data = "data",
    };

    // Both branches inherit from Base
    try std.testing.expectEqual(@as(u32, 1), branch_a.get_id());
    try std.testing.expectEqual(@as(u32, 2), branch_b.get_id());

    // Both have their own data
    try std.testing.expectEqual(@as(u32, 100), branch_a.branch_a_data);
    try std.testing.expectEqualStrings("data", branch_b.branch_b_data);
}

test "deep inheritance - 5 levels" {
    const obj = Level5{
        .super = Level4{
            .super = Level3{
                .super = Level2{
                    .super = Level1{
                        .value1 = 1,
                    },
                    .value1 = 1,
                    .value2 = 2,
                },
                .value1 = 1,
                .value2 = 2,
                .value3 = 3,
            },
            .value1 = 1,
            .value2 = 2,
            .value3 = 3,
            .value4 = 4,
        },
        .value1 = 1,
        .value2 = 2,
        .value3 = 3,
        .value4 = 4,
        .value5 = 5,
    };

    // All properties accessible at deepest level
    try std.testing.expectEqual(@as(u32, 1), obj.get_value1());
    try std.testing.expectEqual(@as(u32, 2), obj.get_value2());
    try std.testing.expectEqual(@as(u32, 3), obj.get_value3());
    try std.testing.expectEqual(@as(u32, 4), obj.get_value4());
    try std.testing.expectEqual(@as(u32, 5), obj.get_value5());

    // Access through super chain
    try std.testing.expectEqual(@as(u32, 1), obj.super.super.super.super.value1);
}

test "property override at different levels" {
    // Test that each level can have its own copy of properties
    var obj = Level3{
        .super = Level2{
            .super = Level1{
                .value1 = 10,
            },
            .value1 = 20,
            .value2 = 200,
        },
        .value1 = 30,
        .value2 = 300,
        .value3 = 3000,
    };

    // Level3's properties are independent
    try std.testing.expectEqual(@as(u32, 30), obj.get_value1());
    try std.testing.expectEqual(@as(u32, 300), obj.get_value2());
    try std.testing.expectEqual(@as(u32, 3000), obj.get_value3());

    // Modify Level3's properties
    obj.value1 = 40;
    obj.value2 = 400;
    obj.value3 = 4000;

    try std.testing.expectEqual(@as(u32, 40), obj.get_value1());
    try std.testing.expectEqual(@as(u32, 400), obj.get_value2());
    try std.testing.expectEqual(@as(u32, 4000), obj.get_value3());

    // Parent properties unchanged
    try std.testing.expectEqual(@as(u32, 20), obj.super.value1);
    try std.testing.expectEqual(@as(u32, 10), obj.super.super.value1);
}

test "complex struct with many properties" {
    const ComplexParent = struct {
        prop1: []const u8,
        prop2: u32,
        prop3: bool,
        prop4: f64,
        prop5: []const u8,

        pub inline fn get_prop1(self: *const @This()) []const u8 {
            return self.prop1;
        }
        pub inline fn get_prop2(self: *const @This()) u32 {
            return self.prop2;
        }
        pub inline fn get_prop3(self: *const @This()) bool {
            return self.prop3;
        }
        pub inline fn get_prop4(self: *const @This()) f64 {
            return self.prop4;
        }
        pub inline fn get_prop5(self: *const @This()) []const u8 {
            return self.prop5;
        }
    };

    const ComplexChild = struct {
        super: ComplexParent,

        prop1: []const u8,
        prop2: u32,
        prop3: bool,
        prop4: f64,
        prop5: []const u8,
        prop6: i32,
        prop7: []const u8,
        prop8: u64,

        pub inline fn get_prop1(self: *const @This()) []const u8 {
            return self.prop1;
        }
        pub inline fn get_prop2(self: *const @This()) u32 {
            return self.prop2;
        }
        pub inline fn get_prop3(self: *const @This()) bool {
            return self.prop3;
        }
        pub inline fn get_prop4(self: *const @This()) f64 {
            return self.prop4;
        }
        pub inline fn get_prop5(self: *const @This()) []const u8 {
            return self.prop5;
        }
        pub inline fn get_prop6(self: *const @This()) i32 {
            return self.prop6;
        }
        pub inline fn get_prop7(self: *const @This()) []const u8 {
            return self.prop7;
        }
        pub inline fn get_prop8(self: *const @This()) u64 {
            return self.prop8;
        }
    };

    const obj = ComplexChild{
        .super = ComplexParent{
            .prop1 = "parent1",
            .prop2 = 1,
            .prop3 = true,
            .prop4 = 1.0,
            .prop5 = "parent5",
        },
        .prop1 = "child1",
        .prop2 = 2,
        .prop3 = false,
        .prop4 = 2.0,
        .prop5 = "child5",
        .prop6 = -100,
        .prop7 = "child7",
        .prop8 = 99999,
    };

    // All 8 properties accessible
    try std.testing.expectEqualStrings("child1", obj.get_prop1());
    try std.testing.expectEqual(@as(u32, 2), obj.get_prop2());
    try std.testing.expectEqual(false, obj.get_prop3());
    try std.testing.expectEqual(@as(f64, 2.0), obj.get_prop4());
    try std.testing.expectEqualStrings("child5", obj.get_prop5());
    try std.testing.expectEqual(@as(i32, -100), obj.get_prop6());
    try std.testing.expectEqualStrings("child7", obj.get_prop7());
    try std.testing.expectEqual(@as(u64, 99999), obj.get_prop8());
}

test "array of inherited objects" {
    var objects: [10]BranchA = undefined;

    for (&objects, 0..) |*obj, i| {
        obj.* = BranchA{
            .super = Base{
                .id = @intCast(i),
                .name = "Object",
            },
            .id = @intCast(i),
            .name = "Object",
            .branch_a_data = @intCast(i * 100),
        };
    }

    // Verify all objects
    for (objects, 0..) |obj, i| {
        try std.testing.expectEqual(@as(u32, @intCast(i)), obj.get_id());
        try std.testing.expectEqual(@as(u32, @intCast(i * 100)), obj.branch_a_data);
    }
}
