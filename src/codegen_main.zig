const std = @import("std");
const codegen = @import("codegen.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.next();

    // Parse arguments
    var config = codegen.ClassConfig{};
    var source_dir: ?[]const u8 = null;
    var output_dir: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--source-dir")) {
            source_dir = args.next() orelse {
                std.debug.print("Error: --source-dir requires a value\n", .{});
                return error.MissingValue;
            };
        } else if (std.mem.eql(u8, arg, "--output-dir")) {
            output_dir = args.next() orelse {
                std.debug.print("Error: --output-dir requires a value\n", .{});
                return error.MissingValue;
            };
        } else if (std.mem.eql(u8, arg, "--method-prefix")) {
            config.method_prefix = args.next() orelse {
                std.debug.print("Error: --method-prefix requires a value\n", .{});
                return error.MissingValue;
            };
        } else if (std.mem.eql(u8, arg, "--getter-prefix")) {
            config.getter_prefix = args.next() orelse {
                std.debug.print("Error: --getter-prefix requires a value\n", .{});
                return error.MissingValue;
            };
        } else if (std.mem.eql(u8, arg, "--setter-prefix")) {
            config.setter_prefix = args.next() orelse {
                std.debug.print("Error: --setter-prefix requires a value\n", .{});
                return error.MissingValue;
            };
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            return;
        } else {
            std.debug.print("Unknown argument: {s}\n", .{arg});
            printHelp();
            return error.UnknownArgument;
        }
    }

    // Validate required arguments
    if (source_dir == null or output_dir == null) {
        std.debug.print("Error: --source-dir and --output-dir are required\n\n", .{});
        printHelp();
        return error.MissingArguments;
    }

    // Validate paths for security
    const src = source_dir.?;
    const out = output_dir.?;

    // Check for parent directory references (path traversal)
    if (std.mem.indexOf(u8, src, "..") != null) {
        std.debug.print("Error: Source directory contains '..' - path traversal not allowed: {s}\n", .{src});
        std.debug.print("For security reasons, paths with '..' are not permitted.\n", .{});
        return error.UnsafePath;
    }

    if (std.mem.indexOf(u8, out, "..") != null) {
        std.debug.print("Error: Output directory contains '..' - path traversal not allowed: {s}\n", .{out});
        std.debug.print("For security reasons, paths with '..' are not permitted.\n", .{});
        return error.UnsafePath;
    }

    // Warn about absolute paths (but allow them)
    if ((src.len > 0 and src[0] == '/') or (src.len >= 2 and src[1] == ':')) {
        std.debug.print("Warning: Using absolute path for source directory: {s}\n", .{src});
    }

    if ((out.len > 0 and out[0] == '/') or (out.len >= 2 and out[1] == ':')) {
        std.debug.print("Warning: Using absolute path for output directory: {s}\n", .{out});
    }

    // Run code generation
    std.debug.print("[zoop-codegen] Scanning {s} for class definitions...\n", .{source_dir.?});

    try codegen.generateAllClasses(
        allocator,
        source_dir.?,
        output_dir.?,
        config,
    );

    std.debug.print("[zoop-codegen] ✓ Generated classes in {s}\n", .{output_dir.?});
}

fn printHelp() void {
    std.debug.print(
        \\zoop-codegen - Automatic OOP code generator for Zig
        \\
        \\USAGE:
        \\    zoop-codegen --source-dir <dir> --output-dir <dir> [OPTIONS]
        \\
        \\REQUIRED:
        \\    --source-dir <dir>      Directory to scan for class definitions
        \\    --output-dir <dir>      Directory to write generated code
        \\
        \\OPTIONS:
        \\    --method-prefix <str>   Prefix for inherited methods (default: "call_")
        \\    --getter-prefix <str>   Prefix for property getters (default: "get_")
        \\    --setter-prefix <str>   Prefix for property setters (default: "set_")
        \\    -h, --help             Show this help message
        \\
        \\EXAMPLES:
        \\    # Default prefixes
        \\    zoop-codegen --source-dir src --output-dir zig-cache/zoop-generated
        \\
        \\    # Custom prefixes
        \\    zoop-codegen --source-dir src --output-dir generated \
        \\        --method-prefix "" --getter-prefix "read_" --setter-prefix "write_"
        \\
        \\    # No prefixes
        \\    zoop-codegen --source-dir src --output-dir generated \
        \\        --method-prefix "" --getter-prefix "" --setter-prefix ""
        \\
    , .{});
}
