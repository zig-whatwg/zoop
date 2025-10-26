const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: zig run format.zig -- <file.zig>\n", .{});
        std.debug.print("Formats a Zig file using 'zig fmt'\n", .{});
        return;
    }

    const file_path = args[1];

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "zig", "fmt", file_path },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        std.debug.print("Error formatting {s}:\n{s}\n", .{ file_path, result.stderr });
        return error.FormatFailed;
    }

    std.debug.print("Successfully formatted: {s}\n", .{file_path});
}
