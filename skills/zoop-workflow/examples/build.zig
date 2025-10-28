const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zoop_dep = b.dependency("zoop", .{});
    const zoop = zoop_dep.module("zoop");

    // Add zoop codegen step
    const zoop_exe = zoop_dep.artifact("zoop-codegen");
    const zoop_step = @import("zoop").addZoopCodegenFromBinary(b, zoop_exe, .{
        .source_dir = "zoop_src",
        .output_dir = "src",
    });

    // Build executable
    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.step.dependOn(zoop_step); // Run codegen before build
    exe.root_module.addImport("zoop", zoop);

    b.installArtifact(exe);

    // Add test step
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    unit_tests.step.dependOn(zoop_step);
    unit_tests.root_module.addImport("zoop", zoop);

    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);

    // Add cache cleaning step
    _ = @import("zoop").addCleanCacheStep(b);
}
