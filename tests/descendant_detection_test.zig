const std = @import("std");
const codegen = @import("codegen");

test "descendant map detects all descendants" {
    const allocator = std.testing.allocator;

    var registry = codegen.GlobalRegistry.init(allocator);
    defer registry.deinit();

    // Create test file structure:
    // Entity (no parent)
    // ├─ NamedEntity extends Entity
    // │  └─ Player extends NamedEntity
    // └─ Item extends Entity

    const entity_source =
        \\const zoop = @import("zoop");
        \\pub const Entity = zoop.class(struct {
        \\    pub fn update(self: *Entity) void {
        \\        _ = self;
        \\    }
        \\});
    ;

    const named_entity_source =
        \\const zoop = @import("zoop");
        \\const Entity = @import("entity.zig").Entity;
        \\pub const NamedEntity = zoop.class(struct {
        \\    pub const extends = Entity;
        \\});
    ;

    const player_source =
        \\const zoop = @import("zoop");
        \\const NamedEntity = @import("named_entity.zig").NamedEntity;
        \\pub const Player = zoop.class(struct {
        \\    pub const extends = NamedEntity;
        \\});
    ;

    const item_source =
        \\const zoop = @import("zoop");
        \\const Entity = @import("entity.zig").Entity;
        \\pub const Item = zoop.class(struct {
        \\    pub const extends = Entity;
        \\});
    ;

    // Process each file
    var entity_output = std.ArrayList(u8).init(allocator);
    defer entity_output.deinit();
    try codegen.processSourceFile(allocator, entity_source, "entity.zig", entity_output.writer(), &registry);

    var named_entity_output = std.ArrayList(u8).init(allocator);
    defer named_entity_output.deinit();
    try codegen.processSourceFile(allocator, named_entity_source, "named_entity.zig", named_entity_output.writer(), &registry);

    var player_output = std.ArrayList(u8).init(allocator);
    defer player_output.deinit();
    try codegen.processSourceFile(allocator, player_source, "player.zig", player_output.writer(), &registry);

    var item_output = std.ArrayList(u8).init(allocator);
    defer item_output.deinit();
    try codegen.processSourceFile(allocator, item_source, "item.zig", item_output.writer(), &registry);

    // Build descendant map
    var descendant_map = try registry.buildDescendantMap();
    defer {
        var it = descendant_map.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        descendant_map.deinit();
    }

    // Verify Entity has both NamedEntity and Player, plus Item as descendants
    const entity_descendants = descendant_map.get("Entity") orelse {
        std.debug.print("Entity not found in descendant map\n", .{});
        return error.TestFailed;
    };
    try std.testing.expectEqual(@as(usize, 3), entity_descendants.items.len);

    var has_named_entity = false;
    var has_player = false;
    var has_item = false;
    for (entity_descendants.items) |descendant| {
        if (std.mem.eql(u8, descendant, "NamedEntity")) has_named_entity = true;
        if (std.mem.eql(u8, descendant, "Player")) has_player = true;
        if (std.mem.eql(u8, descendant, "Item")) has_item = true;
    }
    try std.testing.expect(has_named_entity);
    try std.testing.expect(has_player);
    try std.testing.expect(has_item);

    // Verify NamedEntity has only Player as descendant
    const named_entity_descendants = descendant_map.get("NamedEntity") orelse {
        std.debug.print("NamedEntity not found in descendant map\n", .{});
        return error.TestFailed;
    };
    try std.testing.expectEqual(@as(usize, 1), named_entity_descendants.items.len);
    try std.testing.expectEqualStrings("Player", named_entity_descendants.items[0]);

    // Verify Player and Item have no descendants
    try std.testing.expect(descendant_map.get("Player") == null);
    try std.testing.expect(descendant_map.get("Item") == null);
}
