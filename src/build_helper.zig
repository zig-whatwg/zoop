const std = @import("std");
const Build = std.Build;

/// Options for zoop code generation
pub const ZoopOptions = struct {
    /// Directory containing zoop source files (e.g., "zoop_src")
    source_dir: []const u8,
    /// Directory where generated files will be written (e.g., "src")
    output_dir: []const u8,
    /// Prefix for property getter methods (default: "get_")
    getter_prefix: []const u8 = "get_",
    /// Prefix for property setter methods (default: "set_")
    setter_prefix: []const u8 = "set_",
};

/// Add zoop code generation step to your build
///
/// This creates a build step that runs zoop-codegen with caching enabled.
/// The step will only regenerate files that have changed or whose parent
/// classes have changed.
///
/// Example usage in build.zig:
/// ```zig
/// const zoop = @import("zoop");
///
/// pub fn build(b: *std.Build) void {
///     const target = b.standardTargetOptions(.{});
///     const optimize = b.standardOptimizeOption(.{});
///
///     // Add zoop codegen step
///     const zoop_step = zoop.addZoopCodegen(b, .{
///         .source_dir = "zoop_src",
///         .output_dir = "src",
///     });
///
///     // Run codegen before building
///     const exe = b.addExecutable(.{
///         .name = "myapp",
///         .root_source_file = b.path("src/main.zig"),
///         .target = target,
///         .optimize = optimize,
///     });
///     exe.step.dependOn(zoop_step);
///
///     b.installArtifact(exe);
/// }
/// ```
pub fn addZoopCodegen(b: *Build, options: ZoopOptions) *Build.Step {
    const zoop_codegen = b.addSystemCommand(&.{
        "zoop-codegen",
        "--source-dir",
        options.source_dir,
        "--output-dir",
        options.output_dir,
        "--getter-prefix",
        options.getter_prefix,
        "--setter-prefix",
        options.setter_prefix,
    });

    // Create a named step for clarity
    const codegen_step = b.step("codegen", "Generate code from zoop source files");
    codegen_step.dependOn(&zoop_codegen.step);

    return codegen_step;
}

/// Add zoop code generation using a locally built zoop-codegen binary
///
/// This is useful when developing zoop itself or when you want to use a
/// specific version of zoop-codegen built from source.
///
/// Example usage in build.zig:
/// ```zig
/// const zoop = @import("zoop");
///
/// pub fn build(b: *std.Build) void {
///     // Build zoop-codegen from source
///     const zoop_exe = b.addExecutable(.{
///         .name = "zoop-codegen",
///         .root_source_file = b.path("deps/zoop/src/codegen_main.zig"),
///         .target = b.host,
///     });
///
///     // Use the locally built binary
///     const zoop_step = zoop.addZoopCodegenFromBinary(b, zoop_exe, .{
///         .source_dir = "zoop_src",
///         .output_dir = "src",
///     });
///
///     // ... rest of build
/// }
/// ```
pub fn addZoopCodegenFromBinary(
    b: *Build,
    zoop_exe: *Build.Step.Compile,
    options: ZoopOptions,
) *Build.Step {
    const run_codegen = b.addRunArtifact(zoop_exe);
    run_codegen.addArgs(&.{
        "--source-dir",
        options.source_dir,
        "--output-dir",
        options.output_dir,
        "--getter-prefix",
        options.getter_prefix,
        "--setter-prefix",
        options.setter_prefix,
    });

    // Create a named step for clarity
    const codegen_step = b.step("codegen", "Generate code from zoop source files");
    codegen_step.dependOn(&run_codegen.step);

    return codegen_step;
}

/// Clear the zoop cache
///
/// This removes the cache manifest, forcing a full regeneration on the next build.
/// Useful when the cache gets corrupted or for troubleshooting.
///
/// Example usage in build.zig:
/// ```zig
/// const zoop = @import("zoop");
///
/// pub fn build(b: *std.Build) void {
///     // Add a "clean-cache" step
///     const clean_cache_step = zoop.addCleanCacheStep(b);
///
///     // Can be run with: zig build clean-cache
/// }
/// ```
pub fn addCleanCacheStep(b: *Build) *Build.Step {
    const clean_step = b.step("clean-cache", "Clear zoop cache manifest");

    const rm_cache = b.addSystemCommand(&.{
        "rm",
        "-f",
        ".zig-cache/zoop-manifest.json",
    });

    clean_step.dependOn(&rm_cache.step);

    return clean_step;
}
