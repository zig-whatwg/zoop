const std = @import("std");
const zoop = @import("zoop");

pub const Parent = zoop.class(struct {
    value: i32,

    pub fn init(value: i32) Parent {
        return Parent{ .value = value };
    }

    pub fn instanceMethod(self: *Parent) i32 {
        return self.value * 2;
    }

    pub fn staticMethod(x: i32) i32 {
        return x + 100;
    }

    pub fn anotherStatic() i32 {
        return 42;
    }
});

pub const Child = zoop.class(struct {
    pub const extends = Parent;
    extra: i32,

    pub fn init(value: i32, extra: i32) Child {
        return Child{
            .super = Parent.init(value),
            .extra = extra,
        };
    }

    pub fn childInstance(self: *Child) i32 {
        return self.extra * 3;
    }

    pub fn childStatic(y: i32) i32 {
        return y - 50;
    }
});
