const std = @import("std");
const codegen = @import("codegen");

test "empty class generates valid init without trailing comma" {
    const allocator = std.testing.allocator;

    // Generate code for empty parent
    const parent_source =
        \\pub const EventTarget = zoop.class(struct {
        \\    pub fn addEventListener(self: *EventTarget) void {
        \\        _ = self;
        \\    }
        \\});
    ;

    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    var registry = codegen.ClassRegistry.init(allocator);
    defer registry.deinit();

    try codegen.processSourceFile(allocator, parent_source, "test.zig", output.writer(), &registry);

    const generated = output.items;

    // Check that the generated init doesn't have invalid trailing comma
    // Should be: initFields(allocator, &.{});
    // NOT: initFields(allocator, &.{,});
    try std.testing.expect(std.mem.indexOf(u8, generated, "initFields(allocator, &.{,") == null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "initFields(allocator, &.{") != null);
}
