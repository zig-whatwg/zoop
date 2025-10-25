const std = @import("std");
const testing = std.testing;

pub const Parent = struct {
    value: i32,

    pub fn instanceMethod(self: *Parent) i32 {
        return self.value * 2;
    }

    pub fn staticMethod(x: i32) i32 {
        return x + 100;
    }

    pub fn anotherStatic() i32 {
        return 42;
    }
};

pub const Child = struct {
    super: Parent,

    extra: i32,

    pub fn childInstance(self: *Child) i32 {
        return self.extra * 3;
    }

    pub fn childStatic(y: i32) i32 {
        return y - 50;
    }

    pub inline fn call_instanceMethod(self: *Child) i32 {
        return self.super.instanceMethod();
    }
};

test "instance method wrapper works" {
    var child = Child{
        .super = Parent{ .value = 10 },
        .extra = 5,
    };

    try testing.expectEqual(@as(i32, 20), child.call_instanceMethod());
}

test "child instance method works" {
    var child = Child{
        .super = Parent{ .value = 10 },
        .extra = 5,
    };

    try testing.expectEqual(@as(i32, 15), child.childInstance());
}

test "parent static methods work" {
    try testing.expectEqual(@as(i32, 150), Parent.staticMethod(50));
    try testing.expectEqual(@as(i32, 42), Parent.anotherStatic());
}

test "child static methods work" {
    try testing.expectEqual(@as(i32, 0), Child.childStatic(50));
}

test "child can call parent static methods" {
    try testing.expectEqual(@as(i32, 200), Parent.staticMethod(100));
}
