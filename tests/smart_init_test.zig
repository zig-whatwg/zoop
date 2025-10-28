const std = @import("std");
const testing = std.testing;
const zoop = @import("zoop");

test "smart init: inherits parent init signature and adds child fields" {
    // Base class with init that takes allocator
    const Base = zoop.class(struct {
        pub fn init(allocator: std.mem.Allocator) Base {
            _ = allocator;
            return Base{};
        }
    });
    
    // Child adds fields - should get init(allocator, id, name)
    const Child = zoop.class(struct {
        pub const extends = Base;
        id: u32,
        name: []const u8,
    });
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const child = Child.init(allocator, 42, "test");
    try testing.expectEqual(@as(u32, 42), child.id);
    try testing.expectEqualStrings("test", child.name);
}

test "smart init: three-level hierarchy with accumulated fields" {
    const Level1 = zoop.class(struct {
        pub fn init(allocator: std.mem.Allocator) Level1 {
            _ = allocator;
            return Level1{};
        }
    });
    
    const Level2 = zoop.class(struct {
        pub const extends = Level1;
        field2: u32,
    });
    
    const Level3 = zoop.class(struct {
        pub const extends = Level2;
        field3: []const u8,
    });
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const obj = Level3.init(allocator, 100, "hello");
    try testing.expectEqual(@as(u32, 100), obj.field2);
    try testing.expectEqualStrings("hello", obj.field3);
}

test "smart init: handles error unions from parent" {
    const Parent = zoop.class(struct {
        name: []const u8,
        
        pub fn init(allocator: std.mem.Allocator, name_val: []const u8) !Parent {
            const name_copy = try allocator.dupe(u8, name_val);
            return Parent{ .name = name_copy };
        }
        
        pub fn deinit(self: *Parent, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
        }
    });
    
    const Child = zoop.class(struct {
        pub const extends = Parent;
        value: i32,
    });
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var child = try Child.init(allocator, "test_name", 42);
    defer child.deinit(allocator);
    
    try testing.expectEqualStrings("test_name", child.name);
    try testing.expectEqual(@as(i32, 42), child.value);
}

test "smart init: user-defined init overrides smart generation" {
    const Base = zoop.class(struct {
        pub fn init(allocator: std.mem.Allocator) Base {
            _ = allocator;
            return Base{};
        }
    });
    
    const Custom = zoop.class(struct {
        pub const extends = Base;
        value: i32,
        
        // User provides custom init - should be used instead of smart init
        pub fn init(allocator: std.mem.Allocator) Custom {
            _ = allocator;
            return Custom{ .value = 999 };
        }
    });
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const custom = Custom.init(allocator);
    try testing.expectEqual(@as(i32, 999), custom.value);
}
