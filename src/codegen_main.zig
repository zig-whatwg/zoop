//! # zoop-codegen - Command-line code generator for Zoop
//!
//! This is the main entry point for the `zoop-codegen` executable, which scans
//! Zig source files for `zoop.class()` declarations and generates enhanced code
//! with inheritance, properties, and method wrappers.
//!
//! ## Usage
//!
//! ```bash
//! zoop-codegen --source-dir src --output-dir .zig-cache/zoop-generated
//! ```
//!
//! ## Command-Line Interface
//!
//! ### Required Arguments
//!
//! - `--source-dir <dir>` - Directory to scan for `.zig` files containing `zoop.class()`
//! - `--output-dir <dir>` - Directory where generated code will be written
//!
//! ### Optional Arguments
//!
//! - `--method-prefix <str>` - Prefix for inherited method wrappers (default: "call_")
//! - `--getter-prefix <str>` - Prefix for property getters (default: "get_")
//! - `--setter-prefix <str>` - Prefix for property setters (default: "set_")
//! - `-h, --help` - Show help message
//!
//! ## Security
//!
//! This tool includes path traversal protection:
//!
//! - **Blocks** paths containing `..` (error)
//! - **Warns** about absolute paths (allows but warns)
//! - Only processes files within specified directories
//!
//! This prevents malicious source files from causing the generator to read/write
//! outside intended directories.
//!
//! ## Integration
//!
//! Typically called from build.zig:
//!
//! ```zig
//! const codegen_exe = zoop_dep.artifact("zoop-codegen");
//! const gen_cmd = b.addRunArtifact(codegen_exe);
//! gen_cmd.addArgs(&.{
//!     "--source-dir", "src",
//!     "--output-dir", ".zig-cache/zoop-generated",
//!     "--method-prefix", "call_",
//! });
//! exe.step.dependOn(&gen_cmd.step);
//! ```
//!
//! See CONSUMER_USAGE.md for complete integration examples.

const std = @import("std");
const codegen = @import("codegen.zig");

/// Main entry point for zoop-codegen executable.
///
/// Parses command-line arguments, validates paths for security, and invokes
/// the code generation engine.
///
/// ## Process
///
/// 1. Parse command-line arguments
/// 2. Validate required arguments present
/// 3. Security check: validate paths for traversal attempts
/// 4. Invoke codegen.generateAllClasses()
/// 5. Report success or error
///
/// ## Exit Codes
///
/// - 0: Success
/// - Non-zero: Error (missing args, invalid paths, generation failure, etc.)
///
/// ## Errors
///
/// Returns error if:
/// - Missing required arguments (--source-dir, --output-dir)
/// - Unknown arguments provided
/// - Path traversal detected (`..` in paths)
/// - Code generation fails (invalid syntax, I/O errors, etc.)
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("ERROR: Memory leak detected in zoop-codegen!\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.next();

    // Initialize configuration with defaults
    var config = codegen.ClassConfig{};
    var source_dir: ?[]const u8 = null;
    var output_dir: ?[]const u8 = null;

    // Parse command-line arguments
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

    // Security: Validate paths for path traversal attempts
    const src = source_dir.?;
    const out = output_dir.?;

    // Block parent directory references (path traversal attacks)
    if (std.mem.indexOf(u8, src, "..") != null) {
        std.debug.print("Error: Source directory contains '..' - path traversal not allowed: {s}\n", .{src});
        std.debug.print("For security reasons, paths with '..' are not permitted.\n", .{});
        std.debug.print("Use absolute paths or paths without '..' instead.\n", .{});
        return error.UnsafePath;
    }

    if (std.mem.indexOf(u8, out, "..") != null) {
        std.debug.print("Error: Output directory contains '..' - path traversal not allowed: {s}\n", .{out});
        std.debug.print("For security reasons, paths with '..' are not permitted.\n", .{});
        std.debug.print("Use absolute paths or paths without '..' instead.\n", .{});
        return error.UnsafePath;
    }

    // Warn about absolute paths (allowed but potentially surprising)
    if ((src.len > 0 and src[0] == '/') or (src.len >= 2 and src[1] == ':')) {
        std.debug.print("Warning: Using absolute path for source directory: {s}\n", .{src});
    }

    if ((out.len > 0 and out[0] == '/') or (out.len >= 2 and out[1] == ':')) {
        std.debug.print("Warning: Using absolute path for output directory: {s}\n", .{out});
    }

    std.debug.print("[zoop-codegen] Scanning {s} for class definitions...\n", .{source_dir.?});

    codegen.generateAllClasses(
        allocator,
        source_dir.?,
        output_dir.?,
        config,
    ) catch |err| {
        std.debug.print("ERROR: Code generation failed: {}\n", .{err});
        std.debug.print("Please check the error messages above for details.\n", .{});
        return err;
    };

    std.debug.print("[zoop-codegen] ✓ Generated classes in {s}\n", .{output_dir.?});
}

/// Print command-line help message.
///
/// Displays usage instructions, argument descriptions, and examples.
fn printHelp() void {
    std.debug.print(
        \\zoop-codegen - Automatic OOP code generator for Zig
        \\
        \\Scans Zig source files for zoop.class() declarations and generates enhanced
        \\code with inheritance, properties, and zero-cost method wrappers.
        \\
        \\USAGE:
        \\    zoop-codegen --source-dir <dir> --output-dir <dir> [OPTIONS]
        \\
        \\REQUIRED ARGUMENTS:
        \\    --source-dir <dir>      Directory to scan for class definitions
        \\                            Must contain .zig files with zoop.class() calls
        \\
        \\    --output-dir <dir>      Directory to write generated code
        \\                            Creates same directory structure as source
        \\
        \\OPTIONAL ARGUMENTS:
        \\    --method-prefix <str>   Prefix for inherited methods (default: "call_")
        \\                            Example: employee.call_greet()
        \\
        \\    --getter-prefix <str>   Prefix for property getters (default: "get_")
        \\                            Example: user.get_email()
        \\
        \\    --setter-prefix <str>   Prefix for property setters (default: "set_")
        \\                            Example: user.set_email("new@...")
        \\
        \\    -h, --help              Show this help message
        \\
        \\EXAMPLES:
        \\    # Standard usage with default prefixes
        \\    zoop-codegen --source-dir src --output-dir .zig-cache/zoop-generated
        \\
        \\    # Custom prefixes for different naming conventions
        \\    zoop-codegen --source-dir src --output-dir generated \
        \\        --method-prefix "invoke_" \
        \\        --getter-prefix "read_" \
        \\        --setter-prefix "write_"
        \\
        \\    # No prefixes (empty strings)
        \\    zoop-codegen --source-dir src --output-dir generated \
        \\        --method-prefix "" \
        \\        --getter-prefix "" \
        \\        --setter-prefix ""
        \\
        \\    # Manual generation workflow (review before merging)
        \\    zoop-codegen --source-dir .codegen-input --output-dir src-generated
        \\    diff -r src/ src-generated/  # Review changes
        \\    # Manually merge updates, then:
        \\    rm -rf src-generated/
        \\
        \\SECURITY:
        \\    - Paths containing '..' are blocked (path traversal protection)
        \\    - Absolute paths are allowed but generate warnings
        \\    - Only processes files within specified directories
        \\
        \\SEE ALSO:
        \\    README.md         - Overview and quick start
        \\    CONSUMER_USAGE.md - Integration patterns and workflows
        \\    API_REFERENCE.md  - Complete API documentation
        \\
    , .{});
}
