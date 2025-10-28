const std = @import("std");

// Import the generated code
const Entity = @import("output/input.zig").Entity;
const NamedEntity = @import("output/input.zig").NamedEntity;
const User = @import("output/input.zig").User;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Three-Level Inheritance Demo ===\n\n", .{});

    // Level 1: Entity
    std.debug.print("--- Level 1: Entity ---\n", .{});
    var entity = try Entity.init(allocator, 123);
    defer {} // No deinit needed - no string fields
    std.debug.print("Entity ID: {}\n\n", .{entity.get_id()});

    // Level 2: NamedEntity (inherits Entity's validation)
    std.debug.print("--- Level 2: NamedEntity ---\n", .{});
    var named = try NamedEntity.init(allocator, 456, "Alice");
    defer named.deinit();
    std.debug.print("NamedEntity ID: {}, Name: {s}\n\n", .{ named.id, named.name });

    // Level 3: User (inherits Entity's validation + adds email property)
    std.debug.print("--- Level 3: User ---\n", .{});
    var user = try User.init(allocator, 789, "Bob", true, "bob@example.com");
    defer user.deinit();
    std.debug.print("User ID: {}, Name: {s}, Active: {}, Email: {s}\n\n", .{
        user.id,
        user.name,
        user.active,
        user.get_email(),
    });

    // Demonstrate inherited validation at all levels
    std.debug.print("--- Validation Tests ---\n", .{});
    
    // Try invalid ID (0) - will fail at all levels
    if (Entity.init(allocator, 0)) |_| {
        std.debug.print("ERROR: Should have failed!\n", .{});
    } else |err| {
        std.debug.print("✓ Entity validation: {}\n", .{err});
    }
    
    if (NamedEntity.init(allocator, 0, "Test")) |_| {
        std.debug.print("ERROR: Should have failed!\n", .{});
    } else |err| {
        std.debug.print("✓ NamedEntity inherited validation: {}\n", .{err});
    }
    
    if (User.init(allocator, 0, "Test", true, "test@example.com")) |_| {
        std.debug.print("ERROR: Should have failed!\n", .{});
    } else |err| {
        std.debug.print("✓ User inherited validation: {}\n", .{err});
    }

    // Try ID too large (> 999999) - will fail at all levels
    if (User.init(allocator, 9999999, "Test", true, "test@example.com")) |_| {
        std.debug.print("ERROR: Should have failed!\n", .{});
    } else |err| {
        std.debug.print("✓ User inherited validation (too large): {}\n", .{err});
    }

    std.debug.print("\n=== All validations passed! ===\n", .{});
}
