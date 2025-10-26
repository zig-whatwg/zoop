const std = @import("std");
const testing = std.testing;

// Test to demonstrate string interning benefits
// This test shows that interning reduces memory usage by deduplicating strings

test "string interning - same pointer for duplicate strings" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    // Simulate a simple string pool
    var pool = std.StringHashMap(void).init(allocator);
    defer {
        var it = pool.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        pool.deinit();
    }

    // Function to intern a string
    const internString = struct {
        fn intern(p: *std.StringHashMap(void), alloc: std.mem.Allocator, str: []const u8) ![]const u8 {
            const gop = try p.getOrPut(str);
            if (!gop.found_existing) {
                const owned = try alloc.dupe(u8, str);
                gop.key_ptr.* = owned;
            }
            return gop.key_ptr.*;
        }
    }.intern;

    // Create two identical strings from different sources
    const str1 = "MyClass";
    const str2_buf = try allocator.alloc(u8, 7);
    defer allocator.free(str2_buf);
    @memcpy(str2_buf, "MyClass");

    // Intern both
    const interned1 = try internString(&pool, allocator, str1);
    const interned2 = try internString(&pool, allocator, str2_buf);

    // They should point to the same memory location
    try testing.expect(interned1.ptr == interned2.ptr);
    try testing.expectEqualStrings(interned1, interned2);

    // Pool should only have one entry
    try testing.expectEqual(@as(usize, 1), pool.count());
}

test "string interning - memory savings calculation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var pool = std.StringHashMap(void).init(allocator);
    defer {
        var it = pool.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        pool.deinit();
    }

    const internString = struct {
        fn intern(p: *std.StringHashMap(void), alloc: std.mem.Allocator, str: []const u8) ![]const u8 {
            const gop = try p.getOrPut(str);
            if (!gop.found_existing) {
                const owned = try alloc.dupe(u8, str);
                gop.key_ptr.* = owned;
            }
            return gop.key_ptr.*;
        }
    }.intern;

    // Simulate referencing the same class name 100 times
    // Without interning: 100 allocations × 20 bytes = 2000 bytes
    // With interning: 1 allocation × 20 bytes = 20 bytes
    const class_name = "SomeLongClassName123";

    var references: [100][]const u8 = undefined;
    for (&references) |*ref| {
        ref.* = try internString(&pool, allocator, class_name);
    }

    // All references should point to the same string
    for (references) |ref| {
        try testing.expect(ref.ptr == references[0].ptr);
    }

    // Pool should only have one entry (20 bytes)
    // vs 100 entries without interning (2000 bytes)
    try testing.expectEqual(@as(usize, 1), pool.count());
}

test "string interning - different strings get different pointers" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var pool = std.StringHashMap(void).init(allocator);
    defer {
        var it = pool.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        pool.deinit();
    }

    const internString = struct {
        fn intern(p: *std.StringHashMap(void), alloc: std.mem.Allocator, str: []const u8) ![]const u8 {
            const gop = try p.getOrPut(str);
            if (!gop.found_existing) {
                const owned = try alloc.dupe(u8, str);
                gop.key_ptr.* = owned;
            }
            return gop.key_ptr.*;
        }
    }.intern;

    const class1 = try internString(&pool, allocator, "ClassA");
    const class2 = try internString(&pool, allocator, "ClassB");
    const class3 = try internString(&pool, allocator, "ClassC");

    // Different strings should have different pointers
    try testing.expect(class1.ptr != class2.ptr);
    try testing.expect(class2.ptr != class3.ptr);
    try testing.expect(class1.ptr != class3.ptr);

    // Pool should have three entries
    try testing.expectEqual(@as(usize, 3), pool.count());
}

test "string interning - interned strings are identical" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var pool = std.StringHashMap(void).init(allocator);
    defer {
        var it = pool.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        pool.deinit();
    }

    const internString = struct {
        fn intern(p: *std.StringHashMap(void), alloc: std.mem.Allocator, str: []const u8) ![]const u8 {
            const gop = try p.getOrPut(str);
            if (!gop.found_existing) {
                const owned = try alloc.dupe(u8, str);
                gop.key_ptr.* = owned;
            }
            return gop.key_ptr.*;
        }
    }.intern;

    // Simulate class hierarchy
    const parent = try internString(&pool, allocator, "Animal");
    const child1_parent_ref = try internString(&pool, allocator, "Animal");
    const child2_parent_ref = try internString(&pool, allocator, "Animal");

    // All parent references should be the exact same pointer
    try testing.expect(parent.ptr == child1_parent_ref.ptr);
    try testing.expect(parent.ptr == child2_parent_ref.ptr);

    // Can use pointer equality instead of string comparison
    try testing.expect(@intFromPtr(parent.ptr) == @intFromPtr(child1_parent_ref.ptr));
}
