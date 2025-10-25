const std = @import("std");
const zoop = @import("zoop");

pub const Parent = zoop.class(struct {
    id: u64,
    name: []const u8,

    pub fn init(id_val: u64, name_val: []const u8) Parent {
        return Parent{
            .id = id_val,
            .name = name_val,
        };
    }

    pub fn deinit(self: *Parent, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }

    pub fn display(self: *const Parent) void {
        std.debug.print("Parent: {} - {s}\n", .{ self.id, self.name });
    }
});

pub const ChildWithInit = zoop.class(struct {
    pub const extends = Parent;

    value: i32,

    pub fn init(id_val: u64, name_val: []const u8, val: i32) ChildWithInit {
        return ChildWithInit{
            .super = Parent.init(id_val, name_val),
            .value = val,
        };
    }

    pub fn display(self: *const ChildWithInit) void {
        std.debug.print("ChildWithInit: {} - {s} (value: {})\n", .{
            self.super.id,
            self.super.name,
            self.value,
        });
    }
});

pub const ChildNoInit = zoop.class(struct {
    pub const extends = Parent;

    extra: bool,

    pub fn toggle(self: *ChildNoInit) void {
        self.extra = !self.extra;
    }
});
